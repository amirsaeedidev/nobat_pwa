import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_wallet.dart';

/// Tenant-scoped employee wallet access. All mutations use atomic Postgres RPCs.
class SupabaseEmployeeWalletRepository {
  SupabaseEmployeeWalletRepository({
    required SupabaseClient client,
    required String? Function() businessId,
  }) : _client = client, _businessId = businessId;

  final SupabaseClient _client;
  final String? Function() _businessId;

  String _tenant() {
    if (_client.auth.currentUser == null) {
      throw StateError('نشست Supabase معتبر نیست؛ دوباره وارد شوید.');
    }
    final id = _businessId();
    if (id == null || id.isEmpty) throw StateError('عضویت فعال مجموعه تأیید نشده است.');
    return id;
  }

  static const _walletColumns =
      'id,business_id,employee_id,transaction_type,amount_toman,direction,description,status,period_start,period_end,created_at,idempotency_key,reversal_of_id,reference_id,finance_entry_id,contract_snapshot';

  EmployeeWalletTransaction _transaction(Map<String, dynamic> row) {
    final rawType = row['transaction_type']?.toString() ?? 'adjustment';
    final type = switch (rawType) {
      'service_commission' => EmployeeWalletTransactionType.commission,
      'salary' => EmployeeWalletTransactionType.fixedSalary,
      'salary_payment' || 'settlement' => EmployeeWalletTransactionType.salaryPayment,
      'advance' => EmployeeWalletTransactionType.advance,
      'bonus' => EmployeeWalletTransactionType.bonus,
      'penalty' => EmployeeWalletTransactionType.penalty,
      'deduction' => EmployeeWalletTransactionType.deduction,
      'refund' => EmployeeWalletTransactionType.refund,
      _ => EmployeeWalletTransactionType.adjustment,
    };
    final rawAmount = (row['amount_toman'] as num).toInt();
    return EmployeeWalletTransaction(
      id: row['id'].toString(),
      employeeId: row['employee_id'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
      amount: row['direction'] == 'debit' ? -rawAmount : rawAmount,
      type: type,
      description: row['description']?.toString() ?? '',
      status: row['status'] == 'reversed'
          ? EmployeeWalletTransactionStatus.reversed
          : row['status'] == 'pending'
              ? EmployeeWalletTransactionStatus.pending
              : EmployeeWalletTransactionStatus.posted,
      sourceFinanceEntryId: row['finance_entry_id']?.toString(),
      reversalOfId: row['reversal_of_id']?.toString(),
      idempotencyKey: row['idempotency_key']?.toString(),
      referenceId: row['reference_id']?.toString(),
    );
  }

  EmployeeWalletSettlement _settlement(Map<String, dynamic> row) {
    final amount = (row['amount_toman'] as num).toInt();
    final paid = row['paid_at'] != null ? amount : 0;
    return EmployeeWalletSettlement(
      id: row['id'].toString(),
      employeeId: row['employee_id'].toString(),
      periodType: EmployeeWalletPeriodType.values.firstWhere(
        (v) => v.name == row['period_type'],
        orElse: () => EmployeeWalletPeriodType.manual,
      ),
      periodStart: DateTime.parse(row['period_start'].toString()),
      periodEnd: DateTime.parse(row['period_end'].toString()),
      dueAmount: amount,
      paidAmount: paid,
      remainingAfter: (row['balance_after_toman'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
      status: paid == amount
          ? EmployeeWalletSettlementStatus.completed
          : EmployeeWalletSettlementStatus.partial,
      receiptNumber: row['receipt_number']?.toString() ?? row['id'].toString(),
      idempotencyKey: row['idempotency_key']?.toString(),
    );
  }

  EmployeeWalletPayment _payment(Map<String, dynamic> row) {
    final method = switch (row['payment_method']) {
      'cash' => EmployeeWalletPaymentMethod.cash,
      'bank_transfer' => EmployeeWalletPaymentMethod.bankTransfer,
      'pos' => EmployeeWalletPaymentMethod.pos,
      'cheque' => EmployeeWalletPaymentMethod.cheque,
      _ => EmployeeWalletPaymentMethod.other,
    };
    return EmployeeWalletPayment(
      id: row['id'].toString(),
      employeeId: row['employee_id'].toString(),
      settlementId: row['id'].toString(),
      walletTransactionId: row['wallet_transaction_id']?.toString() ?? '',
      createdAt: DateTime.parse((row['paid_at'] ?? row['created_at']).toString()).toLocal(),
      amount: (row['amount_toman'] as num).toInt(),
      method: method,
      receiptNumber: row['receipt_number']?.toString() ?? '',
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      description: row['request_note']?.toString() ?? '',
    );
  }

  Future<List<EmployeeWalletTransaction>> fetchTransactions(
    String employeeId, {DateTime? from, DateTime? to}
  ) async {
    final tenant = _tenant();
    var query = _client.from('employee_wallet_transactions')
        .select(_walletColumns).eq('business_id', tenant).eq('employee_id', employeeId);
    if (from != null) query = query.gte('created_at', from.toUtc().toIso8601String());
    if (to != null) query = query.lte('created_at', to.toUtc().toIso8601String());
    final rows = await query.order('created_at', ascending: false);
    return rows.map((row) => _transaction(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  Future<EmployeeWallet> fetchWallet(String employeeId, {DateTime? at}) async =>
      EmployeeWallet.fromTransactions(employeeId, await fetchTransactions(employeeId, to: at), calculatedAt: at);

  Future<List<EmployeeWalletSettlement>> fetchSettlements(String employeeId) async {
    final tenant = _tenant();
    final rows = await _client.from('employee_settlements')
        .select('id,employee_id,period_type,period_start,period_end,amount_toman,status,paid_at,created_at,idempotency_key,payment_method,receipt_number,wallet_transaction_id,balance_after_toman,request_note')
        .eq('business_id', tenant).eq('employee_id', employeeId)
        .order('created_at', ascending: false);
    return rows.map((row) => _settlement(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  Future<List<EmployeeWalletPayment>> fetchPayments(String employeeId) async {
    final tenant = _tenant();
    final rows = await _client.from('employee_settlements')
        .select('id,employee_id,amount_toman,paid_at,created_at,idempotency_key,payment_method,receipt_number,wallet_transaction_id,request_note')
        .eq('business_id', tenant).eq('employee_id', employeeId)
        .not('paid_at', 'is', null).order('paid_at', ascending: false);
    return rows.map((row) => _payment(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  Future<String> recordTransaction({
    required String employeeId,
    required int amount,
    required EmployeeWalletTransactionType type,
    required String description,
    required String idempotencyKey,
    bool? credit,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? referenceId,
  }) async {
    final tenant = _tenant();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'مبلغ باید بیشتر از صفر باشد.');
    final transactionType = switch (type) {
      EmployeeWalletTransactionType.commission => 'service_commission',
      EmployeeWalletTransactionType.fixedSalary => 'salary',
      EmployeeWalletTransactionType.salaryPayment => 'salary_payment',
      EmployeeWalletTransactionType.advance => 'advance',
      EmployeeWalletTransactionType.bonus => 'bonus',
      EmployeeWalletTransactionType.penalty => 'penalty',
      EmployeeWalletTransactionType.deduction => 'deduction',
      EmployeeWalletTransactionType.refund => 'refund',
      EmployeeWalletTransactionType.adjustment => 'adjustment',
    };
    final result = await _client.rpc('record_employee_wallet_transaction', params: {
      'p_business_id': tenant,
      'p_employee_id': employeeId,
      'p_amount_toman': amount,
      'p_transaction_type': transactionType,
      'p_direction': (credit ?? type.isCredit) ? 'credit' : 'debit',
      'p_description': description.trim(),
      'p_idempotency_key': idempotencyKey,
      'p_period_start': periodStart == null ? null : _date(periodStart),
      'p_period_end': periodEnd == null ? null : _date(periodEnd),
      'p_reference_id': referenceId,
      'p_contract_snapshot': <String, dynamic>{},
    });
    if (result == null || result.toString().isEmpty) throw StateError('ثبت تراکنش در دفتر کل ناموفق بود.');
    return result.toString();
  }

  Future<String> accrueMonthlySalary(String employeeId, {DateTime? at}) async {
    final tenant = _tenant();
    final date = at ?? DateTime.now();
    final profiles = await _client.from('employee_pay_profiles')
        .select('monthly_salary_toman,effective_from,is_active')
        .eq('business_id', tenant).eq('employee_id', employeeId)
        .eq('is_active', true).lte('effective_from', _date(date))
        .order('effective_from', ascending: false).limit(1);
    if (profiles.isEmpty) throw StateError('قرارداد حقوق فعال برای این پرسنل ثبت نشده است.');
    final salary = (profiles.first['monthly_salary_toman'] as num?)?.toInt() ?? 0;
    if (salary <= 0) throw StateError('مبلغ حقوق ثابت در قرارداد ثبت نشده است.');
    final start = DateTime(date.year, date.month, 1);
    final end = DateTime(date.year, date.month + 1, 0);
    return recordTransaction(
      employeeId: employeeId, amount: salary, type: EmployeeWalletTransactionType.fixedSalary,
      description: 'ثبت حقوق ثابت ${date.year}-${date.month.toString().padLeft(2, '0')}',
      idempotencyKey: 'salary:$employeeId:${date.year}-${date.month.toString().padLeft(2, '0')}',
      periodStart: start, periodEnd: end,
    );
  }

  Future<String> settle({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required EmployeeWalletPeriodType periodType,
    required int amount,
    required EmployeeWalletPaymentMethod method,
    required String description,
    required String idempotencyKey,
  }) async {
    final tenant = _tenant();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'مبلغ تسویه باید بیشتر از صفر باشد.');
    final methodKey = switch (method) {
      EmployeeWalletPaymentMethod.cash => 'cash',
      EmployeeWalletPaymentMethod.bankTransfer => 'bank_transfer',
      EmployeeWalletPaymentMethod.pos => 'pos',
      EmployeeWalletPaymentMethod.cheque => 'cheque',
      EmployeeWalletPaymentMethod.other => 'other',
    };
    final result = await _client.rpc('settle_employee_wallet', params: {
      'p_business_id': tenant,
      'p_employee_id': employeeId,
      'p_period_type': periodType.name,
      'p_period_start': _date(periodStart),
      'p_period_end': _date(periodEnd),
      'p_amount_toman': amount,
      'p_method': methodKey,
      'p_description': description.trim(),
      'p_idempotency_key': idempotencyKey,
    });
    if (result == null || result.toString().isEmpty) throw StateError('ثبت تسویه در سرور ناموفق بود.');
    return result.toString();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
