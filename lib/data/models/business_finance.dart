/// اسناد مالی مجموعه؛ همه مبالغ به تومان صحیح هستند و در Datamonck محلی نگهداری می‌شوند.
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
    amount: (json['amount'] as num).toInt(),
    method: BusinessPaymentMethod.values.firstWhere((v) => v.name == json['method'], orElse: () => BusinessPaymentMethod.other),
    type: BusinessPaymentType.values.firstWhere((v) => v.name == json['type'], orElse: () => BusinessPaymentType.receipt),
    description: json['description'] as String? ?? '',
    reversesPaymentId: json['reverses_payment_id'] as String?,
    idempotencyKey: json['idempotency_key'] as String?,
  );
}

/// هزینه عمومی مجموعه؛ سند منبع و ثبت‌کننده برای ردیابی اجباری است.
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
  });

  final String id;
  final DateTime createdAt;
  final int amount;
  final BusinessExpenseCategory category;
  final String description;
  final String sourceDocumentId;
  final String createdBy;
  final BusinessExpenseStatus status;

  Map<String, dynamic> toJson() => {
    'id': id, 'created_at': createdAt.toIso8601String(), 'amount': amount,
    'category': category.name, 'description': description,
    'source_document_id': sourceDocumentId, 'created_by': createdBy,
    'status': status.name,
  };

  factory BusinessExpense.fromJson(Map<String, dynamic> json) => BusinessExpense(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    amount: (json['amount'] as num).toInt(),
    category: BusinessExpenseCategory.values.firstWhere((v) => v.name == json['category'], orElse: () => BusinessExpenseCategory.other),
    description: json['description'] as String? ?? '',
    sourceDocumentId: json['source_document_id'] as String,
    createdBy: json['created_by'] as String,
    status: BusinessExpenseStatus.values.firstWhere((v) => v.name == json['status'], orElse: () => BusinessExpenseStatus.posted),
  );
}
