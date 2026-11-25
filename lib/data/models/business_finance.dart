/// مدل‌های دفتر مالی مجموعه؛ مبالغ به تومان و رکوردهای تولیدی از Supabase خوانده می‌شوند.
enum BusinessPaymentMethod {
  cash('نقدی'),
  pos('کارت‌خوان'),
  bankTransfer('انتقال بانکی'),
  wallet('کیف پول'),
  other('سایر');

  const BusinessPaymentMethod(this.label);
  final String label;
}

enum BusinessPaymentType { receipt, refund }

enum BusinessExpenseCategory {
  operating('هزینه عملیاتی'),
  rent('اجاره'),
  supplies('مواد مصرفی'),
  utilities('قبوض و خدمات'),
  marketing('تبلیغات'),
  maintenance('تعمیر و نگهداری'),
  other('سایر');

  const BusinessExpenseCategory(this.label);
  final String label;
}

enum BusinessExpenseStatus { posted, pending, reversed }

/// رسید یا برگشت وجه مرتبط با یک نوبت؛ مبلغ همیشه مثبت است.
class AppointmentPayment {
  const AppointmentPayment({
    required this.id,
    required this.appointmentId,
    required this.customerId,
    required this.createdAt,
    required this.amount,
    required this.method,
    required this.type,
    required this.description,
    this.reversesPaymentId,
    this.idempotencyKey,
  });

  final String id;
  final String appointmentId;
  final String customerId;
  final DateTime createdAt;
  final int amount;
  final BusinessPaymentMethod method;
  final BusinessPaymentType type;
  final String description;
  final String? reversesPaymentId;
  final String? idempotencyKey;

  int get signedAmount => type == BusinessPaymentType.refund ? -amount : amount;

  Map<String, dynamic> toJson() => {
    'id': id, 'appointment_id': appointmentId, 'customer_id': customerId,
    'created_at': createdAt.toIso8601String(), 'amount': amount,
    'method': method.name, 'type': type.name, 'description': description,
    'reverses_payment_id': reversesPaymentId, 'idempotency_key': idempotencyKey,
  };

  factory AppointmentPayment.fromJson(Map<String, dynamic> json) => AppointmentPayment(
    id: json['id'] as String,
    appointmentId: json['appointment_id'] as String,
    customerId: json['customer_id'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    amount: ((json['amount_toman'] ?? json['amount']) as num).toInt(),
    method: _paymentMethodFromKey(json['method'] as String?) ?? BusinessPaymentMethod.other,
    type: BusinessPaymentType.values.firstWhere((v) => v.name == (json['payment_type'] ?? json['type']), orElse: () => BusinessPaymentType.receipt),
    description: json['description'] as String? ?? '',
    reversesPaymentId: json['reverses_payment_id'] as String?,
    idempotencyKey: json['idempotency_key'] as String?,
  );
}

/// هزینه عمومی مجموعه؛ سند منبع اختیاری است و اسناد پیوست به رکورد هزینه لینک می‌شوند.
class BusinessExpense {
  const BusinessExpense({
    required this.id,
    required this.createdAt,
    required this.amount,
    required this.category,
    required this.description,
    required this.sourceDocumentId,
    required this.createdBy,
    this.status = BusinessExpenseStatus.posted,
    this.expenseDate,
    this.paymentMethod,
    this.idempotencyKey,
    this.relatedAppointmentId,
    this.relatedCustomerId,
    this.reversedAt,
    this.reversedBy,
    this.reversalReason,
  });

  final String id;
  final DateTime createdAt;
  final int amount;
  final BusinessExpenseCategory category;
  final String description;
  final String sourceDocumentId;
  final String createdBy;
  final BusinessExpenseStatus status;
  final DateTime? expenseDate;
  final BusinessPaymentMethod? paymentMethod;
  final String? idempotencyKey;
  final String? relatedAppointmentId;
  final String? relatedCustomerId;
  final DateTime? reversedAt;
  final String? reversedBy;
  final String? reversalReason;

