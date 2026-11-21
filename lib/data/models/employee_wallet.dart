/// دفتر کل کیف پول پرسنل؛ مبالغ به تومان صحیح و با علامت ذخیره می‌شوند.
enum EmployeeWalletTransactionType {
  commission('پورسانت خدمات'),
  fixedSalary('حقوق ثابت'),
  salaryPayment('پرداخت حقوق'),
  advance('مساعده'),
  bonus('پاداش'),
  penalty('جریمه'),
  deduction('کسورات'),
  refund('بازپرداخت'),
  adjustment('اصلاح مالی');

  const EmployeeWalletTransactionType(this.label);
  final String label;
  bool get isCredit => this == commission || this == fixedSalary || this == bonus || this == adjustment;
}

enum EmployeeWalletTransactionStatus { pending, posted, reversed }
enum EmployeeWalletPeriodType {
  daily('روزانه'), weekly('هفتگی'), monthly('ماهانه'), manual('دستی');
  const EmployeeWalletPeriodType(this.label);
  final String label;
}
enum EmployeeWalletSettlementStatus { partial, completed }
enum EmployeeWalletPaymentMethod { cash, bankTransfer, pos, cheque, other }

/// سند دفتر کل متصل به سند مالی/پورسانت/نوبت/حقوق/تسویه.
class EmployeeWalletTransaction {
  const EmployeeWalletTransaction({
    required this.id, required this.employeeId, required this.createdAt,
    required this.amount, required this.type, required this.description,
    this.status = EmployeeWalletTransactionStatus.posted,
    this.sourceFinanceEntryId, this.settlementId, this.reversalOfId,
    this.idempotencyKey, this.appointmentId, this.paymentId,
    this.referenceType, this.referenceId,
  });
  final String id;
  final String employeeId;
  final DateTime createdAt;
  /// مثبت بستانکار و منفی بدهکار.
  final int amount;
  final EmployeeWalletTransactionType type;
  final String description;
  final EmployeeWalletTransactionStatus status;
  final String? sourceFinanceEntryId;
  final String? settlementId;
  final String? reversalOfId;
  final String? idempotencyKey;
  final String? appointmentId;
  final String? paymentId;
  final String? referenceType;
  final String? referenceId;

  Map<String, dynamic> toJson() => {
    'id': id, 'employee_id': employeeId, 'created_at': createdAt.toIso8601String(),
    'amount': amount, 'type': type.name, 'description': description, 'status': status.name,
    'source_finance_entry_id': sourceFinanceEntryId, 'settlement_id': settlementId,
    'reversal_of_id': reversalOfId, 'idempotency_key': idempotencyKey,
    'appointment_id': appointmentId, 'payment_id': paymentId,
    'reference_type': referenceType, 'reference_id': referenceId,
  };

  factory EmployeeWalletTransaction.fromJson(Map<String, dynamic> json) => EmployeeWalletTransaction(
    id: json['id'] as String, employeeId: json['employee_id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String), amount: (json['amount'] as num).toInt(),
    type: EmployeeWalletTransactionType.values.firstWhere((v) => v.name == json['type'], orElse: () => EmployeeWalletTransactionType.adjustment),
    description: json['description'] as String? ?? '',
    status: EmployeeWalletTransactionStatus.values.firstWhere((v) => v.name == json['status'], orElse: () => EmployeeWalletTransactionStatus.posted),
    sourceFinanceEntryId: json['source_finance_entry_id'] as String?,
    settlementId: json['settlement_id'] as String?, reversalOfId: json['reversal_of_id'] as String?,
    idempotencyKey: json['idempotency_key'] as String?, appointmentId: json['appointment_id'] as String?,
    paymentId: json['payment_id'] as String?, referenceType: json['reference_type'] as String?,
    referenceId: json['reference_id'] as String?,
  );
}

/// کیف پول یک نمای محاسباتی از دفتر کل است و مقدار مالی مستقل نگه نمی‌دارد.
class EmployeeWallet {
  const EmployeeWallet({
    required this.employeeId, required this.summary, required this.transactionCount,
    required this.calculatedAt,
  });
  final String employeeId;
  final EmployeeWalletSummary summary;
  final int transactionCount;
  final DateTime calculatedAt;
  int get payableBalance => summary.payableBalance;
  int get calculatedIncome => summary.earned;
  int get paymentsMade => summary.paid;
  int get advances => summary.advances;
  int get bonuses => summary.bonuses;
  int get debtsAndDeductions => summary.debits;
  int get finalBalance => summary.balance;

  factory EmployeeWallet.fromTransactions(String employeeId, Iterable<EmployeeWalletTransaction> source, {DateTime? calculatedAt}) {
    final entries = source.toList(growable: false);
    return EmployeeWallet(
      employeeId: employeeId,
      summary: EmployeeWalletSummary.fromTransactions(entries),
      transactionCount: entries.length,
      calculatedAt: calculatedAt ?? DateTime.now(),
    );
  }
}

/// پرداخت مستقل و تغییرناپذیر؛ هر پرداخت به یک تسویه و یک سند دفتر کل متصل است.
class EmployeeWalletPayment {
  const EmployeeWalletPayment({
    required this.id, required this.employeeId, required this.settlementId,
    required this.walletTransactionId, required this.createdAt, required this.amount,
    required this.method, required this.receiptNumber, required this.idempotencyKey,
    this.description = '',
  });
  final String id;
  final String employeeId;
  final String settlementId;
  final String walletTransactionId;
  final DateTime createdAt;
  final int amount;
  final EmployeeWalletPaymentMethod method;
  final String receiptNumber;
  final String idempotencyKey;
  final String description;

