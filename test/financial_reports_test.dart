import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/business_finance.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/report_analytics.dart';
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
      expect(report.settlements, isNotEmpty);
      expect(report.staffPaid, greaterThan(0));
      expect(report.paymentsByMethod.length, BusinessPaymentMethod.values.length);
    });
  });
}