  Map<String, dynamic> toJson() => {
    'id': id, 'created_at': createdAt.toIso8601String(), 'amount': amount,
    'category': category.name, 'description': description,
    'source_document_id': sourceDocumentId, 'created_by': createdBy,
    'status': status.name, 'expense_date': expenseDate?.toIso8601String(),
    'payment_method': paymentMethod == null ? null : _paymentMethodKey(paymentMethod!),
    'idempotency_key': idempotencyKey,
    'related_appointment_id': relatedAppointmentId,
    'related_customer_id': relatedCustomerId,
    'reversed_at': reversedAt?.toIso8601String(), 'reversed_by': reversedBy,
    'reversal_reason': reversalReason,
  };

  factory BusinessExpense.fromJson(Map<String, dynamic> json) => BusinessExpense(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    amount: ((json['amount_toman'] ?? json['amount']) as num).toInt(),
    category: BusinessExpenseCategory.values.firstWhere((v) => v.name == json['category'], orElse: () => BusinessExpenseCategory.other),
    description: json['description'] as String? ?? '',
    sourceDocumentId: json['source_document_id'] as String? ?? '',
    createdBy: json['created_by'] as String? ?? '',
    status: BusinessExpenseStatus.values.firstWhere((v) => v.name == json['status'], orElse: () => BusinessExpenseStatus.posted),
    expenseDate: json['expense_date'] == null ? null : DateTime.parse(json['expense_date'] as String),
    paymentMethod: _paymentMethodFromKey(json['payment_method'] as String?),
    idempotencyKey: json['idempotency_key'] as String?,
    relatedAppointmentId: json['related_appointment_id'] as String?,
    relatedCustomerId: json['related_customer_id'] as String?,
    reversedAt: json['reversed_at'] == null ? null : DateTime.parse(json['reversed_at'] as String),
    reversedBy: json['reversed_by'] as String?,
    reversalReason: json['reversal_reason'] as String?,
  );
}

String _paymentMethodKey(BusinessPaymentMethod value) => switch (value) {
  BusinessPaymentMethod.cash => 'cash',
  BusinessPaymentMethod.pos => 'pos',
  BusinessPaymentMethod.bankTransfer => 'bank_transfer',
  BusinessPaymentMethod.wallet => 'wallet',
  BusinessPaymentMethod.other => 'other',
};

BusinessPaymentMethod? _paymentMethodFromKey(String? value) => switch (value) {
  'cash' => BusinessPaymentMethod.cash,
  'pos' => BusinessPaymentMethod.pos,
  'bank_transfer' || 'bankTransfer' => BusinessPaymentMethod.bankTransfer,
  'wallet' => BusinessPaymentMethod.wallet,
  'other' => BusinessPaymentMethod.other,
  _ => null,
};

/// Metadata for a private finance file stored in Supabase Storage.
class BusinessFinanceDocument {
  const BusinessFinanceDocument({
    required this.id,
    required this.documentType,
    required this.createdAt,
    required this.createdBy,
    required this.status,
    this.documentNumber,
    this.appointmentId,
    this.customerId,
    this.expenseId,
    this.paymentId,
    this.amount,
    this.storagePath,
    this.fileName,
    this.mimeType,
    this.fileSizeBytes,
    this.notes = '',
    this.voidedAt,
    this.voidedBy,
  });

  final String id;
  final String documentType;
  final DateTime createdAt;
  final String createdBy;
  final String status;
  final String? documentNumber;
  final String? appointmentId;
  final String? customerId;
  final String? expenseId;
  final String? paymentId;
  final int? amount;
  final String? storagePath;
  final String? fileName;
  final String? mimeType;
  final int? fileSizeBytes;
  final String notes;
  final DateTime? voidedAt;
  final String? voidedBy;

  factory BusinessFinanceDocument.fromJson(Map<String, dynamic> json) =>
      BusinessFinanceDocument(
        id: json['id'] as String,
        documentType: json['document_type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        createdBy: json['created_by'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        documentNumber: json['document_number'] as String?,
        appointmentId: json['appointment_id'] as String?,
        customerId: json['customer_id'] as String?,
        expenseId: json['expense_id'] as String?,
        paymentId: json['payment_id'] as String?,
        amount: (json['amount_toman'] as num?)?.toInt(),
        storagePath: json['storage_path'] as String?,
        fileName: json['file_name'] as String?,
        mimeType: json['mime_type'] as String?,
        fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
        notes: json['notes'] as String? ?? '',
        voidedAt: json['voided_at'] == null ? null : DateTime.parse(json['voided_at'] as String),
        voidedBy: json['voided_by'] as String?,
      );
}
