import '../mock/app_database.dart';
import '../models/employee_wallet.dart';
import '../models/employee_payroll.dart';
import 'operations_repository.dart';

/// قرارداد خواندن دفتر کل و اجرای عملیات مالی؛ تمام اعداد از AppDatabase مشترک استخراج می‌شوند.
class EmployeeWalletRepository {
  EmployeeWalletRepository(this.db, {OperationsRepository? operations})
      : _operations = operations ?? OperationsRepository(db);

  final AppDatabase db;
  final OperationsRepository _operations;

  /// Synchronous read-through methods for reactive screens; all values are derived from the local ledger.
  EmployeeWallet readWallet(String employeeId, {DateTime? at}) => db.walletFor(employeeId, at: at);
  List<EmployeeWalletTransaction> readTransactions(String employeeId, {DateTime? from, DateTime? to}) =>
      db.walletTransactionsFor(employeeId, from: from, to: to);
  List<EmployeeWalletSettlement> readSettlements(String employeeId) => db.walletSettlementsFor(employeeId);
  List<EmployeeWalletPayment> readPayments(String employeeId) => db.walletPaymentsFor(employeeId);
  List<EmployeeWallet> readDebtAndReceivables() => db.walletDebtAndReceivableReport();
  int readPeriodDue(String employeeId, DateTime start, DateTime end) => db.walletPeriodDue(employeeId, start, end);
  PayrollCalculation readPayroll(String employeeId, {DateTime? at}) => db.payrollFor(employeeId, at: at);
  Future<List<EmployeeWalletTransaction>> correctTransaction({
    required String transactionId, required int correctedAmount, required String description,
  }) => _operations.correctWalletTransaction(
    transactionId: transactionId, correctedAmount: correctedAmount, description: description,
  );

  Future<EmployeeWallet> fetchWallet(String employeeId, {DateTime? at}) async {
    await db.delay(20);
    return db.walletFor(employeeId, at: at);
  }

  Future<List<EmployeeWalletTransaction>> fetchTransactions(
    String employeeId, {DateTime? from, DateTime? to}
  ) async {
    await db.delay(20);
    return db.walletTransactionsFor(employeeId, from: from, to: to);
  }

  Future<List<EmployeeWalletSettlement>> fetchSettlements(String employeeId) async {
    await db.delay(20);
    return db.walletSettlementsFor(employeeId);
  }

  Future<List<EmployeeWalletPayment>> fetchPayments(String employeeId) async {
    await db.delay(20);
    return db.walletPaymentsFor(employeeId);
  }

  Future<List<EmployeeWallet>> fetchDebtAndReceivableReport() async {
    await db.delay(20);
    return db.walletDebtAndReceivableReport();
  }

  int calculatePeriodDue(String employeeId, DateTime start, DateTime end) =>
      db.walletPeriodDue(employeeId, start, end);

  Future<EmployeeWalletTransaction> recordTransaction({
    required String employeeId,
    required int amount,
    required EmployeeWalletTransactionType type,
    required String description,
    required String idempotencyKey,
    String? referenceType,
    String? referenceId,
  }) => _operations.addWalletTransaction(
    employeeId: employeeId, amount: amount, type: type,
    description: description, idempotencyKey: idempotencyKey,
    referenceType: referenceType, referenceId: referenceId,
  );

  Future<int> accruePayroll(String employeeId, {DateTime? at}) =>
      _operations.accruePayrollBaseToWallet(employeeId, at: at);

  Future<EmployeeWalletSettlement> settle({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required EmployeeWalletPeriodType periodType,
    required int paidAmount,
    required String idempotencyKey,
    EmployeeWalletPaymentMethod method = EmployeeWalletPaymentMethod.bankTransfer,
    String description = 'پرداخت تسویه پرسنل',
  }) => _operations.settleEmployeeWallet(
    employeeId: employeeId, periodStart: periodStart, periodEnd: periodEnd,
    periodType: periodType, paidAmount: paidAmount, idempotencyKey: idempotencyKey,
    method: method, description: description,
  );
}
