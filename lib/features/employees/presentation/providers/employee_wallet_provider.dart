import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/employee_wallet.dart';
import '../../../../data/models/employee_finance.dart';
import '../../../../data/repositories/supabase_employee_wallet_repository.dart';

/// Async state for a single employee wallet. It never falls back to local/mock data.
class EmployeeWalletProvider extends ChangeNotifier {
  EmployeeWalletProvider(this.repository, this.employeeId) {
    refresh();
  }

  final SupabaseEmployeeWalletRepository repository;
  final String employeeId;

  bool loading = true;
  bool saving = false;
  String? error;
  EmployeeWallet? wallet;
  List<EmployeeWalletTransaction> transactions = const [];
  List<EmployeeWalletSettlement> settlements = const [];
  List<EmployeeWalletPayment> payments = const [];
  EmployeePayProfile? payProfile;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await Future.wait<Object>([
        repository.fetchWallet(employeeId),
        repository.fetchTransactions(employeeId),
        repository.fetchSettlements(employeeId),
        repository.fetchPayments(employeeId),
        repository.fetchPayProfile(employeeId),
      ]);
      wallet = result[0] as EmployeeWallet;
      transactions = result[1] as List<EmployeeWalletTransaction>;
      settlements = result[2] as List<EmployeeWalletSettlement>;
      payments = result[3] as List<EmployeeWalletPayment>;
      payProfile = result[4] as EmployeePayProfile?;
    } catch (exception) {
      error = exception.toString();
      wallet = null;
      transactions = const [];
      settlements = const [];
      payments = const [];
      payProfile = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> savePayProfile(EmployeePayProfile profile) async {
    await _run(() => repository.savePayProfile(profile));
  }

  Future<void> record({
    required int amount,
    required EmployeeWalletTransactionType type,
    required String description,
    required String idempotencyKey,
  }) async {
    await _run(() => repository.recordTransaction(
      employeeId: employeeId,
      amount: amount,
      type: type,
      description: description,
      idempotencyKey: idempotencyKey,
    ));
  }

  Future<void> accrueSalary({required String idempotencyKey, DateTime? month}) async {
    await _run(() => repository.accrueSalary(employeeId, month: month, idempotencyKey: idempotencyKey));
  }

  Future<void> settle({
    required EmployeeWalletPeriodType periodType,
    required DateTime start,
    required DateTime end,
    required int amount,
    required EmployeeWalletPaymentMethod method,
    required String description,
    required String idempotencyKey,
  }) async {
    await _run(() => repository.settle(
      employeeId: employeeId,
      periodType: periodType,
      periodStart: start,
      periodEnd: end,
      amount: amount,
      method: method,
      description: description,
      idempotencyKey: idempotencyKey,
    ));
  }

  Future<void> _run(Future<Object?> Function() action) async {
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await action();
      await refresh();
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
