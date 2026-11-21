import '../models/employee_wallet.dart';
import '../repositories/employee_wallet_repository.dart';

/// بازه مالی قطعی برای محاسبه، گزارش و تسویه کیف پول.
class EmployeeWalletPeriod {
  const EmployeeWalletPeriod({required this.type, required this.start, required this.end});
  final EmployeeWalletPeriodType type;
  final DateTime start;
  final DateTime end;

  factory EmployeeWalletPeriod.select({
    required EmployeeWalletPeriodType type,
    required DateTime anchor,
    DateTime? manualStart,
    DateTime? manualEnd,
  }) {
    final day = DateTime(anchor.year, anchor.month, anchor.day);
    switch (type) {
      case EmployeeWalletPeriodType.daily:
        return EmployeeWalletPeriod(type: type, start: day, end: day.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1)));
      case EmployeeWalletPeriodType.weekly:
        final start = day.subtract(Duration(days: day.weekday - DateTime.monday));
        return EmployeeWalletPeriod(type: type, start: start, end: start.add(const Duration(days: 7)).subtract(const Duration(microseconds: 1)));
      case EmployeeWalletPeriodType.monthly:
        final start = DateTime(anchor.year, anchor.month, 1);
        return EmployeeWalletPeriod(type: type, start: start, end: DateTime(anchor.year, anchor.month + 1, 1).subtract(const Duration(microseconds: 1)));
      case EmployeeWalletPeriodType.manual:
        if (manualStart == null || manualEnd == null || manualEnd.isBefore(manualStart)) {
          throw ArgumentError('برای تسویه دستی باید بازه شروع و پایان معتبر انتخاب شود.');
        }
        return EmployeeWalletPeriod(type: type, start: manualStart, end: manualEnd);
    }
  }
}

/// منطق کاربردی کیف پول؛ محاسبات تجمیعی فقط از دفتر کل مشترک خوانده می‌شوند.
class EmployeeWalletService {
  EmployeeWalletService(this.repository);
  final EmployeeWalletRepository repository;

  Future<EmployeeWallet> calculate(String employeeId, {DateTime? at}) =>
      repository.fetchWallet(employeeId, at: at);
  EmployeeWallet readWallet(String employeeId, {DateTime? at}) => repository.readWallet(employeeId, at: at);
  List<EmployeeWalletTransaction> readTransactions(String employeeId, {DateTime? from, DateTime? to}) =>
      repository.readTransactions(employeeId, from: from, to: to);
  List<EmployeeWalletSettlement> readSettlements(String employeeId) => repository.readSettlements(employeeId);
  List<EmployeeWalletPayment> readPayments(String employeeId) => repository.readPayments(employeeId);
  List<EmployeeWallet> readDebtAndReceivables() => repository.readDebtAndReceivables();
  int readPeriodDue(String employeeId, DateTime start, DateTime end) => repository.readPeriodDue(employeeId, start, end);

  Future<int> payableFor(String employeeId, EmployeeWalletPeriod period) async =>
      repository.calculatePeriodDue(employeeId, period.start, period.end);

  Future<int> accruePayroll(String employeeId, {DateTime? at}) =>
      repository.accruePayroll(employeeId, at: at);

  Future<EmployeeWalletTransaction> recordTransaction({
    required String employeeId, required int amount,
    required EmployeeWalletTransactionType type, required String description,
    required String idempotencyKey, String? referenceType, String? referenceId,
  }) => repository.recordTransaction(
    employeeId: employeeId, amount: amount, type: type, description: description,
    idempotencyKey: idempotencyKey, referenceType: referenceType, referenceId: referenceId,
  );

  Future<EmployeeWalletSettlement> settle({
    required String employeeId, required EmployeeWalletPeriod period,
    required int amount, required String idempotencyKey,
    EmployeeWalletPaymentMethod method = EmployeeWalletPaymentMethod.bankTransfer,
    String description = 'پرداخت تسویه پرسنل',
  }) => repository.settle(
    employeeId: employeeId, period: period, paidAmount: amount,
    idempotencyKey: idempotencyKey, method: method, description: description,
  );

  Future<List<EmployeeWallet>> debtAndReceivables() => repository.fetchDebtAndReceivableReport();
}