  Map<String, dynamic> toJson() => {
    'id': id, 'employee_id': employeeId, 'settlement_id': settlementId,
    'wallet_transaction_id': walletTransactionId, 'created_at': createdAt.toIso8601String(),
    'amount': amount, 'method': method.name, 'receipt_number': receiptNumber,
    'idempotency_key': idempotencyKey, 'description': description,
  };
  factory EmployeeWalletPayment.fromJson(Map<String, dynamic> json) => EmployeeWalletPayment(
    id: json['id'] as String, employeeId: json['employee_id'] as String,
    settlementId: json['settlement_id'] as String, walletTransactionId: json['wallet_transaction_id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String), amount: (json['amount'] as num).toInt(),
    method: EmployeeWalletPaymentMethod.values.firstWhere((v) => v.name == json['method'], orElse: () => EmployeeWalletPaymentMethod.other),
    receiptNumber: json['receipt_number'] as String, idempotencyKey: json['idempotency_key'] as String,
    description: json['description'] as String? ?? '',
  );
}

class EmployeeWalletSettlement {
  const EmployeeWalletSettlement({
    required this.id, required this.employeeId, required this.periodType,
    required this.periodStart, required this.periodEnd, required this.dueAmount,
    required this.paidAmount, required this.remainingAfter, required this.createdAt,
    required this.status, required this.receiptNumber, this.idempotencyKey,
  });
  final String id;
  final String employeeId;
  final EmployeeWalletPeriodType periodType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int dueAmount;
  final int paidAmount;
  final int remainingAfter;
  final DateTime createdAt;
  final EmployeeWalletSettlementStatus status;
  final String receiptNumber;
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => {
    'id': id, 'employee_id': employeeId, 'period_type': periodType.name,
    'period_start': periodStart.toIso8601String(), 'period_end': periodEnd.toIso8601String(),
    'due_amount': dueAmount, 'paid_amount': paidAmount, 'remaining_after': remainingAfter,
    'created_at': createdAt.toIso8601String(), 'status': status.name,
    'receipt_number': receiptNumber, 'idempotency_key': idempotencyKey,
  };
  factory EmployeeWalletSettlement.fromJson(Map<String, dynamic> json) => EmployeeWalletSettlement(
    id: json['id'] as String, employeeId: json['employee_id'] as String,
    periodType: EmployeeWalletPeriodType.values.firstWhere((v) => v.name == json['period_type'], orElse: () => EmployeeWalletPeriodType.manual),
    periodStart: DateTime.parse(json['period_start'] as String), periodEnd: DateTime.parse(json['period_end'] as String),
    dueAmount: (json['due_amount'] as num).toInt(), paidAmount: (json['paid_amount'] as num).toInt(),
    remainingAfter: (json['remaining_after'] as num).toInt(), createdAt: DateTime.parse(json['created_at'] as String),
    status: EmployeeWalletSettlementStatus.values.firstWhere((v) => v.name == json['status'], orElse: () => EmployeeWalletSettlementStatus.partial),
    receiptNumber: json['receipt_number'] as String, idempotencyKey: json['idempotency_key'] as String?,
  );
}

class EmployeeWalletSummary {
  const EmployeeWalletSummary({
    required this.earned, required this.paid, required this.debits,
    required this.balance, required this.pending, this.advances = 0, this.bonuses = 0,
    this.commissionIncome = 0, this.fixedSalaryIncome = 0, this.penalties = 0,
    this.deductions = 0, this.refunds = 0,
  });
  final int earned;
  final int paid;
  final int debits;
  final int balance;
  final int pending;
  final int advances;
  final int bonuses;
  final int commissionIncome;
  final int fixedSalaryIncome;
  final int penalties;
  final int deductions;
  final int refunds;
  int get payableBalance => balance > 0 ? balance : 0;
  int get debt => balance < 0 ? -balance : 0;

  factory EmployeeWalletSummary.fromTransactions(Iterable<EmployeeWalletTransaction> transactions) {
    var earned = 0, paid = 0, debits = 0, pending = 0, advances = 0, bonuses = 0;
    var commission = 0, salary = 0, penalties = 0, deductions = 0, refunds = 0, balance = 0;
    for (final entry in transactions) {
      if (entry.status == EmployeeWalletTransactionStatus.pending) { pending += entry.amount; continue; }
      if (entry.status != EmployeeWalletTransactionStatus.posted) continue;
      balance += entry.amount;
      if (entry.amount > 0) {
        earned += entry.amount;
        if (entry.type == EmployeeWalletTransactionType.commission) commission += entry.amount;
        if (entry.type == EmployeeWalletTransactionType.fixedSalary) salary += entry.amount;
        if (entry.type == EmployeeWalletTransactionType.bonus) bonuses += entry.amount;
      } else {
        if (entry.type == EmployeeWalletTransactionType.salaryPayment) paid += -entry.amount;
        else {
          debits += -entry.amount;
          if (entry.type == EmployeeWalletTransactionType.advance) advances += -entry.amount;
          if (entry.type == EmployeeWalletTransactionType.penalty) penalties += -entry.amount;
          if (entry.type == EmployeeWalletTransactionType.deduction) deductions += -entry.amount;
          if (entry.type == EmployeeWalletTransactionType.refund) refunds += -entry.amount;
        }
      }
    }
    return EmployeeWalletSummary(
      earned: earned, paid: paid, debits: debits, balance: balance, pending: pending,
      advances: advances, bonuses: bonuses, commissionIncome: commission,
      fixedSalaryIncome: salary, penalties: penalties, deductions: deductions, refunds: refunds,
    );
  }
}
