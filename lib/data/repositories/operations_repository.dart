import '../mock/app_database.dart';
import '../models/activity_log.dart';
import '../models/access_control.dart';
import '../models/business_finance.dart';
import '../models/employee_finance.dart';
import '../models/employee_payroll.dart';
import '../models/employee_wallet.dart';
import '../models/employee_hr.dart';
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

  /// تکمیل نوبت یک عملیات مالی قطعی است؛ اسناد پورسانت/درآمد با کلید یکتا ثبت می‌شوند.
  Future<void> completeAppointment(String id) async {
    final appointment = _db.appointmentById(id);
    if (appointment == null) throw StateError('نوبت پیدا نشد.');
    await _db.delay(60);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'appointment-complete-financial:$id',
      operationType: 'appointment_complete_financial_posting',
      entityName: 'نوبت و اسناد مالی',
      entityId: id,
      description: 'تکمیل نوبت ${appointment.reference} و ثبت اسناد مالی وابسته.',
      reversible: false,
      action: () => _db.changeStatus(
        appointment,
        AppointmentStatus.completed,
        operationType: 'appointment_complete_financial_posting',
      ),
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

  Future<AccessRole> createAccessRole({
    required String name,
    List<String> permissionIds = const [],
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError('نام نقش الزامی است.');
    await _db.delay(40);
    return _db.executeSensitiveOperation<AccessRole>(
      idempotencyKey: 'access-role-create:$normalized',
      operationType: 'access_role_create',
      entityName: 'نقش دسترسی',
      entityId: 'custom-role:$normalized',
      description: 'ایجاد نقش سفارشی «$normalized» با ${permissionIds.length} مجوز.',
      reversible: true,
      action: () => _db.createAccessRole(name: normalized, permissionIds: permissionIds),
    );
  }

  Future<void> updateAccessRole(String roleId, {required String name, required List<String> permissionIds}) async {
    await _db.delay(40);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'access-role-update:$roleId:${DateTime.now().microsecondsSinceEpoch}',
      operationType: 'access_role_update',
      entityName: 'نقش دسترسی',
      entityId: roleId,
      description: 'ویرایش نقش «$name» و مجوزهای آن.',
      reversible: true,
      action: () => _db.updateAccessRole(roleId, name: name, permissionIds: permissionIds),
    );
  }

  Future<void> resetAccessRole(String roleId) async {
    await _db.delay(40);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'access-role-reset:$roleId:${DateTime.now().microsecondsSinceEpoch}',
      operationType: 'access_role_reset',
      entityName: 'نقش دسترسی',
      entityId: roleId,
      description: 'بازنشانی نقش دسترسی $roleId به مقادیر پیش‌فرض.',
      reversible: true,
      action: () => _db.resetAccessRole(roleId),
    );
  }

  Future<bool> saveAttendancePayrollPolicy(AttendancePayrollPolicy policy) async {
    await _db.delay(40);
    final key = 'attendance-payroll-policy:${policy.enabled}:${policy.lateDeductionPerMinute}:${policy.absenceDeductionPerDay}:${policy.overtimePaymentPerMinute}:${policy.earlyLeaveDeductionPerMinute}:${DateTime.now().microsecondsSinceEpoch}';
    return _db.executeSensitiveOperation<bool>(
      idempotencyKey: key,
      operationType: 'financial_attendance_policy_update',
      entityName: 'قانون مالی حضور و غیاب',
      entityId: 'attendance-payroll-policy',
      description: 'تغییر نرخ‌های مالی محاسبه حضور و غیاب.',
      reversible: true,
      action: () => _db.saveAttendancePayrollPolicy(policy),
      shouldConsumeKey: (changed) => changed,
    );
  }

  Future<void> savePayProfile(EmployeePayProfile profile) async {
    await _db.delay(50);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'pay-profile-update:${profile.employeeId}:${DateTime.now().microsecondsSinceEpoch}',
      operationType: 'financial_pay_profile_update',
      entityName: 'قرارداد مالی پرسنل',
      entityId: profile.employeeId,
      description: 'تغییر مدل پرداخت و پورسانت پرسنل ${_db.employeeById(profile.employeeId)?.fullName ?? profile.employeeId}.',
      reversible: true,
      action: () => _db.savePayProfile(profile),
    );
  }

  Future<void> saveSalaryContract(SalaryContract contract) async {
    await _db.delay(50);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'salary-contract:${contract.id}',
      operationType: 'financial_salary_contract_create',
      entityName: 'قرارداد حقوق',
      entityId: contract.id,
      description: 'ثبت قرارداد حقوق برای پرسنل ${contract.employeeId}.',
      reversible: false,
      action: () => _db.saveSalaryContract(contract),
    );
  }

  Future<void> addPayrollAdjustment(PayrollAdjustment adjustment) async {
    await _db.delay(50);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'payroll-adjustment:${adjustment.id}',
      operationType: 'financial_payroll_adjustment',
      entityName: 'آیتم حقوق',
      entityId: adjustment.id,
      description: 'ثبت پاداش یا کسورات برای پرسنل ${adjustment.employeeId}.',
      reversible: false,
      action: () => _db.addPayrollAdjustment(adjustment),
    );
  }

  Future<void> addPayrollAdvance(PayrollAdvance advance) async {
    await _db.delay(50);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'payroll-advance:${advance.id}',
      operationType: 'financial_payroll_advance',
      entityName: 'مساعده پرسنل',
      entityId: advance.id,
      description: 'ثبت مساعده برای پرسنل ${advance.employeeId}.',
      reversible: false,
      action: () => _db.addPayrollAdvance(advance),
    );
  }

  Future<EmployeeWalletTransaction> addWalletTransaction({
    required String employeeId,
    required int amount,
    required EmployeeWalletTransactionType type,
    required String description,
    DateTime? createdAt,
    String? idempotencyKey,
    String? referenceType,
    String? referenceId,
  }) async {
    final key = idempotencyKey ?? 'wallet-entry:$employeeId:${DateTime.now().microsecondsSinceEpoch}';
    await _db.delay(50);
    return _db.executeSensitiveOperation<EmployeeWalletTransaction>(
      idempotencyKey: key,
      operationType: 'financial_wallet_entry',
      entityName: 'کیف پول پرسنل',
      entityId: employeeId,
      description: 'ثبت تراکنش «${type.label}» برای پرسنل $employeeId.',
      reversible: false,
      action: () => _db.addWalletTransaction(
        employeeId: employeeId,
        amount: amount,
        type: type,
        description: description,
        createdAt: createdAt,
        idempotencyKey: key,
        referenceType: referenceType,
        referenceId: referenceId,
      ),
    );
  }

  Future<int> accruePayrollBaseToWallet(String employeeId, {DateTime? at}) async {
    final date = at ?? DateTime.now();
    final key = 'payroll-accrual:$employeeId:${date.year}-${date.month}';
    await _db.delay(50);
    return _db.executeSensitiveOperation<int>(
      idempotencyKey: key,
      operationType: 'financial_payroll_accrual',
      entityName: 'ثبت حقوق ماهانه',
      entityId: employeeId,
      description: 'انتقال حقوق پایه و اثر حضور و غیاب پرسنل $employeeId به دفتر کیف پول.',
      reversible: false,
      action: () => _db.accruePayrollBaseToWallet(employeeId, at: date),
      shouldConsumeKey: (posted) => posted > 0,
    );
  }

  Future<EmployeeWalletSettlement> settleEmployeeWallet({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required EmployeeWalletPeriodType periodType,
    required int paidAmount,
    required String idempotencyKey,
    EmployeeWalletPaymentMethod method = EmployeeWalletPaymentMethod.bankTransfer,
    String description = 'پرداخت تسویه پرسنل',
  }) async {
    await _db.delay(50);
    return _db.executeSensitiveOperation<EmployeeWalletSettlement>(
      idempotencyKey: idempotencyKey,
      operationType: 'financial_wallet_settlement',
      entityName: 'تسویه کیف پول',
      entityId: employeeId,
      description: 'ثبت پرداخت $paidAmount برای تسویه پرسنل $employeeId.',
      reversible: false,
      action: () => _db.settleEmployeeWallet(
        employeeId: employeeId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        periodType: periodType,
        paidAmount: paidAmount,
        idempotencyKey: idempotencyKey,
        method: method,
        description: description,
      ),
    );
  }

  Future<AppointmentPayment> recordAppointmentPayment({
    required String appointmentId,
    required int amount,
    required BusinessPaymentMethod method,
    required String description,
    DateTime? createdAt,
    required String idempotencyKey,
  }) async {
    await _db.delay(50);
    return _db.executeSensitiveOperation<AppointmentPayment>(
      idempotencyKey: idempotencyKey,
      operationType: 'financial_payment_create',
      entityName: 'دریافت مشتری',
      entityId: appointmentId,
      description: 'ثبت دریافت $amount برای نوبت $appointmentId.',
      reversible: false,
      action: () => _db.recordAppointmentPayment(
        appointmentId: appointmentId,
        amount: amount,
        method: method,
        description: description,
        createdAt: createdAt,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  Future<AppointmentPayment> refundAppointmentPayment({
    required String paymentId,
    required int amount,
    required String description,
    DateTime? createdAt,
    required String idempotencyKey,
  }) async {
    await _db.delay(50);
    return _db.executeSensitiveOperation<AppointmentPayment>(
      idempotencyKey: idempotencyKey,
      operationType: 'financial_refund',
      entityName: 'برگشت وجه مشتری',
      entityId: paymentId,
      description: 'ثبت برگشت $amount برای رسید $paymentId.',
      reversible: false,
      action: () => _db.refundAppointmentPayment(
        paymentId: paymentId,
        amount: amount,
        description: description,
        createdAt: createdAt,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  Future<void> addBusinessExpense(BusinessExpense expense) async {
    await _db.delay(50);
    _db.executeSensitiveOperation<void>(
      idempotencyKey: 'business-expense:${expense.id}',
      operationType: 'financial_expense_create',
      entityName: 'هزینه مجموعه',
      entityId: expense.id,
      description: 'ثبت هزینه ${expense.amount}.',
      reversible: false,
      action: () => _db.addBusinessExpense(expense),
    );
  }

  Future<bool> recordCommissionRefund(String financeEntryId, int amount) async {
    final key = 'commission-refund:$financeEntryId:$amount:${DateTime.now().microsecondsSinceEpoch}';
    await _db.delay(50);
    return _db.executeSensitiveOperation<bool>(
      idempotencyKey: key,
      operationType: 'financial_commission_refund',
      entityName: 'برگشت پورسانت',
      entityId: financeEntryId,
      description: 'ثبت برگشت پورسانت به مبلغ $amount برای سند $financeEntryId.',
      reversible: false,
      action: () {
        final recorded = _db.recordCommissionRefund(financeEntryId, amount);
        if (!recorded) throw StateError('سند پورسانت برای برگشت وجه پیدا نشد.');
        return recorded;
      },
    );
  }

  ActivityLog? latestUndoableLogFor(String entityId) {
    for (final entry in _db.activityLogs) {
      if (entry.entityId == entityId && entry.isReversible && _db.canUndoLog(entry.id)) return entry;
    }
    return null;
  }

  bool canUndo(String activityLogId) => _db.canUndoLog(activityLogId);

  bool undo(String activityLogId) => _db.undoLog(activityLogId);

  bool undoLatestForEntity(String entityId) {
    final entry = latestUndoableLogFor(entityId);
    return entry != null && _db.undoLog(entry.id);
  }

  List<ActivityLog> get auditHistory => _db.activityLogs
      .where((item) => item.operationType != null || item.undoAction != null)
      .toList(growable: false);
}
