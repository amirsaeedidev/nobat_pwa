import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/business_finance.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/report_analytics.dart';
import 'package:datetime/data/models/employee_wallet.dart';
import 'package:datetime/data/models/employee_finance.dart';
import 'package:datetime/data/models/employee_service_config.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';

void main() {
  group('Supabase business finance model mapping', () {
    test('maps a refund receipt using database field names and signed amount', () {
      final payment = AppointmentPayment.fromJson({
        'id': 'payment-1',
        'appointment_id': 'appointment-1',
        'customer_id': 'customer-1',
        'amount_toman': 125000,
        'method': 'bank_transfer',
        'payment_type': 'refund',
        'description': 'برگشت وجه',
        'reverses_payment_id': 'payment-original',
        'idempotency_key': 'refund-idempotency-1',
        'created_at': '2026-11-25T09:30:00Z',
      });

      expect(payment.amount, 125000);
      expect(payment.method, BusinessPaymentMethod.bankTransfer);
      expect(payment.type, BusinessPaymentType.refund);
      expect(payment.signedAmount, -125000);
      expect(payment.reversesPaymentId, 'payment-original');
    });

    test('maps posted and reversed expenses from Supabase columns', () {
      final expense = BusinessExpense.fromJson({
        'id': 'expense-1',
        'amount_toman': 640000,
        'category': 'utilities',
        'description': 'قبض مجموعه',
        'source_document_id': null,
        'status': 'reversed',
        'created_by': 'actor-1',
        'created_at': '2026-11-25T08:00:00Z',
        'expense_date': '2026-11-24',
        'payment_method': 'pos',
        'idempotency_key': 'expense-idempotency-1',
        'related_appointment_id': null,
        'related_customer_id': null,
        'reversed_at': '2026-11-25T09:00:00Z',
        'reversed_by': 'actor-1',
        'reversal_reason': 'ثبت اشتباه',
      });

      expect(expense.amount, 640000);
      expect(expense.category, BusinessExpenseCategory.utilities);
      expect(expense.status, BusinessExpenseStatus.reversed);
      expect(expense.sourceDocumentId, isNull);
      expect(expense.expenseDate, DateTime(2026, 11, 24));
      expect(expense.paymentMethod, BusinessPaymentMethod.pos);
      expect(expense.reversalReason, 'ثبت اشتباه');
    });
  });

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

      // Every non-zero commission/refund document must have exactly one
      // immutable wallet mirror, and both ledgers must reconcile after refund.
      final appointmentFinance = db.employeeFinanceEntries
          .where((entry) => entry.appointmentId == pending.id)
          .toList();
      final expectedWalletCommission = appointmentFinance.fold<int>(
        0, (sum, entry) => sum + entry.commissionAmount,
      );
      final mirroredWalletEntries = db.employeeWalletTransactions.where((wallet) =>
          appointmentFinance.any((entry) => entry.id == wallet.sourceFinanceEntryId));
      expect(
        mirroredWalletEntries.length,
        appointmentFinance.where((entry) => entry.commissionAmount != 0).length,
      );
      expect(
        mirroredWalletEntries.fold<int>(0, (sum, entry) => sum + entry.amount),
        expectedWalletCommission,
      );
      expect(report.collectedRevenue, db.appointmentPayments.fold<int>(0, (sum, item) => sum + item.signedAmount));
    });

    test('combined payment-method and settlement-status filters stay on their source ledgers', () async {
      final db = AppDatabase();
      // Use a completed appointment without a seeded receipt so this
      // filter test exercises a valid collection instead of attempting to
      // over-collect an already settled Datamonck appointment.
      final appointment = db.appointments.firstWhere((item) => item.status == AppointmentStatus.pending);
      db.changeStatus(appointment, AppointmentStatus.completed);
      db.recordAppointmentPayment(
        appointmentId: appointment.id,
        amount: 1,
        method: BusinessPaymentMethod.cash,
        description: 'گزارش فیلتر روش پرداخت',
        idempotencyKey: 'report-filter-cash-${appointment.id}',
      );

      final employee = db.employees.first;
      db.accruePayrollBaseToWallet(employee.id);
      final start = DateTime(2000, 1, 1);
      final end = DateTime(2100, 1, 1);
      final due = db.walletPeriodDue(employee.id, start, end);
      expect(due, greaterThan(1));
      final settlement = db.settleEmployeeWallet(
        employeeId: employee.id,
        periodStart: start,
        periodEnd: end,
        periodType: EmployeeWalletPeriodType.manual,
        paidAmount: due ~/ 2,
        idempotencyKey: 'report-filter-partial-settlement',
      );
      expect(settlement.status, EmployeeWalletSettlementStatus.partial);

      final report = await MockDashboardRepository(db).fetchReportAnalytics(
        range: allTime(),
        filter: const ReportAnalyticsFilter(
          paymentMethod: 'cash',
          settlementStatus: EmployeeWalletSettlementStatus.partial,
        ),
      );
      expect(report.paymentTransactions, isNotEmpty);
      expect(report.paymentTransactions.every((item) => item.method == BusinessPaymentMethod.cash), isTrue);
      expect(report.settlements, isNotEmpty);
      expect(report.settlements.every((item) => item.status == EmployeeWalletSettlementStatus.partial), isTrue);
    });

    test('service commission override is snapshotted and honored over fixed monthly default', () {
      final db = AppDatabase();
      final source = db.appointments.firstWhere((item) => item.status == AppointmentStatus.pending);
      final serviceId = source.serviceIds.first;
      final service = db.serviceById(serviceId)!;
      final profile = db.payProfileFor(source.employeeId);
      db.savePayProfile(profile.copyWith(
        method: EmployeePaymentMethod.fixedMonthly,
        generalRateBps: 0,
      ));
      db.saveEmployeeServiceConfig(EmployeeServiceConfig(
        employeeId: source.employeeId,
        serviceId: serviceId,
        commissionRateBps: 1500,
        fixedCommissionAmount: 5000,
      ));

      final snapshot = <String, dynamic>{
        'service_id': serviceId,
        'title': service.title,
        'category': service.category,
        'price': 100000,
        'duration_minutes': 45,
        'commission_rate_bps': 1500,
        'fixed_commission_amount': 5000,
        'commission_basis': 'afterDiscount',
        'service_commission_override': true,
      };
      final appointment = source.copyWith(
        id: 'service-commission-override-test',
        reference: 'TEST-COMMISSION',
        serviceIds: [serviceId],
        serviceName: service.title,
        price: 100000,
        durationMinutes: 45,
        serviceSnapshots: [snapshot],
      );
      db.addAppointment(appointment);
      db.changeStatus(appointment, AppointmentStatus.completed);

      final entry = db.employeeFinanceEntries.singleWhere(
        (item) => item.appointmentId == appointment.id && item.serviceId == serviceId,
      );
      expect(entry.rateBps, 1500);
      expect(entry.fixedAmount, 5000);
      expect(entry.commissionAmount, 20000);
      expect(entry.companyShare, 80000);
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
      final employee = db.employees.first;
      db.accruePayrollBaseToWallet(employee.id);
      final settlementStart = DateTime(2000, 1, 1);
      final settlementEnd = DateTime(2100, 1, 1);
      final due = db.walletPeriodDue(employee.id, settlementStart, settlementEnd);
      if (due > 0) {
        db.settleEmployeeWallet(
          employeeId: employee.id,
          periodStart: settlementStart,
          periodEnd: settlementEnd,
          periodType: EmployeeWalletPeriodType.manual,
          paidAmount: due < 100000 ? due : 100000,
          idempotencyKey: 'financial-report-wallet-settlement',
        );
      }
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
      expect(report.walletTransactions, isNotEmpty);
      final visibleWallets = db.employees.where((item) => db.hasPermission('finance.salary.view', employeeId: item.id))
          .map((item) => db.walletFor(item.id)).toList();
      final expectedWalletPayable = visibleWallets.fold<int>(0, (sum, wallet) => sum + wallet.payableBalance);
      final expectedWalletDebt = visibleWallets.fold<int>(0, (sum, wallet) => sum + wallet.debt);
      expect(report.staffPayable, expectedWalletPayable);
      expect(report.staffDebt, expectedWalletDebt);
      expect(report.paymentsByMethod.length, BusinessPaymentMethod.values.length);
    });
  });
}
