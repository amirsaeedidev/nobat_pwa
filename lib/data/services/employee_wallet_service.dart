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

  Future<int> payableFor(String employeeId, EmployeeWalletPeriod period) async {
    final entries = await repository.fetchTransactions(employeeId, from: period.start, to: period.end);
    final summary = EmployeeWalletSummary.fromTransactions(entries);
    return summary.payableBalance;
  }

  Future<EmployeeWalletSettlement> settle({
    required String employeeId, required EmployeeWalletPeriod period,
    required int amount, required String idempotencyKey,
    EmployeeWalletPaymentMethod method = EmployeeWalletPaymentMethod.bankTransfer,
  }) => repository.settle(
    employeeId: employeeId, period: period, paidAmount: amount,
    idempotencyKey: idempotencyKey, method: method,
  );

  Future<List<EmployeeWallet>> debtAndReceivables() => repository.fetchDebtAndReceivableReport();
}
