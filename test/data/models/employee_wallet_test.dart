import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/employee_wallet.dart';

void main() {
  group('Employee wallet ledger', () {
    late AppDatabase db;
    late String employeeId;

    setUp(() {
      db = AppDatabase();
      employeeId = db.employees.first.id;
    });

    test('computes positive and negative balances from posted transactions', () {
      db.addWalletTransaction(employeeId: employeeId, amount: 500000, type: EmployeeWalletTransactionType.bonus, description: 'پاداش تست');
      expect(db.walletBalanceFor(employeeId), greaterThan(0));
      final debtEmployee = db.employees.last.id;
      db.addWalletTransaction(employeeId: debtEmployee, amount: -900000, type: EmployeeWalletTransactionType.advance, description: 'مساعده آزمایشی');
      expect(db.walletBalanceFor(debtEmployee), lessThan(0));
    });

    test('supports partial then full settlement and keeps both receipts', () {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
      db.addWalletTransaction(employeeId: employeeId, amount: 1000000, type: EmployeeWalletTransactionType.bonus, description: 'درآمد دوره', createdAt: now);
      final first = db.settleEmployeeWallet(employeeId: employeeId, periodStart: start, periodEnd: end, periodType: EmployeeWalletPeriodType.monthly, paidAmount: 300000, idempotencyKey: 'partial-once');
      expect(first.status, EmployeeWalletSettlementStatus.partial);
      expect(first.remainingAfter, 700000);
      final second = db.settleEmployeeWallet(employeeId: employeeId, periodStart: start, periodEnd: end, periodType: EmployeeWalletPeriodType.monthly, paidAmount: 700000, idempotencyKey: 'complete-once');
      expect(second.status, EmployeeWalletSettlementStatus.completed);
      expect(second.remainingAfter, 0);
      expect(db.walletSettlementsFor(employeeId).length, 2);
      expect(db.walletPeriodDue(employeeId, start, end), 0);
    });

    test('rejects overpayment and duplicate payment keys', () {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
      db.addWalletTransaction(employeeId: employeeId, amount: 200000, type: EmployeeWalletTransactionType.bonus, description: 'پاداش', createdAt: now);
      db.settleEmployeeWallet(employeeId: employeeId, periodStart: start, periodEnd: end, periodType: EmployeeWalletPeriodType.monthly, paidAmount: 100000, idempotencyKey: 'payment-key');
      expect(
        () => db.settleEmployeeWallet(employeeId: employeeId, periodStart: start, periodEnd: end, periodType: EmployeeWalletPeriodType.monthly, paidAmount: 100000, idempotencyKey: 'payment-key'),
        throwsStateError,
      );
      expect(
        () => db.settleEmployeeWallet(employeeId: employeeId, periodStart: start, periodEnd: end, periodType: EmployeeWalletPeriodType.monthly, paidAmount: 200000),
        throwsArgumentError,
      );
    });

    test('corrects a transaction using reversal and a new adjustment', () {
      final entry = db.addWalletTransaction(employeeId: employeeId, amount: 500000, type: EmployeeWalletTransactionType.bonus, description: 'پاداش اولیه');
      final before = db.walletBalanceFor(employeeId);
      final correction = db.correctWalletTransaction(transactionId: entry.id, correctedAmount: 350000, description: 'اصلاح مبلغ پاداش');
      expect(correction, hasLength(2));
      expect(correction.first.amount, -500000);
      expect(correction.last.amount, 350000);
      expect(db.walletBalanceFor(employeeId), before - 150000);
      expect(db.employeeWalletTransactions.any((item) => item.id == entry.id), isTrue);
      expect(() => db.correctWalletTransaction(transactionId: entry.id, correctedAmount: 1, description: 'اصلاح دوباره'), throwsStateError);
    });

    test('approved commissions are mirrored once and keep the original snapshot', () {
      final employee = db.employees.first;
      final appointment = db.appointments.firstWhere((item) => item.status.name == 'completed' && item.employeeId == employee.id);
      final finance = db.financeEntriesFor(employee.id).firstWhere((entry) => entry.appointmentId == appointment.id);
      final mirrored = db.employeeWalletTransactions.where((entry) => entry.sourceFinanceEntryId == finance.id).toList();
      expect(mirrored, hasLength(1));
      expect(mirrored.single.amount, finance.commissionAmount);
      final before = db.walletBalanceFor(employee.id);
      db.savePayProfile(db.payProfileFor(employee.id).copyWith(generalRateBps: 5000));
      expect(db.walletBalanceFor(employee.id), before);
      expect(db.employeeWalletTransactions.where((entry) => entry.sourceFinanceEntryId == finance.id), hasLength(1));
    });

    test('seeds varied financial histories for at least five employees', () {
      final withEntries = db.employees.where((employee) => db.walletTransactionsFor(employee.id).isNotEmpty).length;
      expect(withEntries, greaterThanOrEqualTo(5));
      expect(db.employeeWalletSettlements, isNotEmpty);
      expect(db.employeeWalletTransactions.any((entry) => entry.type == EmployeeWalletTransactionType.advance), isTrue);
      expect(db.employeeWalletTransactions.any((entry) => entry.type == EmployeeWalletTransactionType.bonus), isTrue);
      expect(db.employeeWalletTransactions.any((entry) => entry.type == EmployeeWalletTransactionType.deduction), isTrue);
    });
  });
}
