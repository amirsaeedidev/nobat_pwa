/// دفتر کل کیف پول پرسنل؛ مبالغ به تومان و با علامت ذخیره می‌شوند.
enum EmployeeWalletTransactionType {
  commission('پورسانت خدمات'),
  fixedSalary('حقوق ثابت'),
  salaryPayment('پرداخت حقوق'),
  advance('مساعده'),
  bonus('پاداش'),
  penalty('جریمه'),
  deduction('کسورات'),
  refund('برگشت وجه'),
  adjustment('اصلاحیه مالی');

  const EmployeeWalletTransactionType(this.label);
  final String label;

  bool get isCredit => this == commission || this == fixedSalary || this == bonus || this == adjustment;
}

enum EmployeeWalletTransactionStatus { pending, posted, reversed }

enum EmployeeWalletPeriodType {
  daily('روزانه'),
  weekly('هفتگی'),
  monthly('ماهانه'),
  manual('دستی');

  const EmployeeWalletPeriodType(this.label);
  final String label;
}

enum EmployeeWalletSettlementStatus { partial, completed }

/// هر رویداد مالی یک سند مستقل است؛ اسناد ثبت‌شده از دفتر کل حذف نمی‌شوند.
class EmployeeWalletTransaction {
  const EmployeeWalletTransaction({
    required this.id,
    required this.employeeId,
    required this.createdAt,
    required this.amount,
    required this.type,
    required this.description,
    this.status = EmployeeWalletTransactionStatus.posted,
    this.sourceFinanceEntryId,
    this.settlementId,
    this.reversalOfId,
    this.idempotencyKey,
  });

  final String id;
  final String employeeId;
  final DateTime createdAt;
  /// مبلغ مثبت بستانکار و مبلغ منفی بدهکار است.
  final int amount;
  final EmployeeWalletTransactionType type;
  final String description;
  final EmployeeWalletTransactionStatus status;
  final String? sourceFinanceEntryId;
  final String? settlementId;
  final String? reversalOfId;
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => {
    'id': id,
    'employee_id': employeeId,
    'created_at': createdAt.toIso8601String(),
    'amount': amount,
    'type': type.name,
    'description': description,
    'status': status.name,
    'source_finance_entry_id': sourceFinanceEntryId,
    'settlement_id': settlementId,
    'reversal_of_id': reversalOfId,
    'idempotency_key': idempotencyKey,
  };

  factory EmployeeWalletTransaction.fromJson(Map<String, dynamic> json) => EmployeeWalletTransaction(
    id: json['id'] as String,
    employeeId: json['employee_id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    amount: (json['amount'] as num).toInt(),
    type: EmployeeWalletTransactionType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => EmployeeWalletTransactionType.adjustment,
    ),
    description: json['description'] as String? ?? '',
    status: EmployeeWalletTransactionStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => EmployeeWalletTransactionStatus.posted,
    ),
    sourceFinanceEntryId: json['source_finance_entry_id'] as String?,
    settlementId: json['settlement_id'] as String?,
    reversalOfId: json['reversal_of_id'] as String?,
    idempotencyKey: json['idempotency_key'] as String?,
  );
}

/// هر پرداخت یک رسید مستقل و تغییرناپذیر دارد؛ پرداخت جزئی رسید بعدی می‌سازد.
class EmployeeWalletSettlement {
  const EmployeeWalletSettlement({
    required this.id,
    required this.employeeId,
    required this.periodType,
    required this.periodStart,
    required this.periodEnd,
    required this.dueAmount,
    required this.paidAmount,
    required this.remainingAfter,
    required this.createdAt,
    required this.status,
    required this.receiptNumber,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'employee_id': employeeId,
    'period_type': periodType.name,
    'period_start': periodStart.toIso8601String(),
    'period_end': periodEnd.toIso8601String(),
    'due_amount': dueAmount,
    'paid_amount': paidAmount,
    'remaining_after': remainingAfter,
    'created_at': createdAt.toIso8601String(),
    'status': status.name,
    'receipt_number': receiptNumber,
  };

  factory EmployeeWalletSettlement.fromJson(Map<String, dynamic> json) => EmployeeWalletSettlement(
    id: json['id'] as String,
    employeeId: json['employee_id'] as String,
    periodType: EmployeeWalletPeriodType.values.firstWhere(
      (value) => value.name == json['period_type'],
      orElse: () => EmployeeWalletPeriodType.manual,
    ),
    periodStart: DateTime.parse(json['period_start'] as String),
    periodEnd: DateTime.parse(json['period_end'] as String),
    dueAmount: (json['due_amount'] as num).toInt(),
    paidAmount: (json['paid_amount'] as num).toInt(),
    remainingAfter: (json['remaining_after'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String),
    status: EmployeeWalletSettlementStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => EmployeeWalletSettlementStatus.partial,
    ),
    receiptNumber: json['receipt_number'] as String,
  );
}

class EmployeeWalletSummary {
  const EmployeeWalletSummary({
    required this.earned,
    required this.paid,
    required this.debits,
    required this.balance,
    required this.pending,
  });

  final int earned;
  final int paid;
  final int debits;
  final int balance;
  final int pending;

  factory EmployeeWalletSummary.fromTransactions(Iterable<EmployeeWalletTransaction> transactions) {
    var earned = 0;
    var paid = 0;
    var debits = 0;
    var pending = 0;
    for (final entry in transactions) {
      if (entry.status != EmployeeWalletTransactionStatus.posted) {
        if (entry.status == EmployeeWalletTransactionStatus.pending) pending += entry.amount;
        continue;
      }
      if (entry.amount > 0) {
        earned += entry.amount;
      } else if (entry.type == EmployeeWalletTransactionType.salaryPayment) {
        paid += -entry.amount;
      } else {
        debits += -entry.amount;
      }
    }
    return EmployeeWalletSummary(
      earned: earned,
      paid: paid,
      debits: debits,
      balance: transactions
          .where((entry) => entry.status == EmployeeWalletTransactionStatus.posted)
          .fold<int>(0, (sum, entry) => sum + entry.amount),
      pending: pending,
    );
  }
}
