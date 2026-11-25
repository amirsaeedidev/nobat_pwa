import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_wallet.dart';
import '../models/employee_finance.dart';

/// Supabase-only data source for employee compensation and wallet ledger.
/// All money values are integer Toman and all writes go through atomic RPCs.
class SupabaseEmployeeWalletRepository {
  SupabaseEmployeeWalletRepository({
    required SupabaseClient client,
    required this.businessId,
  }) : _client = client {
    if (businessId.trim().isEmpty) {
      throw ArgumentError.value(businessId, 'businessId', 'Business ID is required.');
    }
  }

  final SupabaseClient _client;
  final String businessId;

  String _userId() {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('برای مشاهده کیف پول ابتدا وارد حساب کاربری شوید.');
    }
    return id;
  }

  Future<List<EmployeeWalletTransaction>> fetchTransactions(
    String employeeId, {
    DateTime? from,
    DateTime? to,
  }) async {
    _userId();
    var query = _client
        .from('employee_wallet_transactions')
        .select('*')
        .eq('business_id', businessId)
        .eq('employee_id', employeeId);
    if (from != null) query = query.gte('created_at', from.toUtc().toIso8601String());
    if (to != null) query = query.lte('created_at', to.toUtc().toIso8601String());
    final rows = await query.order('created_at', ascending: false);
    return rows.map((row) => _transactionFromRow(Map<String, dynamic>.from(row))).toList();
  }

  Future<EmployeeWallet> fetchWallet(String employeeId, {DateTime? at}) async {
    final rows = await fetchTransactions(employeeId, to: at);
    return EmployeeWallet.fromTransactions(employeeId, rows, calculatedAt: at);
  }

  Future<List<EmployeeWalletSettlement>> fetchSettlements(String employeeId) async {
    _userId();
    final rows = await _client
        .from('employee_settlements')
        .select('*')
        .eq('business_id', businessId)
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false);
    return rows.map((row) => _settlementFromRow(Map<String, dynamic>.from(row))).toList();
  }

  Future<List<EmployeeWalletPayment>> fetchPayments(String employeeId) async {
    _userId();
    final rows = await _client
        .from('employee_settlements')
        .select('*')
        .eq('business_id', businessId)
        .eq('employee_id', employeeId)
        .not('wallet_transaction_id', 'is', null)
        .order('created_at', ascending: false);
    return rows.map((row) {
      final value = Map<String, dynamic>.from(row);
      return EmployeeWalletPayment(
        id: value['id'] as String,
        employeeId: value['employee_id'] as String,
        settlementId: value['id'] as String,
        walletTransactionId: value['wallet_transaction_id'] as String,
        createdAt: DateTime.parse(value['created_at'] as String),
        amount: (value['amount_toman'] as num).toInt(),
        method: _paymentMethod(value['payment_method'] as String?),
        receiptNumber: value['receipt_number'] as String? ?? '',
        idempotencyKey: value['idempotency_key'] as String? ?? value['id'] as String,
        description: value['request_note'] as String? ?? '',
      );
    }).toList();
  }

  Future<EmployeePayProfile?> fetchPayProfile(String employeeId) async {
    _userId();
    final row = await _client
        .from('employee_pay_profiles')
        .select('*,employee_commission_rules(*)')
        .eq('business_id', businessId)
        .eq('employee_id', employeeId)
        .eq('is_active', true)
        .order('effective_from', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final value = Map<String, dynamic>.from(row);
    final rules = (value['employee_commission_rules'] as List? ?? const [])
        .map((item) {
          final rule = Map<String, dynamic>.from(item as Map);
          return EmployeeCommissionRule(
            id: rule['id'] as String,
            serviceId: rule['service_id'] as String?,
            category: rule['category'] as String?,
            rateBps: (rule['rate_bps'] as num?)?.toInt() ?? 0,
            fixedAmount: (rule['fixed_amount_toman'] as num?)?.toInt() ?? 0,
            effectiveFrom: rule['effective_from'] == null
                ? null
                : DateTime.parse(rule['effective_from'] as String),
            active: rule['is_active'] as bool? ?? true,
          );
        }).toList();
    return EmployeePayProfile(
      employeeId: employeeId,
      method: _payMethod(value['payment_method'] as String?),
      monthlySalary: (value['monthly_salary_toman'] as num?)?.toInt() ?? 0,
      generalRateBps: (value['general_rate_bps'] as num?)?.toInt() ?? 0,
      basis: _commissionBasis(value['commission_basis'] as String?),
      rules: rules,
    );
  }

  Future<void> savePayProfile(EmployeePayProfile profile, {DateTime? effectiveFrom}) async {
    _userId();
    await _client.rpc('save_employee_pay_profile', params: {
      'p_business_id': businessId,
      'p_employee_id': profile.employeeId,
      'p_payment_method': _payMethodToDb(profile.method),
      'p_monthly_salary_toman': profile.monthlySalary,
      'p_general_rate_bps': profile.generalRateBps,
      'p_commission_basis': _commissionBasisToDb(profile.basis),
      'p_effective_from': _dateOnly(effectiveFrom ?? DateTime.now()),
      'p_rules': profile.rules.map((rule) => {
        'service_id': rule.serviceId,
        'category': rule.category,
        'rate_bps': rule.rateBps,
        'fixed_amount_toman': rule.fixedAmount,
        'effective_from': _dateOnly(rule.effectiveFrom ?? effectiveFrom ?? DateTime.now()),
        'is_active': rule.active,
      }).toList(),
    });
  }

  Future<String> recordTransaction({
    required String employeeId,
    required int amount,
    required EmployeeWalletTransactionType type,
    required String description,
    required String idempotencyKey,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? referenceId,
    Map<String, dynamic> contractSnapshot = const {},
  }) async {
    _userId();
    if (amount == 0 || idempotencyKey.trim().isEmpty || description.trim().isEmpty) {
      throw ArgumentError('مبلغ، شرح و کلید جلوگیری از ثبت تکراری الزامی است.');
    }
    final isCredit = amount > 0;
    final result = await _client.rpc('record_employee_wallet_transaction', params: {
      'p_business_id': businessId,
      'p_employee_id': employeeId,
      'p_amount_toman': amount.abs(),
      'p_transaction_type': _transactionTypeToDb(type),
      'p_direction': isCredit ? 'credit' : 'debit',
      'p_description': description.trim(),
      'p_idempotency_key': idempotencyKey,
      'p_period_start': periodStart == null ? null : _dateOnly(periodStart),
      'p_period_end': periodEnd == null ? null : _dateOnly(periodEnd),
      'p_reference_id': referenceId,
      'p_contract_snapshot': contractSnapshot,
    });
    return result.toString();
  }

  Future<String> accrueSalary(
    String employeeId, {
    DateTime? month,
    required String idempotencyKey,
  }) async {
    _userId();
    final target = month ?? DateTime.now();
    final result = await _client.rpc('accrue_employee_salary', params: {
      'p_business_id': businessId,
      'p_employee_id': employeeId,
      'p_month': _dateOnly(DateTime(target.year, target.month, 1)),
      'p_idempotency_key': idempotencyKey,
    });
    return result.toString();
  }

  Future<String> settle({
    required String employeeId,
    required EmployeeWalletPeriodType periodType,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int amount,
    required EmployeeWalletPaymentMethod method,
    required String description,
    required String idempotencyKey,
  }) async {
    _userId();
    if (amount <= 0 || periodEnd.isBefore(periodStart) || idempotencyKey.trim().isEmpty) {
      throw ArgumentError('مبلغ، بازه و کلید تسویه معتبر نیست.');
    }
    final result = await _client.rpc('settle_employee_wallet', params: {
      'p_business_id': businessId,
      'p_employee_id': employeeId,
      'p_period_type': periodType.name,
      'p_period_start': _dateOnly(periodStart),
      'p_period_end': _dateOnly(periodEnd),
      'p_amount_toman': amount,
      'p_method': _paymentMethodToDb(method),
      'p_description': description.trim(),
      'p_idempotency_key': idempotencyKey,
    });
    return result.toString();
  }

  Future<int> periodDue(String employeeId, DateTime start, DateTime end) async {
    final rows = await fetchTransactions(employeeId, from: start, to: end);
    return rows.where((item) => item.status == EmployeeWalletTransactionStatus.posted)
        .fold<int>(0, (sum, item) => sum + item.amount)
        .clamp(0, 0x7fffffffffffffff);
  }

  Future<List<Map<String, dynamic>>> fetchEmployeesLedgerSummary() async {
    _userId();
    final rows = await _client
        .from('employee_wallet_transactions')
        .select('employee_id,amount_toman,direction,status')
        .eq('business_id', businessId)
        .eq('status', 'posted');
    final totals = <String, int>{};
    for (final row in rows) {
      final employeeId = row['employee_id'] as String;
      final amount = (row['amount_toman'] as num).toInt();
      final signed = row['direction'] == 'debit' ? -amount : amount;
      totals.update(employeeId, (value) => value + signed, ifAbsent: () => signed);
    }
    return totals.entries.map((entry) => {'employee_id': entry.key, 'balance_toman': entry.value}).toList();
  }

  EmployeeWalletTransaction _transactionFromRow(Map<String, dynamic> row) {
    final amount = (row['amount_toman'] as num).toInt();
    final signed = row['direction'] == 'debit' ? -amount : amount;
    final type = _transactionType(row['transaction_type'] as String?);
    return EmployeeWalletTransaction(
      id: row['id'] as String,
      employeeId: row['employee_id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      amount: signed,
      type: type,
      description: row['description'] as String? ?? '',
      status: _transactionStatus(row['status'] as String?),
      sourceFinanceEntryId: row['finance_entry_id'] as String?,
      reversalOfId: row['reversal_of_id'] as String?,
      idempotencyKey: row['idempotency_key'] as String?,
      referenceId: row['reference_id'] as String?,
      referenceType: row['reference_id'] == null ? null : 'finance_reference',
    );
  }

  EmployeeWalletSettlement _settlementFromRow(Map<String, dynamic> row) {
    final paid = (row['amount_toman'] as num).toInt();
    final remaining = (row['balance_after_toman'] as num?)?.toInt() ?? 0;
    return EmployeeWalletSettlement(
      id: row['id'] as String,
      employeeId: row['employee_id'] as String,
      periodType: EmployeeWalletPeriodType.values.firstWhere(
        (value) => value.name == row['period_type'],
        orElse: () => EmployeeWalletPeriodType.manual,
      ),
      periodStart: DateTime.parse(row['period_start'] as String),
      periodEnd: DateTime.parse(row['period_end'] as String),
      dueAmount: paid + remaining,
      paidAmount: paid,
      remainingAfter: remaining,
      createdAt: DateTime.parse(row['created_at'] as String),
      status: remaining == 0 ? EmployeeWalletSettlementStatus.completed : EmployeeWalletSettlementStatus.partial,
      receiptNumber: row['receipt_number'] as String? ?? '',
      idempotencyKey: row['idempotency_key'] as String?,
    );
  }

  EmployeeWalletTransactionType _transactionType(String? value) => switch (value) {
    'commission' => EmployeeWalletTransactionType.commission,
    'salary' || 'fixed_salary' => EmployeeWalletTransactionType.fixedSalary,
    'salary_payment' || 'settlement' => EmployeeWalletTransactionType.salaryPayment,
    'advance' => EmployeeWalletTransactionType.advance,
    'bonus' => EmployeeWalletTransactionType.bonus,
    'penalty' => EmployeeWalletTransactionType.penalty,
    'deduction' => EmployeeWalletTransactionType.deduction,
    'refund' => EmployeeWalletTransactionType.refund,
    _ => EmployeeWalletTransactionType.adjustment,
  };

  EmployeeWalletTransactionStatus _transactionStatus(String? value) => switch (value) {
    'pending' => EmployeeWalletTransactionStatus.pending,
    'reversed' || 'void' => EmployeeWalletTransactionStatus.reversed,
    _ => EmployeeWalletTransactionStatus.posted,
  };

  EmployeeWalletPaymentMethod _paymentMethod(String? value) => switch (value) {
    'cash' => EmployeeWalletPaymentMethod.cash,
    'pos' => EmployeeWalletPaymentMethod.pos,
    'cheque' => EmployeeWalletPaymentMethod.cheque,
    'other' => EmployeeWalletPaymentMethod.other,
    _ => EmployeeWalletPaymentMethod.bankTransfer,
  };

  String _paymentMethodToDb(EmployeeWalletPaymentMethod value) => switch (value) {
    EmployeeWalletPaymentMethod.cash => 'cash',
    EmployeeWalletPaymentMethod.bankTransfer => 'bank_transfer',
    EmployeeWalletPaymentMethod.pos => 'pos',
    EmployeeWalletPaymentMethod.cheque => 'cheque',
    EmployeeWalletPaymentMethod.other => 'other',
  };

  EmployeePaymentMethod _payMethod(String? value) => switch (value) {
    'fixedMonthly' => EmployeePaymentMethod.fixedMonthly,
    'fixedPlusCommission' => EmployeePaymentMethod.fixedPlusCommission,
    'fixedPerService' => EmployeePaymentMethod.fixedPerService,
    'hybrid' => EmployeePaymentMethod.hybrid,
    _ => EmployeePaymentMethod.commissionOnly,
  };

  String _payMethodToDb(EmployeePaymentMethod value) => value.name;

  CommissionBasis _commissionBasis(String? value) => switch (value) {
    'gross' => CommissionBasis.gross,
    'netReceived' => CommissionBasis.netReceived,
    _ => CommissionBasis.afterDiscount,
  };

  String _commissionBasisToDb(CommissionBasis value) => value.name;

  String _transactionTypeToDb(EmployeeWalletTransactionType value) => switch (value) {
    EmployeeWalletTransactionType.commission => 'commission',
    EmployeeWalletTransactionType.fixedSalary => 'salary',
    EmployeeWalletTransactionType.salaryPayment => 'salary_payment',
    EmployeeWalletTransactionType.advance => 'advance',
    EmployeeWalletTransactionType.bonus => 'bonus',
    EmployeeWalletTransactionType.penalty => 'penalty',
    EmployeeWalletTransactionType.deduction => 'deduction',
    EmployeeWalletTransactionType.refund => 'refund',
    EmployeeWalletTransactionType.adjustment => 'adjustment',
  };

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
