import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/business_finance.dart';
import 'package:datetime/data/models/employee_finance.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/report_analytics.dart';
import 'package:datetime/data/models/employee_wallet.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';

void main() {
  ReportDateRange allTime() => ReportDateRange.custom(
    JalaliDate.fromDateTime(DateTime(2000, 1, 1)),
    JalaliDate.fromDateTime(DateTime(2100, 1, 1)),
  );

  group('Datamonck financial reports', () {
    test('tracks partial receipt and refund without duplicating revenue or commission', () async {
      final db = AppDatabase();
      final pending = db.appointments.firstWhere((item) => item.status == AppointmentStatus.pending);
      db.changeStatus(pending, AppointmentStatus.completed);

      final receipt = db.recordAppointmentPayment(
        appointmentId: pending.id,
        amount: 100000,
        method: BusinessPaymentMethod.pos,
        description: 'دریافت بخشی از مبلغ',
        idempotencyKey: 'test-receipt-${pending.id}',
      );
      final refund = db.refundAppointmentPayment(
        paymentId: receipt.id,
        amount: 25000,
        description: 'برگشت بخشی از وجه',
        idempotencyKey: 'test-refund-${pending.id}',
      );

      expect(refund.signedAmount, -25000);
      expect(() => db.recordAppointmentPayment(
        appointmentId: pending.id,
        amount: 1000,
        method: BusinessPaymentMethod.cash,
        description: 'تکراری',
        idempotencyKey: 'test-receipt-${pending.id}',
      ), throwsStateError);

      final report = await MockDashboardRepository(db).fetchReportAnalytics(range: allTime());
      final financeEntries = db.employeeFinanceEntries.where((entry) =>
        entry.appointmentId == pending.id);
      final expectedRevenue = financeEntries.fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      final expectedCommission = financeEntries.fold<int>(0, (sum, entry) => sum + entry.commissionAmount);
      expect(report.revenue, db.employeeFinanceEntries.fold<int>(0, (sum, entry) => sum + entry.receivedAmount));
      expect(report.revenue, greaterThan(0));
      expect(report.commissionCost, db.employeeFinanceEntries.fold<int>(0, (sum, entry) => sum + entry.commissionAmount));
      expect(report.collectedRevenue, db.appointmentPayments.fold<int>(0, (sum, item) => sum + item.signedAmount));
      expect(report.paymentsByMethod.values.fold<num>(0, (sum, value) => sum + value), report.collectedRevenue);
      expect(report.cost, report.commissionCost + report.payrollCost + report.operatingExpense);
      expect(report.customerDebts.any((item) => item.customerId == pending.customerId), isTrue);
      expect(expectedRevenue, greaterThan(0));
      expect(expectedCommission, greaterThanOrEqualTo(0));
    });

    test('full refund reverses service revenue and cannot be re-collected', () async {
      final db = AppDatabase();
      final pending = db.appointments.firstWhere((item) => item.status == AppointmentStatus.pending);
      db.changeStatus(pending, AppointmentStatus.completed);
      final billable = db.employeeFinanceEntries.where((entry) =>
        entry.appointmentId == pending.id && entry.type.name == 'commission')
        .fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      final receipt = db.recordAppointmentPayment(
        appointmentId: pending.id,
        amount: billable,
        method: BusinessPaymentMethod.cash,
        description: 'تسویه کامل نمونه',
        idempotencyKey: 'full-receipt-${pending.id}',
      );
      db.refundAppointmentPayment(
        paymentId: receipt.id,
        amount: billable,
        description: 'برگشت کامل',
        idempotencyKey: 'full-refund-${pending.id}',
      );
      expect(() => db.recordAppointmentPayment(
        appointmentId: pending.id,
        amount: 1,
        method: BusinessPaymentMethod.cash,
        description: 'دریافت مجدد',
        idempotencyKey: 'recollect-${pending.id}',
      ), throwsArgumentError);
      final report = await MockDashboardRepository(db).fetchReportAnalytics(range: allTime());
      final appointmentRevenue = db.employeeFinanceEntries.where((entry) => entry.appointmentId == pending.id)
          .fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      expect(appointmentRevenue, 0);
      expect(report.collectedRevenue, db.appointmentPayments.fold<int>(0, (sum, item) => sum + item.signedAmount));
    });

    test('requires a source document and prevents duplicate expense documents', () {
      final db = AppDatabase();
      final expense = BusinessExpense(
        id: 'expense-test-1',
        createdAt: DateTime.now(),
        amount: 350000,
        category: BusinessExpenseCategory.supplies,
        description: 'خرید مواد مصرفی تست',
        sourceDocumentId: 'DOC-TEST-001',
        createdBy: 'مدیر تست',
      );
      db.addBusinessExpense(expense);
      expect(() => db.addBusinessExpense(BusinessExpense(
        id: 'expense-test-2',
        createdAt: DateTime.now(),
        amount: 100000,
        category: BusinessExpenseCategory.other,
        description: 'سند تکراری',
        sourceDocumentId: 'DOC-TEST-001',
        createdBy: 'مدیر تست',
      )), throwsStateError);
    });

    test('aggregates income, collection, operating costs, payroll and settlements from shared sources', () async {
      final db = AppDatabase();
      final report = await MockDashboardRepository(db).fetchReportAnalytics(range: allTime());
      final received = db.employeeFinanceEntries.fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      final collected = db.appointmentPayments.fold<int>(0, (sum, payment) => sum + payment.signedAmount);
      final operating = db.businessExpenses.where((item) => item.status == BusinessExpenseStatus.posted)
          .fold<int>(0, (sum, item) => sum + item.amount);
      expect(report.revenue, received);
      expect(report.collectedRevenue, collected);
      expect(report.operatingExpense, operating);
      expect(report.cost, report.commissionCost + report.payrollCost + operating);
      final expectedPayroll = db.employeeWalletTransactions.where((item) =>
        item.status == EmployeeWalletTransactionStatus.posted &&
        (item.type == EmployeeWalletTransactionType.fixedSalary ||
          item.type == EmployeeWalletTransactionType.bonus ||
          item.type == EmployeeWalletTransactionType.penalty ||
          item.type == EmployeeWalletTransactionType.deduction ||
          item.type == EmployeeWalletTransactionType.adjustment))
        .fold<int>(0, (sum, item) => sum + item.amount);
      expect(report.payrollCost, expectedPayroll);
      expect(report.settlements, isNotEmpty);
      expect(report.staffPaid, greaterThan(0));
      expect(report.paymentsByMethod.length, BusinessPaymentMethod.values.length);
    });

    test('completed service without receipt is revenue but not collected cash', () async {
      final db = AppDatabase();
      final appointment = db.appointments.firstWhere((item) => item.status == AppointmentStatus.pending);
      db.changeStatus(appointment, AppointmentStatus.completed);
      expect(db.appointmentPayments.where((item) => item.appointmentId == appointment.id), isEmpty);
      final serviceLedger = db.employeeFinanceEntries.where((entry) => entry.appointmentId == appointment.id);
      final recognized = serviceLedger.fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      final report = await MockDashboardRepository(db).fetchReportAnalytics(range: allTime());
      expect(recognized, appointment.price.round());
      expect(report.revenue, db.employeeFinanceEntries.fold<int>(0, (sum, entry) => sum + entry.receivedAmount));
      expect(report.collectedRevenue, db.appointmentPayments.fold<int>(0, (sum, item) => sum + item.signedAmount));
      expect(report.customerDebts.any((item) => item.customerId == appointment.customerId), isTrue);
    });

    test('discount and excess prepayment are validated before completion is committed', () {
      final db = AppDatabase();
      final template = db.appointments.first;
      final appointment = template.copyWith(
        id: 'discount-prepayment-check',
        reference: 'DISC-001',
        status: AppointmentStatus.pending,
        price: 100000,
        serviceIds: [db.services.first.id],
        serviceSnapshots: [{
          'service_id': db.services.first.id,
          'title': db.services.first.title,
          'price': 100000,
          'commission_rate_bps': 3000,
        }],
      );
      db.addAppointment(appointment);
      final receipt = db.recordAppointmentPayment(
        appointmentId: appointment.id, amount: 90000,
        method: BusinessPaymentMethod.pos, description: 'پیش‌پرداخت',
        idempotencyKey: 'discount-prepay-receipt',
      );
      expect(
        () => db.changeStatus(appointment, AppointmentStatus.completed, discountAmount: 20000),
        throwsStateError,
      );
      expect(db.appointmentById(appointment.id)!.status, AppointmentStatus.pending);
      db.refundAppointmentPayment(
        paymentId: receipt.id, amount: 10000, description: 'اصلاح پیش‌پرداخت',
        idempotencyKey: 'discount-prepay-refund',
      );
      db.changeStatus(appointment, AppointmentStatus.completed, discountAmount: 20000);
      final entry = db.employeeFinanceEntries.singleWhere((item) =>
        item.appointmentId == appointment.id && item.type == FinanceEntryType.commission);
      expect(entry.grossAmount, 100000);
      expect(entry.discountAmount, 20000);
      expect(entry.receivedAmount, 80000);
      expect(db.appointmentPayments.where((item) => item.appointmentId == appointment.id)
        .fold<int>(0, (sum, item) => sum + item.signedAmount), 80000);
    });

    test('cancellation and no-show require refunding collected money first', () {
      final db = AppDatabase();
      final template = db.appointments.first;
      final appointment = template.copyWith(
        id: 'cancel-with-payment', reference: 'CANCEL-001',
        status: AppointmentStatus.pending, price: 100000,
      );
      db.addAppointment(appointment);
      final receipt = db.recordAppointmentPayment(
        appointmentId: appointment.id, amount: 50000,
        method: BusinessPaymentMethod.cash, description: 'بیعانه',
        idempotencyKey: 'cancel-receipt',
      );
      expect(() => db.changeStatus(appointment, AppointmentStatus.cancelled), throwsStateError);
      db.refundAppointmentPayment(
        paymentId: receipt.id, amount: 50000, description: 'استرداد بیعانه',
        idempotencyKey: 'cancel-refund',
      );
      db.changeStatus(appointment, AppointmentStatus.cancelled);
      expect(db.appointmentById(appointment.id)!.status, AppointmentStatus.cancelled);
      expect(() => db.recordAppointmentPayment(
        appointmentId: appointment.id, amount: 1,
        method: BusinessPaymentMethod.cash, description: 'دریافت پس از لغو',
        idempotencyKey: 'cancel-after-refund',
      ), throwsStateError);
    });

    test('completed appointments cannot be financially rewritten or deleted', () {
      final db = AppDatabase();
      final appointment = db.appointments.firstWhere((item) => item.status == AppointmentStatus.pending);
      db.changeStatus(appointment, AppointmentStatus.completed);
      final completed = db.appointmentById(appointment.id)!;
      expect(() => db.updateAppointment(completed.copyWith(price: completed.price + 1000)), throwsStateError);
      expect(() => db.changeStatus(completed, AppointmentStatus.cancelled), throwsStateError);
      expect(() => db.deleteAppointment(completed.id), throwsStateError);
      expect(db.appointmentById(completed.id), isNotNull);
    });

    test('profit stays unverified until expense coverage and direct costs are complete', () async {
      final db = AppDatabase();
      final range = allTime();
      final repository = MockDashboardRepository(db);
      final initial = await repository.fetchReportAnalytics(range: range);
      expect(initial.profitIsComplete, isFalse);
      expect(initial.verifiedNetProfit, isNull);
      db.setBusinessExpenseRangeConfirmed(
        from: range.start, endExclusive: range.endExclusive, confirmed: true,
      );
      final afterConfirmation = await repository.fetchReportAnalytics(range: range);
      // نمونه‌های تاریخی بدون snapshot هزینه مستقیم نباید سود قطعی بسازند.
      expect(afterConfirmation.profitIsComplete, isFalse);
      expect(afterConfirmation.profitStatusNote, contains('هزینه مستقیم'));
    });
  });
}
