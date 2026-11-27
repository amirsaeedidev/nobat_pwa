import 'enums.dart';

/// گزارش فعالیت کاربران — جدول activity_logs.
class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.actor,
    required this.createdAt,
    this.entityName = '',
    this.entityId = '',
    this.undoAction,
    this.undoData,
    this.operationType,
    this.isReversible = false,
    this.idempotencyKey,
    this.operationId,
    this.isUndone = false,
  });

  final String id;
  final ActivityType type;
  final String title;
  final String description;
  final String actor;
  final DateTime createdAt;
  final String entityName;
  final String entityId;
  final String? undoAction;
  final Map<String, dynamic>? undoData;
  /// نوع عملیات دامنه‌ای برای ممیزی و گزارش‌گیری.
  final String? operationType;
  /// فقط عملیات دارای مسیر بازگردانی واقعی true می‌شوند.
  final bool isReversible;
  /// کلید جلوگیری از اجرای دوباره عملیات.
  final String? idempotencyKey;
  final String? operationId;
  final bool isUndone;

  String get operationLabel => switch (operationType) {
    'customer_create' => 'ثبت مشتری',
    'customer_update' => 'ویرایش مشتری',
    'customer_delete' => 'حذف مشتری',
    'customer_archive' => 'بایگانی مشتری',
    'employee_create' => 'افزودن پرسنل',
    'employee_update' => 'ویرایش پرسنل',
    'employee_delete' => 'حذف پرسنل',
    'employee_archive' => 'بایگانی پرسنل',
    'service_create' => 'افزودن خدمت',
    'service_update' => 'ویرایش خدمت',
    'service_delete' => 'حذف خدمت',
    'service_archive' => 'بایگانی خدمت',
    'service_category_delete' => 'حذف دسته‌بندی خدمت',
    'appointment_create' => 'ثبت نوبت',
    'appointment_update' => 'ویرایش نوبت',
    'appointment_confirm' => 'تأیید نوبت',
    'appointment_complete' => 'تکمیل نوبت',
    'appointment_no_show' => 'ثبت عدم حضور',
    'appointment_cancel' => 'لغو نوبت',
    'appointment_reject' => 'رد درخواست نوبت',
    'appointment_delete' => 'حذف نوبت',
    'appointment_reschedule' => 'جابه‌جایی نوبت',
    'access_role_create' => 'ایجاد نقش دسترسی',
    'access_assignment' => 'تغییر دسترسی پرسنل',
    'access_role_update' => 'ویرایش نقش',
    'access_role_reset' => 'بازنشانی نقش',
    'financial_attendance_policy_update' => 'تغییر قانون مالی حضور و غیاب',
    'financial_pay_profile_update' => 'تغییر قرارداد مالی',
    'financial_salary_contract_create' => 'ثبت قرارداد حقوق',
    'financial_payroll_adjustment' => 'ثبت پاداش یا کسورات',
    'financial_payroll_advance' => 'ثبت مساعده',
    'financial_payroll_accrual' => 'ثبت حقوق ماهانه',
    'financial_wallet_entry' => 'ثبت تراکنش کیف پول',
    'financial_wallet_settlement' => 'تسویه کیف پول',
    'financial_payment_create' => 'ثبت دریافت مشتری',
    'financial_refund' => 'برگشت وجه',
    'financial_expense_create' => 'ثبت هزینه مجموعه',
    'financial_commission_refund' => 'برگشت پورسانت',
    'financial_correction' => 'اصلاح سند مالی',
    'employee_service_config_update' => 'تغییر تخصص پرسنل',
    'employee_service_config_remove' => 'حذف تخصص پرسنل',
    'undo' => 'بازگردانی عملیات',
    _ => operationType ?? type.label,
  };

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.key,
        'title': title,
        'description': description,
        'actor': actor,
        'created_at': createdAt.toUtc().toIso8601String(),
        'entity_name': entityName,
        'entity_id': entityId,
        'undo_action': undoAction,
        'undo_data': undoData,
        'operation_type': operationType,
        'is_reversible': isReversible,
        'idempotency_key': idempotencyKey,
        'operation_id': operationId,
        'is_undone': isUndone,
      };

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
        id: json['id'] as String,
        type: ActivityType.fromKey(json['type'] as String? ?? 'appointmentCreated'),
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        actor: json['actor'] as String? ?? 'سیستم',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        entityName: json['entity_name'] as String? ?? '',
        entityId: json['entity_id'] as String? ?? '',
        undoAction: json['undo_action'] as String?,
        undoData: json['undo_data'] == null ? null : Map<String, dynamic>.from(json['undo_data'] as Map),
        operationType: json['operation_type'] as String?,
        isReversible: json['is_reversible'] as bool? ?? (json['undo_action'] != null && json['undo_data'] != null),
        idempotencyKey: json['idempotency_key'] as String?,
        operationId: json['operation_id'] as String?,
        isUndone: json['is_undone'] as bool? ?? json['undone_by_event_id'] != null,
      );
}
