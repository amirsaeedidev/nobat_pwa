import '../mock/app_database.dart';
import '../models/activity_log.dart';
import '../models/employee_wallet.dart';
import '../models/enums.dart';

/// ورودی یک عملیات حساس؛ UI جزئیات آن را برای تأیید نمایش می‌دهد.
class SensitiveOperationPreview {
  const SensitiveOperationPreview({
    required this.title,
    required this.description,
    required this.recordDetails,
    required this.isReversible,
    this.warning,
  });

  final String title;
  final String description;
  final Map<String, String> recordDetails;
  final bool isReversible;
  final String? warning;
}

/// نقطه ورود واحد عملیات حساس؛ تمام تغییرات از مسیر AppDatabase و Audit Log می‌گذرند.
class OperationsRepository {
  OperationsRepository(this._db);

  final AppDatabase _db;

  Future<void> deleteCustomer(String id) async {
    final item = _db.customerById(id);
    if (item == null) throw StateError('مشتری پیدا نشد.');
    await _db.delay(80);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'customer-delete:$id',
      operationType: 'customer_delete',
      entityName: 'مشتری',
      entityId: id,
      description: 'حذف مشتری «${item.fullName}» با شماره ${item.phone}',
      reversible: true,
      action: () => _db.deleteCustomer(id),
    );
  }

  Future<void> deleteEmployee(String id) async {
    final item = _db.employeeById(id);
    if (item == null) throw StateError('پرسنل پیدا نشد.');
    await _db.delay(80);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'employee-delete:$id',
      operationType: 'employee_delete_or_archive',
      entityName: 'پرسنل',
      entityId: id,
      description: 'حذف یا بایگانی پرسنل «${item.fullName}»؛ سوابق وابسته حفظ می‌شوند.',
      reversible: true,
      action: () => _db.deleteEmployee(id),
    );
  }

  Future<void> deleteService(String id) async {
    final item = _db.serviceById(id);
    if (item == null) throw StateError('خدمت پیدا نشد.');
    await _db.delay(80);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'service-delete:$id',
      operationType: 'service_delete_or_archive',
      entityName: 'خدمت',
      entityId: id,
      description: 'حذف یا بایگانی خدمت «${item.title}»؛ تاریخچه نوبت‌ها حفظ می‌شود.',
      reversible: true,
      action: () => _db.deleteService(id),
    );
  }

  Future<void> deleteServiceCategory(String name, {String? moveServicesTo}) async {
    if (!_db.serviceCategories.contains(name)) throw StateError('دسته‌بندی پیدا نشد.');
    await _db.delay(60);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'service-category-delete:$name:${moveServicesTo ?? 'none'}',
      operationType: 'service_category_delete',
      entityName: 'دسته‌بندی خدمت',
      entityId: name,
      description: 'حذف دسته‌بندی «$name» و انتقال خدمات وابسته به ${moveServicesTo ?? 'بدون مقصد'}.',
      reversible: true,
      action: () => _db.deleteServiceCategory(name, moveServicesTo: moveServicesTo),
    );
  }

  Future<void> cancelAppointment(String id, {String? reason}) async {
    final appointment = _db.appointmentById(id);
    if (appointment == null) throw StateError('نوبت پیدا نشد.');
    await _db.delay(60);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'appointment-cancel:$id',
      operationType: 'appointment_cancel',
      entityName: 'نوبت',
      entityId: id,
      description: 'لغو نوبت ${appointment.reference} برای ${appointment.customerName}.',
      reversible: true,
      action: () => _db.changeStatus(appointment, AppointmentStatus.cancelled,
        reason: reason, operationType: 'appointment_cancel'),
    );
  }

  Future<void> rejectAppointment(String id, {String? reason}) async {
    final appointment = _db.appointmentById(id);
    if (appointment == null) throw StateError('نوبت پیدا نشد.');
    await _db.delay(60);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'appointment-reject:$id',
      operationType: 'appointment_reject',
      entityName: 'نوبت',
      entityId: id,
      description: 'رد درخواست نوبت ${appointment.reference} برای ${appointment.customerName}.',
      reversible: true,
      action: () => _db.changeStatus(appointment, AppointmentStatus.cancelled,
        reason: 'رد درخواست: ${reason ?? 'بدون توضیح'}', operationType: 'appointment_reject'),
    );
  }

  Future<void> deleteAppointment(String id) async {
    final appointment = _db.appointmentById(id);
    if (appointment == null) throw StateError('نوبت پیدا نشد.');
    await _db.delay(60);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'appointment-delete:$id',
      operationType: 'appointment_delete',
      entityName: 'نوبت',
      entityId: id,
      description: 'حذف نوبت ${appointment.reference} برای ${appointment.customerName}.',
      reversible: true,
      action: () => _db.deleteAppointment(id),
    );
  }

  /// حذف تراکنش مالی عمداً وجود ندارد؛ تنها اصلاح با سند معکوس مجاز است.
  Future<List<EmployeeWalletTransaction>> correctWalletTransaction({
    required String transactionId,
    required int correctedAmount,
    required String description,
  }) async {
    await _db.delay(60);
    return _db.executeSensitiveOperation<List<EmployeeWalletTransaction>>(
      idempotencyKey: 'wallet-correction:$transactionId',
      operationType: 'financial_correction',
      entityName: 'تراکنش کیف پول',
      entityId: transactionId,
      description: 'اصلاح تراکنش $transactionId با سند معکوس و اصلاحیه: $description',
      reversible: false,
      action: () => _db.correctWalletTransaction(
        transactionId: transactionId,
        correctedAmount: correctedAmount,
        description: description,
      ),
    );
  }

  Future<void> assignEmployeeRole({
    required String employeeId,
    required String roleId,
    Map<String, bool> overrides = const {},
    bool canViewOtherEmployees = false,
    bool canViewPersonalIncome = true,
  }) async {
    await _db.delay(60);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'employee-access:$employeeId:$roleId:${DateTime.now().microsecondsSinceEpoch}',
      operationType: 'access_assignment',
      entityName: 'دسترسی پرسنل',
      entityId: employeeId,
      description: 'تغییر نقش و مجوزهای پرسنل ${_db.employeeById(employeeId)?.fullName ?? employeeId}.',
      reversible: true,
      action: () => _db.assignEmployeeAccess(
        employeeId: employeeId,
        roleId: roleId,
        overrides: overrides,
        canViewOtherEmployees: canViewOtherEmployees,
        canViewPersonalIncome: canViewPersonalIncome,
      ),
    );
  }

  bool canUndo(String activityLogId) => _db.canUndoLog(activityLogId);

  bool undo(String activityLogId) => _db.undoLog(activityLogId);

  List<ActivityLog> get auditHistory => _db.activityLogs
      .where((item) => item.operationType != null || item.undoAction != null)
      .toList(growable: false);
}
