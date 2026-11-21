import 'package:flutter_test/flutter_test.dart';

import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/appointment.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/employee_wallet.dart';
import 'package:datetime/data/models/employee_payroll.dart';
import 'package:datetime/data/repositories/employee_wallet_repository.dart';
import 'package:datetime/data/services/employee_wallet_service.dart';

void main() {
  group('employee wallet core — Datamonck', () {
    test('wallet derives commission from completed appointment finance documents', () {
      final db = AppDatabase();
      final appointment = db.appointments.firstWhere((item) => item.status == AppointmentStatus.pending);
      db.changeStatus(appointment, AppointmentStatus.completed);

      final finance = db.employeeFinanceEntries.where((item) => item.appointmentId == appointment.id).toList();
      final walletEntries = db.employeeWalletTransactions.where((item) => item.appointmentId == appointment.id).toList();
      expect(finance, isNotEmpty);
      expect(walletEntries.length, finance.where((item) => item.commissionAmount != 0).length);
      expect(walletEntries.every((item) => item.sourceFinanceEntryId != null && item.referenceId == item.sourceFinanceEntryId), isTrue);
      expect(walletEntries.fold<int>(0, (sum, item) => sum + item.amount),
          finance.fold<int>(0, (sum, item) => sum + item.commissionAmount));

      final wallet = db.walletFor(appointment.employeeId);
      expect(wallet.calculatedIncome, greaterThanOrEqualTo(0));
      expect(wallet.finalBalance, db.walletTransactionsFor(appointment.employeeId)
          .where((item) => item.status == EmployeeWalletTransactionStatus.posted)
          .fold<int>(0, (sum, item) => sum + item.amount));
    });

    test('salary, bonus, advance and deductions are sourced from payroll records and reconcile', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final now = DateTime.now();

      db.addPayrollAdjustment(PayrollAdjustment(
        id: 'wallet-core-bonus', employeeId: employee.id, amount: 250000,
        date: now, description: 'پاداش واقعی تست', createdBy: 'مدیر تست',
        status: PayrollRecordStatus.approved, bonusType: PayrollBonusType.performance,
      ));
      db.addPayrollAdvance(PayrollAdvance(
        id: 'wallet-core-advance', employeeId: employee.id, amount: 100000,
        requestedAt: now, paidAt: now, description: 'مساعده تست',
        status: AdvanceStatus.paid,
      ));
      db.addPayrollAdjustment(PayrollAdjustment(
        id: 'wallet-core-deduction', employeeId: employee.id, amount: 50000,
        date: now, description: 'کسورات تست', createdBy: 'مدیر تست',
        status: PayrollRecordStatus.approved, deductionType: PayrollDeductionType.agreed,
      ));

      expect(db.accruePayrollBaseToWallet(employee.id, at: now), greaterThanOrEqualTo(1));
      expect(db.accruePayrollBaseToWallet(employee.id, at: now), 0);

      final wallet = db.walletFor(employee.id);
      expect(wallet.summary.bonuses, greaterThanOrEqualTo(250000));
      expect(wallet.advances, greaterThanOrEqualTo(100000));
      expect(wallet.debtsAndDeductions, greaterThanOrEqualTo(150000));
      expect(wallet.summary.fixedSalaryIncome, greaterThan(0));
      expect(wallet.finalBalance, wallet.calculatedIncome - wallet.paymentsMade - wallet.debtsAndDeductions);
      expect(db.payrollAdjustments.singleWhere((item) => item.id == 'wallet-core-bonus').sourceWalletTransactionId, isNotNull);
      expect(db.payrollAdvances.singleWhere((item) => item.id == 'wallet-core-advance').sourceWalletTransactionId, isNotNull);
    });

    test('settlement writes linked immutable payment and salary-payment ledger document', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final start = DateTime(2000, 1, 1);
      final end = DateTime(2100, 1, 1);
      db.accruePayrollBaseToWallet(employee.id);
      final due = db.walletPeriodDue(employee.id, start, end);
      expect(due, greaterThan(0));

      final settlement = db.settleEmployeeWallet(
        employeeId: employee.id, periodStart: start, periodEnd: end,
        periodType: EmployeeWalletPeriodType.manual, paidAmount: 1000,
        idempotencyKey: 'wallet-core-settlement-once',
        method: EmployeeWalletPaymentMethod.pos, description: 'پرداخت آزمایشی',
      );
      final payment = db.employeeWalletPayments.singleWhere((item) => item.settlementId == settlement.id);
      final transaction = db.employeeWalletTransactions.singleWhere((item) => item.id == payment.walletTransactionId);

      expect(payment.amount, 1000);
      expect(payment.method, EmployeeWalletPaymentMethod.pos);
      expect(payment.receiptNumber, settlement.receiptNumber);
      expect(payment.idempotencyKey, settlement.idempotencyKey);
      expect(transaction.paymentId, payment.id);
      expect(transaction.settlementId, settlement.id);
      expect(transaction.referenceType, 'wallet_settlement');
      expect(transaction.amount, -payment.amount);
      expect(db.walletPeriodDue(employee.id, start, end), due - payment.amount);
      expect(() => db.settleEmployeeWallet(
        employeeId: employee.id, periodStart: start, periodEnd: end,
        periodType: EmployeeWalletPeriodType.manual, paidAmount: 1000,
        idempotencyKey: 'wallet-core-settlement-once',
      ), throwsStateError);
    });

    test('manual transaction API cannot fabricate commissions, refunds, payments or salary accrual', () {
      final db = AppDatabase();
      final employeeId = db.employees.first.id;
      for (final type in [
        EmployeeWalletTransactionType.commission,
        EmployeeWalletTransactionType.refund,
        EmployeeWalletTransactionType.salaryPayment,
        EmployeeWalletTransactionType.fixedSalary,
      ]) {
        expect(() => db.addWalletTransaction(
          employeeId: employeeId, amount: 1000, type: type,
          description: 'ثبت دستی غیرمجاز', idempotencyKey: 'manual-forbidden-${type.name}',
        ), throwsArgumentError);
      }
    });

    test('staff wallet access is employee-scoped and hides salary-only documents', () {
      final db = AppDatabase();
      db.switchMockAccount('demo-staff');
      final ownEmployeeId = db.currentAccessAccount.employeeId!;
      final otherEmployeeId = db.employees.firstWhere((item) => item.id != ownEmployeeId).id;

      final ownEntries = db.walletTransactionsFor(ownEmployeeId);
      expect(ownEntries.every((item) =>
          item.type == EmployeeWalletTransactionType.commission ||
          item.type == EmployeeWalletTransactionType.refund), isTrue);
      expect(() => db.walletFor(otherEmployeeId), throwsA(isA<AccessDeniedException>()));
      expect(() => db.walletPaymentsFor(ownEmployeeId), throwsA(isA<AccessDeniedException>()));
    });

    test('daily weekly monthly and manual period selectors use exact boundaries', () {
      final anchor = DateTime(2026, 11, 18, 14, 30);
      final daily = EmployeeWalletPeriod.select(type: EmployeeWalletPeriodType.daily, anchor: anchor);
      expect(daily.start, DateTime(2026, 11, 18));
      expect(daily.end, DateTime(2026, 11, 18, 23, 59, 59, 999, 999));

      final weekly = EmployeeWalletPeriod.select(type: EmployeeWalletPeriodType.weekly, anchor: anchor);
      expect(weekly.start.weekday, DateTime.monday);
      expect(weekly.end, weekly.start.add(const Duration(days: 7)).subtract(const Duration(microseconds: 1)));

      final monthly = EmployeeWalletPeriod.select(type: EmployeeWalletPeriodType.monthly, anchor: anchor);
      expect(monthly.start, DateTime(2026, 11, 1));
      expect(monthly.end, DateTime(2026, 12, 1).subtract(const Duration(microseconds: 1)));

      expect(() => EmployeeWalletPeriod.select(type: EmployeeWalletPeriodType.manual, anchor: anchor),
          throwsArgumentError);
      final manual = EmployeeWalletPeriod.select(
        type: EmployeeWalletPeriodType.manual, anchor: anchor,
        manualStart: DateTime(2026, 10, 1), manualEnd: DateTime(2026, 10, 31),
      );
      expect(manual.start, DateTime(2026, 10, 1));
      expect(manual.end, DateTime(2026, 10, 31));
    });

    test('repository and service expose computed wallet and debt report', () async {
      final db = AppDatabase();
      final repository = EmployeeWalletRepository(db);
      final service = EmployeeWalletService(repository);
      final employeeId = db.employees.first.id;
      final wallet = await service.calculate(employeeId);
      expect(wallet.employeeId, employeeId);
      expect(wallet.summary.balance, db.walletBalanceFor(employeeId));
      final report = await service.debtAndReceivables();
      expect(report.map((item) => item.employeeId), contains(employeeId));
    });
  });
}
