import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/jalali.dart';
import '../models/activity_log.dart';
import '../models/appointment.dart';
import '../models/business_settings.dart';
import '../models/business_finance.dart';
import '../models/customer.dart';
import '../models/employee.dart';
import '../models/enums.dart';
import '../models/employee_finance.dart';
import '../models/employee_payroll.dart';
import '../models/employee_wallet.dart';
import '../models/employee_service_config.dart';
import '../models/employee_schedule.dart';
import '../models/employee_hr.dart';
import '../models/access_control.dart';
import '../models/service.dart';
import '../models/sms_message.dart';
import 'mock_seed.dart';

class AccessDeniedException implements Exception { const AccessDeniedException(this.message); final String message; @override String toString() => message; }

/// پایگاه‌داده درون‌حافظه‌ای (شبیه‌ساز Supabase در این فاز).
/// تمام تغییرات، گزارش فعالیت و وضعیت‌های وابسته را به‌صورت مرکزی به‌روزرسانی می‌کند.
class AppDatabase extends ChangeNotifier {
  AppDatabase({bool seed = true}) {
    if (seed) _seed();
  }

  final List<Customer> _customers = [];
  final List<Appointment> _appointments = [];
  final List<Service> _services = [];
  final List<String> _serviceCategories = [];
  final List<Employee> _employees = [];
  final List<SmsMessage> _sms = [];
  final List<ActivityLog> _logs = [];
  final List<SmsTemplate> _templates = [];
  final Map<String, EmployeePayProfile> _employeePayProfiles = {};
  final Map<String, List<SalaryContract>> _salaryContracts = {};
  final List<PayrollAdjustment> _payrollAdjustments = [];
  final List<PayrollAdvance> _payrollAdvances = [];
  final List<EmployeePerformanceTarget> _performanceTargets = [];
  final List<EmployeeFinanceEntry> _employeeFinanceEntries = [];
  final List<EmployeeWalletTransaction> _employeeWalletTransactions = [];
  final List<EmployeeWalletSettlement> _employeeWalletSettlements = [];
  final List<EmployeeWalletPayment> _employeeWalletPayments = [];
  final List<EmployeeWalletSettlementRequest> _employeeWalletSettlementRequests = [];
  final List<AppointmentPayment> _appointmentPayments = [];
  final List<BusinessExpense> _businessExpenses = [];
  final Map<String, EmployeeServiceConfig> _employeeServiceConfigs = {};
  final Map<String, EmployeeScheduleException> _employeeScheduleExceptions = {};
  final List<EmployeeLeave> _employeeLeaves = [];
  final List<AttendanceRecord> _attendanceRecords = [];
  final List<EmployeeDocument> _employeeDocuments = [];
  final List<EmployeeNotice> _employeeNotices = [];
  AttendancePayrollPolicy _attendancePayrollPolicy = const AttendancePayrollPolicy();
  AttendancePayrollPolicy get attendancePayrollPolicy => _attendancePayrollPolicy;
  final Map<String, AccessRole> _accessRoles = {};
  final Map<String, AccessAssignment> _accessAssignments = {};
  final List<AccessAccount> _accessAccounts = [];
  String _currentAccessAccountId = 'demo-global-admin';
  BusinessSettings _settings = const BusinessSettings(
    name: '',
    slogan: '',
    description: '',
    phone: '',
    mobile: '',
    email: '',
    province: '',
    city: '',
    address: '',
    postalCode: '',
    latitude: 0,
    longitude: 0,
    currency: '',
    logoText: '',
    smsProvider: SmsProviderSettings(providerName: '', endpoint: '', credit: 0),
    notifications: NotificationSettings(
      confirmationEnabled: false,
      reminderEnabled: false,
      cancellationEnabled: false,
      rescheduleEnabled: false,
      reminderHours: [],
      sendToStaff: false,
    ),
    bookingRules: BookingRules(
      allowCustomerCancel: false,
      allowReschedule: false,
      maxReschedules: 0,
      minHoursBeforeChange: 0,
      maxAdvanceDays: 0,
      requireConfirmation: false,
      preventOverlap: false,
      slotIntervalMinutes: 0,
      cancelPenaltyCount: 0,
    ),
  );

  int _idCounter = 5000;
  final Set<String> _undoneLogIds = {};
  final Set<String> _executedOperationKeys = {};

  bool get _isGlobalAdmin => currentAccessAccount.roleId == 'global_admin';
  String? get _activeEmployeeId => currentAccessAccount.employeeId;

  /// پرسنل فقط مشتریانی را می‌بیند که در نوبت‌های خودش ثبت شده‌اند.
  List<Customer> get customers => List.unmodifiable(_customers.where((customer) =>
    !customer.isArchived && (_isGlobalAdmin || _appointments.any((item) =>
      item.employeeId == _activeEmployeeId && item.customerId == customer.id))));
  /// Complete customer collection for the isolated mock/test adapter only.
  List<Customer> get allCustomers => List.unmodifiable(_customers);
  List<Appointment> get appointments => List.unmodifiable(_appointments.where((item) =>
    _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  List<Service> get services => List.unmodifiable(_services.where((service) =>
    _isGlobalAdmin || (_activeEmployeeId != null &&
      (_employees.firstWhere((item) => item.id == _activeEmployeeId, orElse: () => _employees.first).serviceIds.contains(service.id)))));
  List<String> get serviceCategories => List.unmodifiable(services.map((service) => service.category).toSet().toList()..sort());
  List<Employee> get employees => List.unmodifiable(_employees.where((employee) =>
    _isGlobalAdmin || employee.id == _activeEmployeeId));
  List<SmsMessage> get smsMessages => List.unmodifiable(_isGlobalAdmin ? _sms : const <SmsMessage>[]);
  List<ActivityLog> get activityLogs => List.unmodifiable(_isGlobalAdmin ? _logs : const <ActivityLog>[]);
  List<SmsTemplate> get smsTemplates => List.unmodifiable(_isGlobalAdmin ? _templates : const <SmsTemplate>[]);
  List<EmployeeFinanceEntry> get employeeFinanceEntries => List.unmodifiable(_employeeFinanceEntries.where((entry) =>
    _isGlobalAdmin || (entry.employeeId == _activeEmployeeId &&
      (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund))));
  List<PayrollAdjustment> get payrollAdjustments => List.unmodifiable(_payrollAdjustments.where((item) =>
    _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  List<PayrollAdvance> get payrollAdvances => List.unmodifiable(
    _payrollAdvances.where((item) =>
      currentAccessAccount.roleId == 'global_admin' ||
      item.employeeId == currentAccessAccount.employeeId),
  );
  List<EmployeePerformanceTarget> get performanceTargets => List.unmodifiable(_performanceTargets.where((item) => _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  /// Public wallet collections are row-scoped too; callers cannot bypass walletTransactionsFor.
  List<EmployeeWalletTransaction> get employeeWalletTransactions => List.unmodifiable(
    _employeeWalletTransactions.where((entry) =>
      canViewEmployeeIncome(entry.employeeId) &&
      (hasPermission('finance.salary.view', employeeId: entry.employeeId) ||
        entry.type == EmployeeWalletTransactionType.commission ||
        entry.type == EmployeeWalletTransactionType.refund)),
  );
  List<EmployeeWalletSettlement> get employeeWalletSettlements => List.unmodifiable(
    _employeeWalletSettlements.where((entry) =>
      hasPermission('finance.salary.view', employeeId: entry.employeeId) &&
      hasPermission('finance.settlement.view', employeeId: entry.employeeId)),
  );
  List<EmployeeWalletPayment> get employeeWalletPayments => List.unmodifiable(
    _employeeWalletPayments.where((entry) =>
      hasPermission('finance.salary.view', employeeId: entry.employeeId) &&
      hasPermission('finance.settlement.view', employeeId: entry.employeeId)),
  );
  List<AppointmentPayment> get appointmentPayments => List.unmodifiable(_isGlobalAdmin ? _appointmentPayments : const <AppointmentPayment>[]);
  List<BusinessExpense> get businessExpenses => List.unmodifiable(_isGlobalAdmin ? _businessExpenses : const <BusinessExpense>[]);
  List<EmployeeLeave> get employeeLeaves => List.unmodifiable(_employeeLeaves.where((item) => _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  List<AttendanceRecord> get attendanceRecords => List.unmodifiable(_attendanceRecords.where((item) => _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  List<EmployeeDocument> get employeeDocuments => List.unmodifiable(_employeeDocuments.where((item) => _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  List<EmployeeNotice> get employeeNotices => List.unmodifiable(_employeeNotices.where((item) => _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  List<AccessRole> get accessRoles => List.unmodifiable(_accessRoles.values);
  /// حساب‌های آزمایشی فقط برای جابه‌جایی بین دو نقش در محیط آفلاین Datamonck.
  List<AccessAccount> get accessAccounts => List.unmodifiable(_accessAccounts);
  AccessAccount get currentAccessAccount => _accessAccounts.isEmpty
      ? const AccessAccount(id: 'unauthenticated', name: 'کاربر واردنشده', roleId: 'unauthenticated', isDemo: false)
      : _accessAccounts.firstWhere((account) => account.id == _currentAccessAccountId, orElse: () => _accessAccounts.first);
  String get currentAccessRoleName => _accessRoles[currentAccessAccount.roleId]?.name ?? 'نقش نامشخص';
  List<EmployeeScheduleException> get employeeScheduleExceptions => List.unmodifiable(_employeeScheduleExceptions.values.where((item) => _isGlobalAdmin || item.employeeId == _activeEmployeeId));
  EmployeePayProfile payProfileFor(String employeeId) {
    requirePermission('finance.salary.view', employeeId: employeeId);
    return _employeePayProfiles[employeeId] ?? EmployeePayProfile(employeeId: employeeId);
  }
  BusinessSettings get settings => _settings;

  /// داده‌های نمونه پرداخت و هزینه مجموعه؛ صرفاً برای Datamonck آفلاین.
  void _seedBusinessFinance() {
    var index = 0;
    for (final appointment in _appointments.where((item) => item.status == AppointmentStatus.completed)) {
      final revenueDocuments = _employeeFinanceEntries
          .where((entry) => entry.appointmentId == appointment.id && entry.type == FinanceEntryType.commission)
          .toList();
      final received = revenueDocuments.fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      if (received <= 0 || revenueDocuments.isEmpty) continue;
      final methods = BusinessPaymentMethod.values;
      _appointmentPayments.add(AppointmentPayment(
        id: 'payment-seed-${appointment.id}',
        appointmentId: appointment.id,
        customerId: appointment.customerId,
        createdAt: revenueDocuments.first.createdAt,
        amount: received,
        method: methods[index++ % methods.length],
        type: BusinessPaymentType.receipt,
        description: 'دریافت نمونه Datamonck برای نوبت ${appointment.reference}',
        idempotencyKey: 'seed-payment-${appointment.id}',
      ));
    }
    final now = DateTime.now();
    _businessExpenses.addAll([
      BusinessExpense(id: 'expense-seed-rent', createdAt: now.subtract(const Duration(days: 3)), amount: 6500000, category: BusinessExpenseCategory.rent, description: 'اجاره فضای مجموعه (نمونه)', sourceDocumentId: 'DOC-DM-RENT-001', createdBy: 'Datamonck'),
      BusinessExpense(id: 'expense-seed-supplies', createdAt: now.subtract(const Duration(days: 2)), amount: 1250000, category: BusinessExpenseCategory.supplies, description: 'خرید مواد مصرفی (نمونه)', sourceDocumentId: 'DOC-DM-SUP-001', createdBy: 'Datamonck'),
      BusinessExpense(id: 'expense-seed-utilities', createdAt: now.subtract(const Duration(days: 1)), amount: 480000, category: BusinessExpenseCategory.utilities, description: 'قبوض و خدمات (نمونه)', sourceDocumentId: 'DOC-DM-UTIL-001', createdBy: 'Datamonck'),
    ]);
  }

  List<AppointmentPayment> paymentsForAppointment(String appointmentId) =>
      _appointmentPayments.where((item) => item.appointmentId == appointmentId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  AppointmentPayment recordAppointmentPayment({
    required String appointmentId,
    required int amount,
    required BusinessPaymentMethod method,
    required String description,
    DateTime? createdAt,
    required String idempotencyKey,
  }) {
    requirePermission('finance.payment.create');
    final matches = _appointments.where((item) => item.id == appointmentId).toList();
    if (matches.isEmpty) throw StateError('نوبت مورد نظر پیدا نشد.');
    if (amount <= 0 || description.trim().isEmpty) throw ArgumentError('مبلغ و توضیحات پرداخت معتبر نیست.');
    if (idempotencyKey.trim().isEmpty || _appointmentPayments.any((item) => item.idempotencyKey == idempotencyKey)) {
      throw StateError('این پرداخت قبلاً ثبت شده است.');
    }
    final appointment = matches.first;
    final revenueDocuments = _employeeFinanceEntries.where((entry) =>
      entry.appointmentId == appointmentId &&
      (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund)).toList();
    final recognized = revenueDocuments.fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
    final billable = revenueDocuments.isNotEmpty ? recognized : appointment.price.round();
    final collected = _appointmentPayments.where((item) => item.appointmentId == appointmentId)
        .fold<int>(0, (sum, item) => sum + item.signedAmount);
    final outstanding = billable - collected;
    if (outstanding <= 0 || amount > outstanding) throw ArgumentError('مبلغ پرداخت از مانده قابل دریافت بیشتر است.');
    final payment = AppointmentPayment(
      id: nextId('payment'), appointmentId: appointmentId, customerId: appointment.customerId,
      createdAt: createdAt ?? DateTime.now(), amount: amount, method: method,
      type: BusinessPaymentType.receipt, description: description.trim(), idempotencyKey: idempotencyKey,
    );
    _appointmentPayments.add(payment);
    log(ActivityType.settingsChanged, 'ثبت دریافت مشتری', 'دریافت مبلغ $amount برای نوبت ${appointment.reference} ثبت شد.', entity: 'دریافت‌های مجموعه', entityId: payment.id, operationType: 'financial_payment_create', isReversible: false, idempotencyKey: idempotencyKey);
    _commit();
    return payment;
  }

  AppointmentPayment refundAppointmentPayment({
    required String paymentId,
    required int amount,
    required String description,
    DateTime? createdAt,
    required String idempotencyKey,
  }) {
    requirePermission('finance.payment.create');
    final matches = _appointmentPayments.where((item) => item.id == paymentId && item.type == BusinessPaymentType.receipt).toList();
    if (matches.isEmpty) throw StateError('رسید دریافت پیدا نشد.');
    final original = matches.first;
    if (amount <= 0 || description.trim().isEmpty) throw ArgumentError('مبلغ و توضیحات برگشت معتبر نیست.');
    if (idempotencyKey.trim().isEmpty || _appointmentPayments.any((item) => item.idempotencyKey == idempotencyKey)) {
      throw StateError('این برگشت قبلاً ثبت شده است.');
    }
    final refunded = _appointmentPayments.where((item) => item.type == BusinessPaymentType.refund && item.reversesPaymentId == paymentId)
        .fold<int>(0, (sum, item) => sum + item.amount);
    if (refunded + amount > original.amount) throw ArgumentError('مبلغ برگشت از مبلغ رسید بیشتر است.');

    final refund = AppointmentPayment(
      id: nextId('payment'), appointmentId: original.appointmentId, customerId: original.customerId,
      createdAt: createdAt ?? DateTime.now(), amount: amount, method: original.method,
      type: BusinessPaymentType.refund, description: description.trim(),
      reversesPaymentId: paymentId, idempotencyKey: idempotencyKey,
    );
    _appointmentPayments.add(refund);

    // برگشت سهم پرسنل را متناسب با مبلغ برگشتی، از همان اسناد کمیسیون برمی‌گردانیم.
    final originals = _employeeFinanceEntries.where((entry) =>
      entry.appointmentId == original.appointmentId && entry.type == FinanceEntryType.commission).toList();
    final refundable = originals.fold<int>(0, (sum, entry) {
      final already = _employeeFinanceEntries.where((item) =>
        item.type == FinanceEntryType.refund && item.reversesEntryId == entry.id)
        .fold<int>(0, (value, item) => value - item.receivedAmount);
      return sum + (entry.receivedAmount - already).clamp(0, entry.receivedAmount).toInt();
    });
    final refundableEntries = <({EmployeeFinanceEntry entry, int available})>[];
    for (final entry in originals) {
      final already = _employeeFinanceEntries.where((item) =>
        item.type == FinanceEntryType.refund && item.reversesEntryId == entry.id)
        .fold<int>(0, (value, item) => value - item.receivedAmount);
      final available = (entry.receivedAmount - already).clamp(0, entry.receivedAmount).toInt();
      if (available > 0) refundableEntries.add((entry: entry, available: available));
    }
    var left = amount.clamp(0, refundable).toInt();
    var remainingWeight = refundable;
    for (var index = 0; index < refundableEntries.length && left > 0; index++) {
      final item = refundableEntries[index];
      final allocation = index == refundableEntries.length - 1
          ? left
          : (amount * item.available ~/ remainingWeight).clamp(0, item.available).toInt();
      if (allocation > 0) {
        recordCommissionRefund(item.entry.id, allocation);
        left -= allocation;
      }
      remainingWeight -= item.available;
    }
    log(ActivityType.settingsChanged, 'ثبت برگشت وجه مشتری', 'برگشت مبلغ $amount برای نوبت ثبت شد.', entity: 'دریافت‌های مجموعه', entityId: refund.id, operationType: 'financial_refund', isReversible: false, idempotencyKey: idempotencyKey);
    _commit();
    return refund;
  }

  void addBusinessExpense(BusinessExpense expense) {
    requirePermission('finance.payment.create');
    if (expense.amount <= 0 || expense.description.trim().isEmpty ||
        expense.sourceDocumentId?.trim().isEmpty == true || expense.createdBy.trim().isEmpty) {
      throw ArgumentError('مبلغ، شرح، سند منبع و ثبت‌کننده هزینه الزامی است.');
    }
    if (_businessExpenses.any((item) => item.id == expense.id || (expense.sourceDocumentId != null && item.sourceDocumentId == expense.sourceDocumentId))) {
      throw StateError('شناسه هزینه یا سند منبع تکراری است.');
    }
    _businessExpenses.add(expense);
    log(ActivityType.settingsChanged, 'ثبت هزینه مجموعه', 'هزینه ${expense.category.label} ثبت شد.', entity: 'امور مالی مجموعه', entityId: expense.id, operationType: 'financial_expense_create', isReversible: false);
    _commit();
  }

  String nextId(String prefix) => '$prefix-${++_idCounter}';

  void _seed() {
    _customers.addAll(MockSeed.customers());
    _services.addAll(MockSeed.services());
    _serviceCategories.addAll(_services.map((service) => service.category).toSet().toList()..sort());
    _employees.addAll(MockSeed.employees());
    _seedAccessControl();
    for (final employee in _employees) {
      _syncEmployeeServiceLinks(employee);
      for (final serviceId in employee.serviceIds) {
        _employeeServiceConfigs[_serviceConfigKey(employee.id, serviceId)] = EmployeeServiceConfig(employeeId: employee.id, serviceId: serviceId);
      }
    }
    _appointments.addAll(MockSeed.appointments());
    for (var index = 0; index < _employees.length; index++) { final employee = _employees[index]; _employeePayProfiles[employee.id] = EmployeePayProfile(employeeId: employee.id, method: index == 0 ? EmployeePaymentMethod.fixedPlusCommission : EmployeePaymentMethod.commissionOnly, monthlySalary: index == 0 ? 12000000 : 0, generalRateBps: 3000, basis: CommissionBasis.afterDiscount); }
    for (final appointment in _appointments.where((item) => item.status == AppointmentStatus.completed)) { _createCommissionEntries(appointment); }
    _seedBusinessFinance();
    for (final entry in List<EmployeeFinanceEntry>.of(_employeeFinanceEntries)) { _mirrorFinanceEntryToWallet(entry); }
    _seedPayrollData();
    _seedEmployeeHr();
    _sms.addAll(MockSeed.smsMessages());
    _logs.addAll(MockSeed.activityLogs());
    _templates.addAll(MockSeed.smsTemplates());
    _settings = MockSeed.businessSettings();
    _refreshCustomerStats();
    _logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _sms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _commit() {
    _refreshCustomerStats();
    notifyListeners();
  }

  /// به‌روزرسانی آمار تجمیعی مشتریان بر اساس نوبت‌ها (سازیگما با گزارش‌ها).
  void _refreshCustomerStats() {
    for (var i = 0; i < _customers.length; i++) {
      final customer = _customers[i];
      final related = _appointments.where((a) => a.customerId == customer.id).toList();
      final completed = related.where((a) => a.status == AppointmentStatus.completed).toList();
      final cancelled = related.where((a) => a.status == AppointmentStatus.cancelled).length;
      final noShow = related.where((a) => a.status == AppointmentStatus.noShow).length;
      final last = completed.isEmpty
          ? null
          : (completed.map((a) => a.startAt).reduce((a, b) => a.isAfter(b) ? a : b));
      final spent = completed.fold<num>(0, (sum, a) => sum + a.price);
      _customers[i] = customer.copyWith(
        visitCount: completed.length,
        totalSpent: spent,
        cancelCount: cancelled,
        noShowCount: noShow,
        lastVisitAt: last ?? customer.lastVisitAt,
      );
    }
  }

  void addLog(ActivityLog log) {
    _logs.insert(0, log);
    notifyListeners();
  }

  /// ثبت رویداد با عنوان و توضیح.
  void log(ActivityType type, String title, String description, {String? actor, String entity = '', String entityId = '', String? undoAction, Map<String, dynamic>? undoData, String? operationType, bool? isReversible, String? idempotencyKey}) {
    _logs.insert(
      0,
      ActivityLog(
        id: nextId('log'),
        type: type,
        title: title,
        description: description,
        actor: actor ?? currentAccessAccount.name,
        createdAt: DateTime.now(),
        entityName: entity,
        entityId: entityId,
        undoAction: undoAction,
        undoData: undoData,
        operationType: operationType,
        isReversible: isReversible ?? (undoAction != null && undoData != null),
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  /// اجرای یک عملیات حساس با کلید idempotency و ثبت Audit Log.
  /// کلید تنها پس از موفقیت action مصرف می‌شود؛ شکست عملیات قابل تلاش مجدد است.
  T executeSensitiveOperation<T>({
    required String idempotencyKey,
    required String operationType,
    required String entityName,
    required String entityId,
    required String description,
    required bool reversible,
    required T Function() action,
    bool Function(T result)? shouldConsumeKey,
  }) {
    final key = idempotencyKey.trim();
    if (key.isEmpty) throw ArgumentError('کلید یکتای عملیات الزامی است.');
    if (_executedOperationKeys.contains(key)) throw StateError('این عملیات قبلاً اجرا شده است.');
    final logCount = _logs.length;
    final result = action();
    final consumeKey = shouldConsumeKey?.call(result) ?? true;
    final hasAuditRecord = _logs.length > logCount;
    if (consumeKey && !hasAuditRecord) {
      throw StateError('عملیات تغییری ایجاد نکرد و سابقه‌ای برای ثبت یا بازگردانی ندارد.');
    }
    if (consumeKey) _executedOperationKeys.add(key);
    if (consumeKey && _logs.length > logCount && _logs.isNotEmpty) {
      // A single domain action may append several related records (for example,
      // appointment completion plus commission postings). Attach the operation
      // key to its own audit event, not blindly to the newest child ledger event.
      final addedCount = _logs.length - logCount;
      final addedLogs = _logs.take(addedCount).toList();
      final matchingIndex = addedLogs.indexWhere(
        (entry) => entry.entityId == entityId && entry.operationType == operationType,
      );
      final auditIndex = matchingIndex >= 0 ? matchingIndex : 0;
      final audit = _logs[auditIndex];
      _logs[auditIndex] = ActivityLog(
        id: audit.id, type: audit.type, title: audit.title,
        description: audit.description.isEmpty ? description : audit.description,
        actor: audit.actor, createdAt: audit.createdAt,
        entityName: audit.entityName.isEmpty ? entityName : audit.entityName,
        entityId: audit.entityId.isEmpty ? entityId : audit.entityId,
        undoAction: audit.undoAction, undoData: audit.undoData,
        operationType: audit.operationType ?? operationType,
        isReversible: audit.isReversible && reversible,
        idempotencyKey: key,
      );
    }
    _commit();
    return result;
  }

  bool hasExecutedOperation(String key) => _executedOperationKeys.contains(key);

  // ---------------------------------------------------------------------------
  // کنترل دسترسی و نقش‌ها — منبع حقیقت در لایه داده
  // ---------------------------------------------------------------------------
  void _seedAccessControl() {
    for (final role in AccessRole.defaults()) {
      _accessRoles[role.id] = role;
    }
    _accessAccounts.addAll(const [
      AccessAccount(
        id: 'demo-global-admin',
        name: 'فاطمه رضایی — مدیر کل',
        roleId: 'global_admin',
        employeeId: 'emp-shima',
      ),
      AccessAccount(
        id: 'demo-staff',
        name: 'زهرا نوری — پرسنل',
        roleId: 'staff',
        employeeId: 'emp-zahra',
      ),
    ]);
    for (final employee in _employees) {
      _accessAssignments[employee.id] = AccessAssignment(
        employeeId: employee.id,
        roleId: 'staff',
        canViewOtherEmployees: false,
        canViewPersonalIncome: true,
      );
    }
    _accessAssignments['emp-shima'] = const AccessAssignment(
      employeeId: 'emp-shima',
      roleId: 'global_admin',
      canViewOtherEmployees: true,
      canViewPersonalIncome: true,
    );
  }

  AccessRole? accessRoleById(String id) => _accessRoles[id];
  AccessAssignment? accessAssignmentFor(String employeeId) => _accessAssignments[employeeId];

  void switchMockAccount(String accountId) {
    final matches = _accessAccounts.where((item) => item.id == accountId && item.isEnabled).toList();
    final account = matches.isEmpty ? null : matches.first;
    if (account == null) throw StateError('حساب آزمایشی معتبر یا فعال نیست.');
    _currentAccessAccountId = accountId;
    _commit();
  }

  bool hasPermission(String permissionId, {String? employeeId}) {
    final account = currentAccessAccount;
    if (!account.isEnabled) return false;
    if (account.roleId == 'global_admin') return true;
    final subjectId = account.employeeId;
    final assignment = subjectId == null ? null : _accessAssignments[subjectId];
    final override = assignment?.overrides[permissionId];
    final roleId = assignment?.roleId ?? account.roleId;
    final roleAllows = _accessRoles[roleId]?.permissionIds.contains(permissionId) ?? false;
    final allowed = override ?? roleAllows;
    if (!allowed) return false;

    // Explicit grants may override a role's permission list, but must never
    // bypass employee visibility or the personal-income privacy setting.
    if (permissionId.startsWith('finance.') && employeeId != null) {
      return canViewEmployee(employeeId) &&
          (employeeId != subjectId || (assignment?.canViewPersonalIncome ?? true));
    }
    return true;
  }

  bool canViewEmployee(String employeeId) {
    final account = currentAccessAccount;
    if (account.roleId == 'global_admin') return true;
    if (account.employeeId == employeeId) return true;
    final assignment = account.employeeId == null ? null : _accessAssignments[account.employeeId];
    return (assignment?.canViewOtherEmployees ?? false) &&
        (hasPermission('employees.view_list') || hasPermission('finance.income.view') || hasPermission('finance.salary.view'));
  }

  bool canViewEmployeeIncome(String employeeId) {
    if (!hasPermission('finance.income.view', employeeId: employeeId) &&
        !hasPermission('finance.commission.view', employeeId: employeeId) &&
        !hasPermission('finance.salary.view', employeeId: employeeId)) return false;
    final account = currentAccessAccount;
    final assignment = account.employeeId == null ? null : _accessAssignments[account.employeeId];
    if (account.employeeId == employeeId) return assignment?.canViewPersonalIncome ?? true;
    return assignment?.canViewOtherEmployees ?? account.roleId == 'global_admin';
  }

  void requirePermission(String permissionId, {String? employeeId}) {
    if (employeeId != null && !canViewEmployee(employeeId)) {
      throw const AccessDeniedException('فقط اطلاعات و عملیات مربوط به خودتان در دسترس است.');
    }
    if (!hasPermission(permissionId, employeeId: employeeId)) {
      final matches = AccessPermission.all.where((item) => item.id == permissionId).toList();
      throw AccessDeniedException('برای انجام این عملیات دسترسی «${matches.isEmpty ? permissionId : matches.first.label}» را ندارید.');
    }
  }

  bool canOpenRoute(String path) {
    if (path == '/my-wallet') {
      final employeeId = currentAccessAccount.employeeId;
      return employeeId != null && hasPermission('finance.wallet.view', employeeId: employeeId);
    }
    if (path == '/search' || path == '/search/result') return currentAccessAccount.roleId == 'global_admin';
    if (path == '/book' || path.startsWith('/book/')) return false;
    if (path == '/dashboard') return currentAccessAccount.roleId == 'global_admin';
    if (path == '/my-leaves') return currentAccessAccount.roleId == 'staff' && hasPermission('employees.leave.request', employeeId: currentAccessAccount.employeeId);
    if (path == '/access-denied') return true;
    if (path.startsWith('/settings/permissions')) return hasPermission('permissions.manage');
    if (path.startsWith('/settings/hours')) return hasPermission('settings.hours.edit');
    if (path.startsWith('/settings')) return hasPermission('settings.view') || hasPermission('permissions.manage');
    if (path.startsWith('/employees')) {
      final parts = path.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.length == 1) return hasPermission('employees.view_list');
      if (parts.length == 2 && parts[1] == 'new') return hasPermission('employees.create');
      final employeeId = parts.length > 1 ? parts[1] : '';
      if (parts.contains('wallet')) return canViewEmployeeIncome(employeeId) && hasPermission('finance.wallet.view', employeeId: employeeId);
      if (parts.contains('finance')) return canViewEmployeeIncome(employeeId) && hasPermission('finance.salary.view', employeeId: employeeId);
      if (parts.contains('schedule')) return hasPermission('employees.edit', employeeId: employeeId);
      if (parts.contains('attendance')) return hasPermission('employees.edit', employeeId: employeeId);
      if (parts.contains('analytics')) return hasPermission('finance.income.view', employeeId: employeeId);
      if (parts.contains('edit')) return canViewEmployee(employeeId) && hasPermission('employees.edit');
      return canViewEmployee(employeeId) && hasPermission('employees.view_profile');
    }
    if (path.startsWith('/appointments')) {
      if (path == '/appointments/new') return hasPermission('appointments.create');
      final parts = path.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.length >= 2 && parts[1] != 'new') {
        if (parts.contains('edit') && !hasPermission('appointments.edit')) return false;
        final appointment = appointmentById(parts[1]);
        if (appointment == null) return false;
        return hasPermission('appointments.view_all') ||
            (hasPermission('appointments.view_self') && currentAccessAccount.employeeId == appointment.employeeId);
      }
      return hasPermission('appointments.view_all') || hasPermission('appointments.view_self');
    }
    if (path.startsWith('/calendar')) return hasPermission('appointments.view_all') || hasPermission('appointments.view_self');
    if (path.startsWith('/customers')) {
      final parts = path.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.length == 2 && parts[1] == 'new') return hasPermission('customers.create');
      if (parts.contains('edit')) return hasPermission('customers.edit');
      if (parts.length > 1) return hasPermission('customers.history');
      return hasPermission('customers.view');
    }
    if (path.startsWith('/services')) return hasPermission('services.manage');
    if (path.startsWith('/reports')) return hasPermission('finance.income.view');
    if (path.startsWith('/activity') || path.startsWith('/sms')) return hasPermission('settings.view');
    return true;
  }

  bool canOpenNavigation(String path) {
    if (path == '/dashboard') return currentAccessAccount.roleId == 'global_admin';
    if (path == '/my-leaves') return currentAccessAccount.roleId == 'staff' && hasPermission('employees.leave.request', employeeId: currentAccessAccount.employeeId);
    if (path == '/my-wallet') {
      final employeeId = currentAccessAccount.employeeId;
      return employeeId != null && hasPermission('finance.wallet.view', employeeId: employeeId);
    }
    if (path == '/appointments' || path == '/calendar') return hasPermission('appointments.view_all') || hasPermission('appointments.view_self');
    if (path == '/customers') return hasPermission('customers.view');
    if (path == '/services') return hasPermission('services.manage');
    if (path == '/employees') return hasPermission('employees.view_list');
    if (path == '/reports') return hasPermission('finance.income.view');
    if (path == '/activity' || path == '/sms') return hasPermission('settings.view');
    if (path == '/settings') return hasPermission('settings.view') || hasPermission('permissions.manage');
    return false;
  }

  AccessRole createAccessRole({required String name, required List<String> permissionIds}) {
    requirePermission('permissions.manage');
    throw StateError('در DateTime فقط دو نقش مدیر کل و پرسنل مجاز است.');
  }

  void updateAccessRole(String roleId, {required String name, required List<String> permissionIds}) {
    requirePermission('permissions.manage');
    throw StateError('نقش‌های سیستمی قابل تغییر نیستند؛ مجوز هر پرسنل را جداگانه مدیریت کنید.');
  }

  void resetAccessRole(String roleId) {
    requirePermission('permissions.manage');
    final defaults = {for (final role in AccessRole.defaults()) role.id: role};
    final original = defaults[roleId];
    if (original == null) throw StateError('نقش پیش‌فرض پیدا نشد.');
    final previous = _accessRoles[roleId];
    if (previous == null) throw StateError('نقش پیدا نشد.');
    if (previous.name == original.name && previous.permissionIds.toSet().difference(original.permissionIds.toSet()).isEmpty && original.permissionIds.toSet().difference(previous.permissionIds.toSet()).isEmpty) return;
    _accessRoles[roleId] = original;
    log(ActivityType.settingsChanged, 'بازنشانی نقش دسترسی', 'مجوزهای نقش «${previous.name}» به مقادیر پیش‌فرض بازنشانی شد.', entity: 'نقش دسترسی', entityId: roleId,
      undoAction: 'access_role_restore', undoData: {'id': previous.id, 'name': previous.name, 'permission_ids': previous.permissionIds, 'description': previous.description, 'is_system': previous.isSystem},
      operationType: 'access_role_reset', isReversible: true);
    _commit();
  }

  void assignEmployeeAccess({
    required String employeeId,
    required String roleId,
    Map<String, bool> overrides = const {},
    bool canViewOtherEmployees = false,
    bool canViewPersonalIncome = true,
  }) {
    requirePermission('permissions.manage');
    if (!_employees.any((employee) => employee.id == employeeId)) throw StateError('پرسنل پیدا نشد.');
    if (roleId != 'staff' || !_accessRoles.containsKey(roleId)) {
      throw StateError('برای حساب‌های پرسنلی فقط نقش «پرسنل» قابل اختصاص است.');
    }
    if (_accessAccounts.any((account) => account.employeeId == employeeId && account.roleId == 'global_admin')) {
      throw AccessDeniedException('حساب مدیر کل از مدیریت دسترسی پرسنل جدا است.');
    }
    final previous = _accessAssignments[employeeId];
    final nextOverrides = Map<String, bool>.fromEntries(overrides.entries.where((entry) => AccessPermission.ids.contains(entry.key)));
    if (previous != null && previous.roleId == roleId && previous.overrides.length == nextOverrides.length &&
        previous.overrides.entries.every((entry) => nextOverrides[entry.key] == entry.value) &&
        previous.canViewOtherEmployees == canViewOtherEmployees && previous.canViewPersonalIncome == canViewPersonalIncome) return;
    final matchingAccounts = _accessAccounts.where((account) => account.employeeId == employeeId).toList();
    final previousAccountRole = matchingAccounts.isEmpty ? (previous?.roleId ?? 'staff') : matchingAccounts.first.roleId;
    _accessAssignments[employeeId] = AccessAssignment(
      employeeId: employeeId, roleId: roleId,
      overrides: Map.unmodifiable(nextOverrides),
      canViewOtherEmployees: canViewOtherEmployees,
      canViewPersonalIncome: canViewPersonalIncome,
    );
    for (var index = 0; index < _accessAccounts.length; index++) {
      final account = _accessAccounts[index];
      if (account.employeeId == employeeId) _accessAccounts[index] = account.copyWith(roleId: roleId);
    }
    log(ActivityType.settingsChanged, 'تغییر نقش و دسترسی پرسنل', 'نقش و سطح دسترسی پرسنل ${employeeById(employeeId)?.fullName ?? employeeId} تغییر کرد.', entity: 'دسترسی پرسنل', entityId: employeeId,
      undoAction: 'access_assignment_restore', undoData: {
        'employee_id': employeeId, 'had_assignment': previous != null,
        'role_id': previous?.roleId, 'new_role_id': roleId,
        'overrides': previous?.overrides ?? const <String, bool>{},
        'can_view_other_employees': previous?.canViewOtherEmployees ?? false,
        'can_view_personal_income': previous?.canViewPersonalIncome ?? true,
        'account_role_id': previousAccountRole,
      }, operationType: 'access_assignment', isReversible: true);
    _commit();
  }

  void switchEmployeeAccessRole(String employeeId, String roleId) {
    requirePermission('permissions.manage');
    final current = _accessAssignments[employeeId];
    assignEmployeeAccess(
      employeeId: employeeId, roleId: roleId,
      overrides: current?.overrides ?? const {},
      canViewOtherEmployees: current?.canViewOtherEmployees ?? false,
      canViewPersonalIncome: current?.canViewPersonalIncome ?? true,
    );
  }

  // ---------------------------------------------------------------------------
  // نوبت‌ها
  // ---------------------------------------------------------------------------
  Appointment? appointmentById(String id) {
    for (final a in _appointments) {
      if (a.id == id && (_isGlobalAdmin || a.employeeId == _activeEmployeeId)) return a;
    }
    return null;
  }

  /// بررسی تداخل نوبت برای یک متخصص.
  Appointment? findConflict({
    required String employeeId,
    required DateTime startAt,
    required int durationMinutes,
    String? ignoreId,
  }) {
    for (final a in _appointments) {
      if (a.id == ignoreId) continue;
      if (a.status == AppointmentStatus.cancelled) continue;
      if (a.employeeId != employeeId) continue;
      final end = startAt.add(Duration(minutes: durationMinutes));
      if (a.startAt.isBefore(end) && startAt.isBefore(a.endAt)) return a;
    }
    return null;
  }

  void addAppointment(Appointment appointment, {String? actor}) {
    requirePermission('appointments.create');
    if (currentAccessAccount.roleId != 'global_admin' &&
        currentAccessAccount.employeeId != appointment.employeeId) {
      throw const AccessDeniedException('پرسنل فقط می‌تواند نوبت مربوط به خودش را ثبت کند.');
    }
    _appointments.add(appointment);
    log(
      ActivityType.appointmentCreated,
      'ثبت نوبت جدید',
      'نوبت ${appointment.serviceName} برای ${appointment.customerName} در ${appointment.jalali.long} ساعت ${appointment.startAt.hour.toString().padLeft(2, '0')}:${appointment.startAt.minute.toString().padLeft(2, '0')} ثبت شد.',
      actor: actor,
      entity: 'نوبت',
      entityId: appointment.id,
      undoAction: 'appointment_created',
      undoData: appointment.toJson(),
      operationType: 'appointment_create',
      isReversible: true,
    );
    _commit();
  }

  void updateAppointment(Appointment appointment, {String? actor}) {
    requirePermission('appointments.edit', employeeId: appointment.employeeId);
    final index = _appointments.indexWhere((a) => a.id == appointment.id);
    if (index == -1) return;
    final previous = _appointments[index];
    _appointments[index] = appointment.copyWith(updatedAt: DateTime.now());
    log(
      ActivityType.appointmentUpdated,
      'ویرایش نوبت',
      'نوبت ${appointment.customerName} به‌روزرسانی شد.',
      actor: actor,
      entity: 'نوبت',
      undoAction: 'appointment_restore',
      undoData: previous.toJson(),
      entityId: appointment.id,
      operationType: 'appointment_update',
      isReversible: true,
    );
    _commit();
  }

  void changeStatus(Appointment appointment, AppointmentStatus status, {String? reason, String? actor, String? operationType}) {
    final permissionId = status == AppointmentStatus.confirmed
        ? 'appointments.confirm'
        : status == AppointmentStatus.cancelled
            ? (operationType == 'appointment_reject' ? 'appointments.reject' : 'appointments.cancel')
            : status == AppointmentStatus.completed
                ? 'appointments.complete'
                : 'appointments.edit';
    requirePermission(permissionId, employeeId: appointment.employeeId);
    final index = _appointments.indexWhere((a) => a.id == appointment.id);
    if (index == -1) return;
    final previous = _appointments[index];
    if (previous.status == status && previous.cancelReason == reason) return;
    if (previous.status == AppointmentStatus.cancelled || previous.status == AppointmentStatus.completed) {
      throw StateError('وضعیت نهایی این نوبت قابل تغییر مجدد نیست؛ در صورت نیاز از تاریخچه عملیات بازگردانی کنید.');
    }
    _appointments[index] = previous.copyWith(status: status, cancelReason: reason, updatedAt: DateTime.now());
    final type = switch (status) {
      AppointmentStatus.cancelled => ActivityType.appointmentCancelled,
      AppointmentStatus.completed => ActivityType.appointmentCompleted,
      _ => ActivityType.appointmentUpdated,
    };
    log(
      type,
      operationType == 'appointment_reject' ? 'رد درخواست نوبت' : status == AppointmentStatus.cancelled ? 'لغو نوبت' : 'تغییر وضعیت نوبت',
      operationType == 'appointment_reject'
          ? 'درخواست نوبت ${appointment.customerName} رد شد.${reason != null ? ' دلیل: $reason' : ''}'
          : 'وضعیت نوبت ${appointment.customerName} به «${status.label}» تغییر کرد.${reason != null ? ' دلیل: $reason' : ''}',
      actor: actor,
      entity: 'نوبت',
      undoAction: status == AppointmentStatus.completed ? null : 'appointment_restore',
      undoData: status == AppointmentStatus.completed ? null : previous.toJson(),
      entityId: appointment.id,
      operationType: operationType ?? (status == AppointmentStatus.cancelled ? 'appointment_cancel' : 'appointment_status_change'),
      isReversible: status != AppointmentStatus.completed,
    );
    if (status == AppointmentStatus.completed) finalizeCompletedAppointment(appointment.id);
    _commit();
  }

  // حقوق و پورسانت پرسنل — دفتر مالی محلی و قابل ردیابی
  void savePayProfile(EmployeePayProfile profile) {
    requirePermission('employees.edit');
    if (!_employees.any((employee) => employee.id == profile.employeeId)) throw StateError('پرسنل مورد نظر پیدا نشد.');
    if (profile.monthlySalary < 0 || profile.generalRateBps < 0 || profile.generalRateBps > 10000) throw ArgumentError('حقوق یا درصد پورسانت معتبر نیست.');
    for (final rule in profile.rules) { if (rule.rateBps < 0 || rule.rateBps > 10000 || rule.fixedAmount < 0) throw ArgumentError('قانون پورسانت معتبر نیست.'); }
    final previous = _employeePayProfiles[profile.employeeId];
    if (previous != null && previous.toJson().toString() == profile.toJson().toString()) return;
    _employeePayProfiles[profile.employeeId] = profile;
    log(ActivityType.settingsChanged, 'تغییر قرارداد مالی پرسنل', 'قواعد حقوق و پورسانت ذخیره شد.', entity: 'امور مالی پرسنل', entityId: profile.employeeId,
      undoAction: 'pay_profile_restore',
      undoData: {'employee_id': profile.employeeId, 'had_profile': previous != null, 'profile': previous?.toJson()},
      operationType: 'financial_pay_profile_update', isReversible: true);
    _commit();
  }
  // حقوق ثابت، پاداش، کسورات، مساعده و اهداف عملکردی (کاملاً Mock/آفلاین).
  List<SalaryContract> salaryContractsFor(String employeeId) {
    requirePermission('finance.salary.view', employeeId: employeeId);
    return List.unmodifiable(_salaryContracts[employeeId] ?? const []);
  }

  void saveSalaryContract(SalaryContract contract) {
    requirePermission('employees.edit');
    if (!_employees.any((item) => item.id == contract.employeeId)) throw StateError('پرسنل پیدا نشد.');
    if (contract.monthlyBase < 0 || (contract.effectiveTo != null && contract.effectiveTo!.isBefore(contract.effectiveFrom))) {
      throw ArgumentError('مبلغ یا بازه اعتبار حقوق معتبر نیست.');
    }
    final history = _salaryContracts.putIfAbsent(contract.employeeId, () => []);
    history.add(contract);
    _notifyEmployee(contract.employeeId,EmployeeNoticeType.salaryChanged,'حقوق ثابت تغییر کرد.','قرارداد حقوق جدید با مبلغ ${contract.monthlyBase} ثبت شد.');
    log(ActivityType.settingsChanged, 'ثبت سابقه حقوق ثابت', 'قرارداد حقوق ثابت جدید ثبت شد.', entity: 'حقوق پرسنل', entityId: contract.id, operationType: 'financial_salary_contract_create', isReversible: false);
    _commit();
  }

  void addPayrollAdjustment(PayrollAdjustment adjustment) {
    requirePermission('finance.payment.create', employeeId: adjustment.employeeId);
    if (!_employees.any((item) => item.id == adjustment.employeeId)) throw StateError('پرسنل پیدا نشد.');
    if (adjustment.amount <= 0 || adjustment.description.trim().isEmpty || adjustment.createdBy.trim().isEmpty) {
      throw ArgumentError('مبلغ، دلیل و ثبت‌کننده الزامی است.');
    }
    if (_payrollAdjustments.any((item) => item.id == adjustment.id)) throw StateError('شناسه تکراری است.');
    _payrollAdjustments.add(adjustment);
    if (adjustment.status == PayrollRecordStatus.approved && adjustment.sourceWalletTransactionId == null) {
      final walletType = adjustment.isBonus
          ? EmployeeWalletTransactionType.bonus
          : (adjustment.deductionType == PayrollDeductionType.absence || adjustment.deductionType == PayrollDeductionType.lateness
              ? EmployeeWalletTransactionType.penalty
              : EmployeeWalletTransactionType.deduction);
      final walletAmount = adjustment.isBonus ? adjustment.amount : -adjustment.amount;
      final walletEntry = EmployeeWalletTransaction(
        id: nextId('wallet'), employeeId: adjustment.employeeId, createdAt: adjustment.date,
        amount: walletAmount, type: walletType, description: adjustment.description,
        idempotencyKey: 'payroll-adjustment-${adjustment.id}',
        referenceType: 'payroll_adjustment', referenceId: adjustment.id,
      );
      _employeeWalletTransactions.add(walletEntry);
      _payrollAdjustments[_payrollAdjustments.length - 1] = PayrollAdjustment(
        id: adjustment.id, employeeId: adjustment.employeeId, amount: adjustment.amount,
        date: adjustment.date, description: adjustment.description, createdBy: adjustment.createdBy,
        status: adjustment.status, bonusType: adjustment.bonusType, deductionType: adjustment.deductionType,
        relatedAdvanceId: adjustment.relatedAdvanceId, sourceWalletTransactionId: walletEntry.id,
      );
    }
    log(ActivityType.settingsChanged, 'ثبت آیتم حقوق', 'پاداش یا کسورات پرسنل ثبت شد.', entity: 'حقوق پرسنل', entityId: adjustment.id, operationType: 'financial_payroll_adjustment', isReversible: false);
    _commit();
  }

  void addPayrollAdvance(PayrollAdvance advance) {
    if (currentAccessAccount.roleId == 'staff' && currentAccessAccount.employeeId == advance.employeeId) {
      requirePermission('finance.advance.request', employeeId: advance.employeeId);
      if (advance.status != AdvanceStatus.requested) {
        throw const AccessDeniedException('پرسنل فقط می‌تواند درخواست مساعده ثبت کند.');
      }
    } else {
      requirePermission('finance.advance.create', employeeId: advance.employeeId);
    }
    if (!_employees.any((item) => item.id == advance.employeeId)) throw StateError('پرسنل پیدا نشد.');
    if (advance.amount <= 0 || advance.description.trim().isEmpty) throw ArgumentError('مبلغ و توضیحات مساعده الزامی است.');
    if (_payrollAdvances.any((item) => item.id == advance.id)) throw StateError('شناسه مساعده تکراری است.');
    var savedAdvance = advance;
    if (advance.status == AdvanceStatus.paid && advance.sourceWalletTransactionId == null) {
      final walletEntry = EmployeeWalletTransaction(
        id: nextId('wallet'), employeeId: advance.employeeId, createdAt: advance.paidAt ?? DateTime.now(),
        amount: -advance.amount, type: EmployeeWalletTransactionType.advance,
        description: advance.description, idempotencyKey: 'payroll-advance-${advance.id}',
        referenceType: 'payroll_advance', referenceId: advance.id,
      );
      _employeeWalletTransactions.add(walletEntry);
      savedAdvance = PayrollAdvance(
        id: advance.id, employeeId: advance.employeeId, amount: advance.amount,
        requestedAt: advance.requestedAt, description: advance.description, status: advance.status,
        paidAt: advance.paidAt, deductedAmount: advance.deductedAmount,
        sourceWalletTransactionId: walletEntry.id,
      );
    }
    _payrollAdvances.add(savedAdvance);
    log(ActivityType.settingsChanged, 'ثبت مساعده پرسنل', 'مساعده برای پرسنل ثبت شد.', entity: 'حقوق پرسنل', entityId: savedAdvance.id, operationType: 'financial_payroll_advance', isReversible: false);
    _commit();
  }

  void reviewPayrollAdvanceRequest(String requestId, AdvanceStatus status) {
    requirePermission('finance.advance.create');
    if (status != AdvanceStatus.approved && status != AdvanceStatus.rejected) {
      throw ArgumentError('وضعیت بررسی مساعده معتبر نیست.');
    }
    final index = _payrollAdvances.indexWhere((item) => item.id == requestId);
    if (index < 0) throw StateError('درخواست مساعده پیدا نشد.');
    final current = _payrollAdvances[index];
    if (current.status != AdvanceStatus.requested) throw StateError('این درخواست قبلاً بررسی شده است.');
    _payrollAdvances[index] = PayrollAdvance(
      id: current.id,
      employeeId: current.employeeId,
      amount: current.amount,
      requestedAt: current.requestedAt,
      description: current.description,
      status: status,
      paidAt: current.paidAt,
      deductedAmount: current.deductedAmount,
      sourceWalletTransactionId: current.sourceWalletTransactionId,
    );
    log(ActivityType.settingsChanged, 'بررسی درخواست مساعده',
      'درخواست مساعده ${current.amount} تومان ${status == AdvanceStatus.approved ? 'تأیید' : 'رد'} شد.',
      entity: 'درخواست مساعده', entityId: requestId, operationType: 'payroll_advance_request_review');
    _commit();
  }

  void addPerformanceTarget(EmployeePerformanceTarget target) {
    requirePermission('employees.edit');
    if (!_employees.any((item) => item.id == target.employeeId)) throw StateError('پرسنل پیدا نشد.');
    if (target.targetValue <= 0 || target.periodEnd.isBefore(target.periodStart)) throw ArgumentError('هدف یا بازه آن معتبر نیست.');
    _performanceTargets.removeWhere((item) => item.employeeId == target.employeeId && item.type == target.type && item.serviceId == target.serviceId && item.periodStart == target.periodStart);
    _performanceTargets.add(target);
    _commit();
  }

  PayrollCalculation payrollFor(String employeeId, {DateTime? at}) {
    requirePermission('finance.salary.view', employeeId: employeeId);
    final date = at ?? DateTime.now();
    final contracts = _salaryContracts[employeeId] ?? const <SalaryContract>[];
    SalaryContract? contract;
    for (final item in contracts) {
      if (item.appliesAt(date) && (contract == null || item.effectiveFrom.isAfter(contract.effectiveFrom))) contract = item;
    }
    final monthFinance = _employeeFinanceEntries.where((entry) =>
      entry.employeeId == employeeId &&
      (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund) &&
      entry.createdAt.year == date.year && entry.createdAt.month == date.month);
    final commission = monthFinance.where((entry) => entry.type == FinanceEntryType.commission)
      .fold<int>(0, (sum, entry) => sum + entry.commissionAmount);
    final commissionRefunds = monthFinance.where((entry) => entry.type == FinanceEntryType.refund)
      .fold<int>(0, (sum, entry) => sum + entry.commissionAmount.abs());
    final adjustments = _payrollAdjustments.where((item) =>
      item.employeeId == employeeId && item.date.year == date.year && item.date.month == date.month);
    final advances = _payrollAdvances.where((item) =>
      item.employeeId == employeeId && item.requestedAt.year == date.year && item.requestedAt.month == date.month);
    final paid = _employeeWalletTransactions.where((item) =>
      item.employeeId == employeeId && item.type == EmployeeWalletTransactionType.salaryPayment &&
      item.createdAt.year == date.year && item.createdAt.month == date.month)
      .fold<int>(0, (sum, item) => sum + item.amount.abs());
    final attendanceStart = DateTime(date.year, date.month, 1);
    final attendanceEnd = DateTime(date.year, date.month + 1, 1).subtract(const Duration(microseconds: 1));
    final attendanceAdjustment = attendancePayrollPreview(employeeId, from: attendanceStart, to: attendanceEnd).netAdjustment;
    return EmployeePayrollCalculator.calculate(contract: contract, at: date,
      approvedCommission: commission, adjustments: adjustments, advances: advances,
      previousPayments: paid, commissionRefunds: commissionRefunds,
      attendanceAdjustment: attendanceAdjustment);
  }

  void _seedPayrollData() {
    final now = DateTime.now();
    void addSeedAdjustment(PayrollAdjustment adjustment) {
      final walletType = adjustment.isBonus ? EmployeeWalletTransactionType.bonus : EmployeeWalletTransactionType.deduction;
      final walletEntry = EmployeeWalletTransaction(
        id: nextId('wallet'), employeeId: adjustment.employeeId, createdAt: adjustment.date,
        amount: adjustment.isBonus ? adjustment.amount : -adjustment.amount,
        type: walletType, description: adjustment.description,
        idempotencyKey: 'payroll-adjustment-${adjustment.id}',
        referenceType: 'payroll_adjustment', referenceId: adjustment.id,
      );
      _employeeWalletTransactions.add(walletEntry);
      _payrollAdjustments.add(PayrollAdjustment(
        id: adjustment.id, employeeId: adjustment.employeeId, amount: adjustment.amount,
        date: adjustment.date, description: adjustment.description, createdBy: adjustment.createdBy,
        status: adjustment.status, bonusType: adjustment.bonusType, deductionType: adjustment.deductionType,
        sourceWalletTransactionId: walletEntry.id,
      ));
    }
    for (var index = 0; index < _employees.length && index < 5; index++) {
      final employee = _employees[index];
      _salaryContracts[employee.id] = [SalaryContract(
        id: 'salary-seed-${employee.id}', employeeId: employee.id,
        monthlyBase: index == 0 ? 18000000 : 8000000 + index * 1000000,
        effectiveFrom: DateTime(now.year, now.month, 1), period: SalaryPeriod.monthly,
      )];
      addSeedAdjustment(PayrollAdjustment(
        id: 'bonus-seed-${employee.id}', employeeId: employee.id, amount: 500000 + index * 100000,
        date: now, description: 'پاداش عملکرد آزمایشی', createdBy: 'مدیر سیستم',
        status: PayrollRecordStatus.approved, bonusType: PayrollBonusType.performance,
      ));
      if (index.isOdd) {
        addSeedAdjustment(PayrollAdjustment(
          id: 'deduction-seed-${employee.id}', employeeId: employee.id, amount: 150000,
          date: now, description: 'کسورات نمونه', createdBy: 'مدیر سیستم',
          status: PayrollRecordStatus.approved, deductionType: PayrollDeductionType.agreed,
        ));
      }
      _performanceTargets.add(EmployeePerformanceTarget(
        id: 'target-seed-${employee.id}', employeeId: employee.id,
        type: PerformanceTargetType.monthlyRevenue, targetValue: 30000000,
        periodStart: DateTime(now.year, now.month, 1),
        periodEnd: DateTime(now.year, now.month + 1, 0),
      ));
    }
  }

  List<EmployeeFinanceEntry> financeEntriesFor(String employeeId) {
    requirePermission('finance.commission.view', employeeId: employeeId);
    return _employeeFinanceEntries.where((entry) => entry.employeeId == employeeId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  bool hasCommissionForAppointment(String appointmentId) => _employeeFinanceEntries.any((entry) => entry.appointmentId == appointmentId && entry.type == FinanceEntryType.commission);
  bool finalizeCompletedAppointment(String appointmentId, {int discountAmount = 0, int? finalPaidAmount}) {
    requirePermission('appointments.complete');
    final appointment = appointmentById(appointmentId);
    if (appointment == null || appointment.status != AppointmentStatus.completed || hasCommissionForAppointment(appointmentId)) return false;
    final profile = payProfileFor(appointment.employeeId);
    final grossTotal = appointment.price.round();
    final receivedTotal = finalPaidAmount ?? (grossTotal - discountAmount);
    if (grossTotal < 0 || discountAmount < 0 || discountAmount > grossTotal ||
        receivedTotal < 0 || receivedTotal > grossTotal - discountAmount) {
      throw ArgumentError('مبلغ خدمت، تخفیف یا دریافتی معتبر نیست.');
    }
    final ids = appointment.serviceIds.isEmpty ? <String>[''] : appointment.serviceIds;
    final snapshots = appointment.serviceSnapshots;
    final grossParts = <int>[];
    for (var index = 0; index < ids.length; index++) {
      Map<String, dynamic>? item;
      for (final snapshot in snapshots) {
        if (snapshot['service_id'] == ids[index]) { item = snapshot; break; }
      }
      final savedPrice = (item?['price'] as num?)?.toInt();
      grossParts.add(savedPrice ?? (grossTotal ~/ ids.length + (index == 0 ? grossTotal % ids.length : 0)));
    }
    final snapshotGrossTotal = grossParts.fold<int>(0, (sum, amount) => sum + amount);
    var allocatedDiscount = 0;
    var allocatedReceived = 0;
    for (var index = 0; index < ids.length; index++) {
      final serviceId = ids[index];
      final gross = grossParts[index];
      final isLast = index == ids.length - 1;
      final discount = isLast
          ? discountAmount - allocatedDiscount
          : (snapshotGrossTotal == 0 ? discountAmount ~/ ids.length : (discountAmount * gross) ~/ snapshotGrossTotal);
      final received = isLast
          ? receivedTotal - allocatedReceived
          : (snapshotGrossTotal == 0 ? receivedTotal ~/ ids.length : (receivedTotal * gross) ~/ snapshotGrossTotal);
      allocatedDiscount += discount;
      allocatedReceived += received;
      final service = serviceById(serviceId);
      final rule = profile.ruleFor(serviceId: serviceId, category: service?.category ?? '', date: appointment.startAt);
      Map<String, dynamic>? snapshot;
      for (final item in appointment.serviceSnapshots) {
        if (item['service_id'] == serviceId) { snapshot = item; break; }
      }
      final hasServiceCommissionOverride = snapshot?['service_commission_override'] == true;
      final rate = (snapshot?['commission_rate_bps'] as num?)?.toInt() ?? rule?.rateBps ?? profile.generalRateBps;
      final fixed = (snapshot?['fixed_commission_amount'] as num?)?.toInt() ?? rule?.fixedAmount ?? 0;
      final basisKey = snapshot?['commission_basis'] as String?;
      var basis = profile.basis;
      for (final item in CommissionBasis.values) {
        if (item.name == basisKey) { basis = item; break; }
      }
      final base = CommissionCalculator.base(basis: basis, grossAmount: gross, discountAmount: discount, receivedAmount: received);
      final calculatedCommission = hasServiceCommissionOverride
          ? CommissionCalculator.commission(baseAmount: base, rateBps: rate, fixedAmount: fixed)
          : switch (profile.method) {
              EmployeePaymentMethod.fixedMonthly => 0,
              EmployeePaymentMethod.fixedPerService => fixed,
              _ => CommissionCalculator.commission(baseAmount: base, rateBps: rate, fixedAmount: fixed),
            };
      final commission = calculatedCommission.clamp(0, received).toInt();
      final financeEntry = EmployeeFinanceEntry(id: nextId('finance'), employeeId: appointment.employeeId, appointmentId: appointment.id, serviceId: serviceId, createdAt: DateTime.now(), type: FinanceEntryType.commission, methodSnapshot: profile.method.name, basisSnapshot: profile.basis.name, grossAmount: gross, discountAmount: discount, receivedAmount: received, calculationBase: base, rateBps: rate, fixedAmount: fixed, commissionAmount: commission, companyShare: received - commission);
      _employeeFinanceEntries.add(financeEntry);
      _mirrorFinanceEntryToWallet(financeEntry);
    }
    log(ActivityType.appointmentCompleted, 'ثبت پورسانت نوبت', 'سند پورسانت برای نوبت تکمیل‌شده ایجاد شد.', entity: 'دفتر مالی پرسنل');
    _commit();
    return true;
  }
  bool recordCommissionRefund(String entryId, int refundAmount) {
    requirePermission('finance.payment.create');
    if (refundAmount <= 0) throw ArgumentError('مبلغ برگشت باید بیشتر از صفر باشد.');
    EmployeeFinanceEntry? original;
    for (final entry in _employeeFinanceEntries) { if (entry.id == entryId && entry.type == FinanceEntryType.commission) { original = entry; break; } }
    if (original == null) return false;
    final refunded = _employeeFinanceEntries.where((entry) => entry.type == FinanceEntryType.refund && entry.reversesEntryId == entryId).fold<int>(0, (sum, entry) => sum - entry.receivedAmount);
    if (refunded + refundAmount > original.receivedAmount) throw ArgumentError('مبلغ برگشت از دریافتی این خدمت بیشتر است.');
    final commissionRefund = original.receivedAmount == 0 ? 0 : (original.commissionAmount * refundAmount + original.receivedAmount ~/ 2) ~/ original.receivedAmount;
    final refundEntry = EmployeeFinanceEntry(id: nextId('finance'), employeeId: original.employeeId, appointmentId: original.appointmentId, serviceId: original.serviceId, createdAt: DateTime.now(), type: FinanceEntryType.refund, methodSnapshot: original.methodSnapshot, basisSnapshot: original.basisSnapshot, grossAmount: -refundAmount, discountAmount: 0, receivedAmount: -refundAmount, calculationBase: -refundAmount, rateBps: original.rateBps, fixedAmount: 0, commissionAmount: -commissionRefund, companyShare: -(refundAmount - commissionRefund), reversesEntryId: entryId);
    _employeeFinanceEntries.add(refundEntry);
    _mirrorFinanceEntryToWallet(refundEntry);
    log(ActivityType.settingsChanged, 'ثبت برگشت وجه پورسانت', 'سند اصلاحی برگشت وجه ثبت شد.', entity: 'دفتر مالی پرسنل', entityId: refundEntry.id, operationType: 'financial_commission_refund', isReversible: false);
    _commit();
    return true;
  }
  void _createCommissionEntries(Appointment appointment) {
    if (appointment.status != AppointmentStatus.completed || hasCommissionForAppointment(appointment.id)) return;
    // Seeded completed appointments use the same calculation path and snapshots as UI completions.
    finalizeCompletedAppointment(appointment.id);
  }

  // کیف پول و دفتر کل مالی پرسنل — تمام ارقام از تراکنش‌های ثبت‌شده محاسبه می‌شوند.
  List<EmployeeWalletTransaction> walletTransactionsFor(String employeeId, {DateTime? from, DateTime? to}) {
    if (!canViewEmployeeIncome(employeeId)) throw const AccessDeniedException('اجازه مشاهده اطلاعات درآمد این پرسنل را ندارید.');
    final canViewSalary = hasPermission('finance.salary.view', employeeId: employeeId);
    final canViewCommission = hasPermission('finance.commission.view', employeeId: employeeId);
    return _employeeWalletTransactions.where((entry) {
        if (entry.employeeId != employeeId) return false;
        if (from != null && entry.createdAt.isBefore(from)) return false;
        if (to != null && entry.createdAt.isAfter(to)) return false;
        // حقوق و پورسانت دو سطح دسترسی مستقل‌اند؛ اسناد برگشت متصل به پورسانت
        // نیز بدون مجوز پورسانت نباید از مسیر کیف پول قابل مشاهده باشند.
        if (!canViewCommission &&
            (entry.type == EmployeeWalletTransactionType.commission || entry.sourceFinanceEntryId != null)) return false;
        if (!canViewSalary &&
            entry.type != EmployeeWalletTransactionType.commission &&
            !(entry.type == EmployeeWalletTransactionType.refund && canViewCommission)) return false;
        return true;
      }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<EmployeeWalletSettlement> walletSettlementsFor(String employeeId) {
    requirePermission('finance.salary.view', employeeId: employeeId);
    requirePermission('finance.settlement.view', employeeId: employeeId);
    return _employeeWalletSettlements.where((entry) => entry.employeeId == employeeId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  EmployeeWalletSummary walletSummaryFor(String employeeId) =>
      EmployeeWalletSummary.fromTransactions(walletTransactionsFor(employeeId));

  EmployeeWallet walletFor(String employeeId, {DateTime? at}) =>
      EmployeeWallet.fromTransactions(employeeId, walletTransactionsFor(employeeId), calculatedAt: at);

  List<EmployeeWalletPayment> walletPaymentsFor(String employeeId) {
    requirePermission('finance.salary.view', employeeId: employeeId);
    requirePermission('finance.settlement.view', employeeId: employeeId);
    return _employeeWalletPayments.where((item) => item.employeeId == employeeId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<EmployeeWallet> walletDebtAndReceivableReport() {
    requirePermission('finance.salary.view');
    return _employees.where((employee) => canViewEmployeeIncome(employee.id))
        .map((employee) => walletFor(employee.id)).toList()
      ..sort((a, b) => b.finalBalance.compareTo(a.finalBalance));
  }

  int walletBalanceFor(String employeeId) => walletSummaryFor(employeeId).balance;

  /// ثبت حقوق پایه و اثر حضور و غیاب در دفتر کل، بدون تکرار برای ماه جاری.
  int accruePayrollBaseToWallet(String employeeId, {DateTime? at}) {
    requirePermission('finance.payment.create', employeeId: employeeId);
    final date = at ?? DateTime.now();
    final payroll = payrollFor(employeeId, at: date);
    String? activeContractId;
    for (final contract in _salaryContracts[employeeId] ?? const <SalaryContract>[]) {
      if (contract.appliesAt(date) &&
          (activeContractId == null ||
            contract.effectiveFrom.isAfter((_salaryContracts[employeeId]!
              .firstWhere((item) => item.id == activeContractId)).effectiveFrom))) {
        activeContractId = contract.id;
      }
    }
    final monthStart = DateTime(date.year, date.month, 1);
    var posted = 0;
    final hasSalaryEntry = _employeeWalletTransactions.any((entry) =>
      entry.employeeId == employeeId &&
      entry.type == EmployeeWalletTransactionType.fixedSalary &&
      entry.createdAt.year == date.year && entry.createdAt.month == date.month);
    if (!hasSalaryEntry && payroll.baseSalary > 0) {
      addWalletTransaction(
        employeeId: employeeId,
        amount: payroll.baseSalary,
        type: EmployeeWalletTransactionType.fixedSalary,
        description: 'حقوق پایه ${date.year}/${date.month.toString().padLeft(2, '0')}',
        createdAt: monthStart,
        idempotencyKey: 'payroll-base-$employeeId-${date.year}-${date.month}',
        referenceType: 'salary_contract',
        referenceId: '${activeContractId ?? 'salary-$employeeId'}:${date.year}-${date.month}',
      );
      posted += 1;
    }
    final attendanceKey = 'payroll-attendance-$employeeId-${date.year}-${date.month}';
    if (payroll.attendanceAdjustment != 0 &&
        !_employeeWalletTransactions.any((entry) => entry.idempotencyKey == attendanceKey)) {
      addWalletTransaction(
        employeeId: employeeId,
        amount: payroll.attendanceAdjustment,
        type: EmployeeWalletTransactionType.adjustment,
        description: 'اثر قانون حضور و غیاب ${date.year}/${date.month.toString().padLeft(2, '0')}',
        createdAt: monthStart,
        idempotencyKey: attendanceKey, referenceType: 'attendance_payroll', referenceId: attendanceKey,
      );
      posted += 1;
    }
    return posted;
  }

  int walletPeriodDue(String employeeId, DateTime periodStart, DateTime periodEnd) {
    requirePermission('finance.salary.view', employeeId: employeeId);
    if (periodEnd.isBefore(periodStart)) throw ArgumentError('بازه تسویه معتبر نیست.');
    final accrued = _employeeWalletTransactions.where((entry) =>
      entry.employeeId == employeeId &&
      entry.status == EmployeeWalletTransactionStatus.posted &&
      entry.type != EmployeeWalletTransactionType.salaryPayment &&
      !entry.createdAt.isBefore(periodStart) &&
      !entry.createdAt.isAfter(periodEnd),
    ).fold<int>(0, (sum, entry) => sum + entry.amount);
    final alreadyPaid = _employeeWalletSettlements.where((entry) =>
      entry.employeeId == employeeId &&
      entry.periodStart == periodStart &&
      entry.periodEnd == periodEnd,
    ).fold<int>(0, (sum, entry) => sum + entry.paidAmount);
    return accrued - alreadyPaid;
  }

  EmployeeWalletTransaction addWalletTransaction({
    required String employeeId,
    required int amount,
    required EmployeeWalletTransactionType type,
    required String description,
    DateTime? createdAt,
    String? idempotencyKey,
    String? referenceType,
    String? referenceId,
  }) {
    requirePermission(type == EmployeeWalletTransactionType.advance ? 'finance.advance.create' : 'finance.payment.create', employeeId: employeeId);
    if (!_employees.any((employee) => employee.id == employeeId)) throw StateError('پرسنل مورد نظر پیدا نشد.');
    if (amount == 0) throw ArgumentError('مبلغ تراکنش نمی‌تواند صفر باشد.');
    if (type == EmployeeWalletTransactionType.commission || type == EmployeeWalletTransactionType.refund || type == EmployeeWalletTransactionType.salaryPayment) {
      throw ArgumentError('پورسانت، بازپرداخت و پرداخت حقوق باید از سند مرجع تخصصی ایجاد شوند.');
    }
    if (type == EmployeeWalletTransactionType.fixedSalary && idempotencyKey?.startsWith('payroll-base-') != true) {
      throw ArgumentError('حقوق ثابت فقط از قرارداد حقوق و دوره محاسباتی ثبت می‌شود.');
    }
    if (description.trim().isEmpty) throw ArgumentError('توضیحات تراکنش الزامی است.');
    final creditOnly = type == EmployeeWalletTransactionType.fixedSalary || type == EmployeeWalletTransactionType.bonus || type == EmployeeWalletTransactionType.commission;
    final debitOnly = type == EmployeeWalletTransactionType.advance || type == EmployeeWalletTransactionType.penalty || type == EmployeeWalletTransactionType.deduction || type == EmployeeWalletTransactionType.refund || type == EmployeeWalletTransactionType.salaryPayment;
    if ((creditOnly && amount < 0) || (debitOnly && amount > 0)) throw ArgumentError('جهت مبلغ با نوع تراکنش هم‌خوانی ندارد.');
    if (idempotencyKey != null && (idempotencyKey.trim().isEmpty || _employeeWalletTransactions.any((entry) => entry.idempotencyKey == idempotencyKey))) {
      throw StateError('این عملیات مالی قبلاً ثبت شده است.');
    }
    final walletId = nextId('wallet');
    final defaultReferenceType = switch (type) {
      EmployeeWalletTransactionType.bonus ||
      EmployeeWalletTransactionType.penalty ||
      EmployeeWalletTransactionType.deduction => 'payroll_adjustment',
      EmployeeWalletTransactionType.advance => 'payroll_advance',
      EmployeeWalletTransactionType.adjustment => 'manual_wallet_adjustment',
      _ => 'wallet_source',
    };
    final defaultReferenceId = switch (type) {
      EmployeeWalletTransactionType.bonus ||
      EmployeeWalletTransactionType.penalty ||
      EmployeeWalletTransactionType.deduction => 'payroll-$walletId',
      EmployeeWalletTransactionType.advance => 'advance-$walletId',
      _ => walletId,
    };
    final entry = EmployeeWalletTransaction(
      id: walletId,
      employeeId: employeeId,
      createdAt: createdAt ?? DateTime.now(),
      amount: amount,
      type: type,
      description: description.trim(),
      idempotencyKey: idempotencyKey,
      referenceType: referenceType ?? defaultReferenceType,
      referenceId: referenceId ?? defaultReferenceId,
    );
    _employeeWalletTransactions.add(entry);
    if (type == EmployeeWalletTransactionType.bonus) {
      _payrollAdjustments.add(PayrollAdjustment(
        id: 'payroll-${entry.id}', employeeId: employeeId, amount: amount,
        date: entry.createdAt, description: entry.description, createdBy: currentAccessAccount.name,
        status: PayrollRecordStatus.approved, bonusType: PayrollBonusType.manual,
        sourceWalletTransactionId: entry.id,
      ));
    } else if (type == EmployeeWalletTransactionType.penalty || type == EmployeeWalletTransactionType.deduction) {
      _payrollAdjustments.add(PayrollAdjustment(
        id: 'payroll-${entry.id}', employeeId: employeeId, amount: amount.abs(),
        date: entry.createdAt, description: entry.description, createdBy: currentAccessAccount.name,
        status: PayrollRecordStatus.approved, deductionType: PayrollDeductionType.agreed,
        sourceWalletTransactionId: entry.id,
      ));
    } else if (type == EmployeeWalletTransactionType.advance) {
      _payrollAdvances.add(PayrollAdvance(
        id: 'advance-${entry.id}', employeeId: employeeId, amount: amount.abs(),
        requestedAt: entry.createdAt, paidAt: entry.createdAt, description: entry.description,
        status: AdvanceStatus.paid, sourceWalletTransactionId: entry.id,
      ));
    }
    if (type == EmployeeWalletTransactionType.salaryPayment) _notifyEmployee(employeeId,EmployeeNoticeType.paymentRecorded,'پرداخت ثبت شد.','پرداخت حقوق برای شما ثبت شد.');
    log(ActivityType.settingsChanged, 'ثبت تراکنش کیف پول', 'تراکنش «${type.label}» برای پرسنل ثبت شد.', entity: 'کیف پول پرسنل', entityId: entry.id, operationType: 'financial_wallet_entry', isReversible: false, idempotencyKey: idempotencyKey);
    _commit();
    return entry;
  }

  /// اصلاح سند فقط با دو سند تازه (معکوس و اصلاحیه) انجام می‌شود؛ سند اصلی دست‌نخورده می‌ماند.
  List<EmployeeWalletTransaction> correctWalletTransaction({
    required String transactionId,
    required int correctedAmount,
    required String description,
  }) {
    requirePermission('finance.payment.create');
    final matches = _employeeWalletTransactions.where((entry) => entry.id == transactionId).toList();
    if (matches.isEmpty || matches.first.status != EmployeeWalletTransactionStatus.posted) throw StateError('تراکنش قابل اصلاح پیدا نشد.');
    final original = matches.first;
    if (_employeeWalletTransactions.any((entry) => entry.reversalOfId == transactionId)) throw StateError('این تراکنش قبلاً اصلاح شده است.');
    if (correctedAmount == 0 || description.trim().isEmpty) throw ArgumentError('مبلغ و توضیحات اصلاحیه معتبر نیست.');
    // سندهای مشتق از قرارداد، پورسانت، برگشت وجه، پرداخت حقوق و قانون حضور
    // باید از مسیر تخصصی خود اصلاح شوند تا دفتر کل و منبع محاسبه از هم جدا نشوند.
    if (original.sourceFinanceEntryId != null ||
        original.type == EmployeeWalletTransactionType.fixedSalary ||
        original.type == EmployeeWalletTransactionType.commission ||
        original.type == EmployeeWalletTransactionType.refund ||
        original.type == EmployeeWalletTransactionType.salaryPayment ||
        (original.type == EmployeeWalletTransactionType.adjustment &&
          original.idempotencyKey?.startsWith('payroll-attendance-') == true)) {
      throw StateError('این سند به منبع محاسباتی متصل است؛ اصلاح آن باید از مسیر تخصصی همان منبع انجام شود.');
    }
    if ((original.amount > 0) != (correctedAmount > 0) &&
        original.type != EmployeeWalletTransactionType.adjustment) {
      throw ArgumentError('جهت مبلغ اصلاحی باید با نوع سند اصلی یکسان باشد.');
    }
    final reversal = EmployeeWalletTransaction(
      id: nextId('wallet'),
      employeeId: original.employeeId,
      createdAt: DateTime.now(),
      amount: -original.amount,
      type: EmployeeWalletTransactionType.adjustment,
      description: 'سند معکوس تراکنش ${original.id}',
      reversalOfId: original.id,
      referenceType: 'wallet_transaction_correction', referenceId: original.id,
    );
    final correction = EmployeeWalletTransaction(
      id: nextId('wallet'),
      employeeId: original.employeeId,
      createdAt: DateTime.now(),
      amount: correctedAmount,
      type: EmployeeWalletTransactionType.adjustment,
      description: description.trim(),
      reversalOfId: original.id,
      referenceType: 'wallet_transaction_correction', referenceId: original.id,
    );
    _employeeWalletTransactions.addAll([reversal, correction]);
    log(ActivityType.settingsChanged, 'اصلاح سند مالی', 'سند ${original.id} با ثبت معکوس ${reversal.id} و اصلاحیه ${correction.id} اصلاح شد.',
      entity: 'کیف پول پرسنل', entityId: original.id, operationType: 'financial_correction', isReversible: false);
    // به‌روزرسانی مقدار سند منبع حقوق/مساعده با حفظ شناسه و تاریخچه اسناد کیف پول.
    final adjustmentIndex = _payrollAdjustments.indexWhere((item) => item.sourceWalletTransactionId == original.id);
    if (adjustmentIndex >= 0) {
      final item = _payrollAdjustments[adjustmentIndex];
      _payrollAdjustments[adjustmentIndex] = PayrollAdjustment(
        id: item.id, employeeId: item.employeeId, amount: correctedAmount.abs(),
        date: item.date, description: item.description, createdBy: item.createdBy,
        status: item.status, bonusType: item.bonusType, deductionType: item.deductionType,
        relatedAdvanceId: item.relatedAdvanceId, sourceWalletTransactionId: item.sourceWalletTransactionId,
      );
    }
    final advanceIndex = _payrollAdvances.indexWhere((item) => item.sourceWalletTransactionId == original.id);
    if (advanceIndex >= 0) {
      final item = _payrollAdvances[advanceIndex];
      _payrollAdvances[advanceIndex] = PayrollAdvance(
        id: item.id, employeeId: item.employeeId, amount: correctedAmount.abs(),
        requestedAt: item.requestedAt, description: item.description, status: item.status,
        paidAt: item.paidAt, deductedAmount: item.deductedAmount.clamp(0, correctedAmount.abs()),
        sourceWalletTransactionId: item.sourceWalletTransactionId,
      );
    }
    _commit();
    return [reversal, correction];
  }

  List<EmployeeWalletSettlementRequest> walletSettlementRequestsFor(String employeeId) {
    if (currentAccessAccount.roleId != 'global_admin' &&
        currentAccessAccount.employeeId != employeeId) {
      throw const AccessDeniedException('فقط درخواست‌های تسویه شخصی قابل مشاهده است.');
    }
    return List.unmodifiable(_employeeWalletSettlementRequests.where((item) => item.employeeId == employeeId));
  }

  void requestWalletSettlement(EmployeeWalletSettlementRequest request) {
    requirePermission('finance.settlement.request', employeeId: request.employeeId);
    if (request.amount <= 0 || request.description.trim().isEmpty ||
        request.periodEnd.isBefore(request.periodStart)) {
      throw ArgumentError('مبلغ، توضیحات و بازه درخواست تسویه معتبر نیست.');
    }
    final availableBalance = walletTransactionsFor(request.employeeId)
        .where((item) => item.status == EmployeeWalletTransactionStatus.posted)
        .fold<int>(0, (sum, item) => sum + item.amount);
    if (request.amount > availableBalance) {
      throw ArgumentError('مبلغ درخواست از مانده قابل تسویه کیف پول بیشتر است.');
    }
    if (_employeeWalletSettlementRequests.any((item) =>
        item.employeeId == request.employeeId &&
        item.status == EmployeeWalletRequestStatus.pending &&
        !item.periodStart.isAfter(request.periodEnd) &&
        !request.periodStart.isAfter(item.periodEnd))) {
      throw StateError('برای این بازه یک درخواست تسویه در انتظار بررسی وجود دارد.');
    }
    _employeeWalletSettlementRequests.add(request);
    log(ActivityType.settingsChanged, 'درخواست تسویه پرسنل',
      'درخواست تسویه ${request.amount} تومان برای ${employeeById(request.employeeId)?.fullName ?? request.employeeId} ثبت شد.',
      entity: 'درخواست تسویه', entityId: request.id, operationType: 'wallet_settlement_request');
    _commit();
  }

  void reviewWalletSettlementRequest(String requestId, EmployeeWalletRequestStatus status) {
    requirePermission('finance.settlement.view');
    final index = _employeeWalletSettlementRequests.indexWhere((item) => item.id == requestId);
    if (index < 0) throw StateError('درخواست تسویه پیدا نشد.');
    final current = _employeeWalletSettlementRequests[index];
    if (current.status != EmployeeWalletRequestStatus.pending ||
        status == EmployeeWalletRequestStatus.pending) {
      throw StateError('وضعیت این درخواست قبلاً بررسی شده است.');
    }
    _employeeWalletSettlementRequests[index] = current.copyWith(
      status: status,
      reviewedAt: DateTime.now(),
      reviewedBy: currentAccessAccount.name,
    );
    log(ActivityType.settingsChanged, 'بررسی درخواست تسویه',
      'درخواست تسویه ${current.amount} تومان ${status == EmployeeWalletRequestStatus.approved ? 'تأیید' : 'رد'} شد.',
      entity: 'درخواست تسویه', entityId: requestId, operationType: 'wallet_settlement_request_review');
    _commit();
  }

  EmployeeWalletSettlement settleEmployeeWallet({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required EmployeeWalletPeriodType periodType,
    required int paidAmount,
    required String idempotencyKey,
    EmployeeWalletPaymentMethod method = EmployeeWalletPaymentMethod.bankTransfer,
    String description = 'پرداخت تسویه پرسنل',
  }) {
    requirePermission('finance.payment.create', employeeId: employeeId);
    requirePermission('finance.salary.view', employeeId: employeeId);
    if (!_employees.any((employee) => employee.id == employeeId)) throw StateError('پرسنل مورد نظر پیدا نشد.');
    if (periodEnd.isBefore(periodStart)) throw ArgumentError('بازه تسویه معتبر نیست.');
    if (paidAmount <= 0) throw ArgumentError('مبلغ پرداخت باید بیشتر از صفر باشد.');
    if (idempotencyKey.trim().isEmpty ||
        _employeeWalletTransactions.any((entry) => entry.idempotencyKey == idempotencyKey) ||
        _employeeWalletPayments.any((entry) => entry.idempotencyKey == idempotencyKey) ||
        _employeeWalletSettlements.any((entry) => entry.idempotencyKey == idempotencyKey)) {
      throw StateError('این پرداخت قبلاً ثبت شده است.');
    }
    final due = walletPeriodDue(employeeId, periodStart, periodEnd);
    if (due <= 0) throw StateError('در این بازه مبلغ قابل پرداختی وجود ندارد.');
    if (paidAmount > due) throw ArgumentError('مبلغ پرداخت از مانده قابل تسویه بیشتر است.');
    final settlementId = nextId('settlement');
    final remaining = due - paidAmount;
    final now = DateTime.now();
    final settlement = EmployeeWalletSettlement(
      id: settlementId,
      employeeId: employeeId,
      periodType: periodType,
      periodStart: periodStart,
      periodEnd: periodEnd,
      dueAmount: due,
      paidAmount: paidAmount,
      remainingAfter: remaining,
      createdAt: now,
      status: remaining == 0 ? EmployeeWalletSettlementStatus.completed : EmployeeWalletSettlementStatus.partial,
      receiptNumber: 'RC-${now.microsecondsSinceEpoch}',
      idempotencyKey: idempotencyKey,
    );
    final paymentId = nextId('wallet-payment');
    final walletTransactionId = nextId('wallet');
    _employeeWalletSettlements.add(settlement);
    _employeeWalletTransactions.add(EmployeeWalletTransaction(
      id: walletTransactionId,
      employeeId: employeeId,
      createdAt: now,
      amount: -paidAmount,
      type: EmployeeWalletTransactionType.salaryPayment,
      description: description.trim().isEmpty ? 'پرداخت تسویه ${settlement.receiptNumber}' : description.trim(),
      settlementId: settlementId,
      paymentId: paymentId,
      referenceType: 'wallet_settlement', referenceId: settlementId,
      idempotencyKey: idempotencyKey,
    ));
    _employeeWalletPayments.add(EmployeeWalletPayment(
      id: paymentId, employeeId: employeeId, settlementId: settlementId,
      walletTransactionId: walletTransactionId, createdAt: now, amount: paidAmount,
      method: method, receiptNumber: settlement.receiptNumber,
      idempotencyKey: idempotencyKey, description: description.trim(),
    ));
    _notifyEmployee(employeeId, EmployeeNoticeType.paymentRecorded, 'پرداخت ثبت شد', 'پرداخت ${paidAmount} تومان برای شما ثبت شد. رسید: ${settlement.receiptNumber}');
    log(ActivityType.settingsChanged, 'ثبت تسویه پرسنل', 'پرداخت ${paidAmount} تومان برای تسویه پرسنل ثبت شد.', entity: 'تسویه حساب', entityId: settlementId, operationType: 'financial_wallet_settlement', isReversible: false, idempotencyKey: idempotencyKey);
    _commit();
    return settlement;
  }

  void _mirrorFinanceEntryToWallet(EmployeeFinanceEntry entry) {
    if (entry.commissionAmount == 0 ||
        _employeeWalletTransactions.any((walletEntry) => walletEntry.sourceFinanceEntryId == entry.id)) return;
    _employeeWalletTransactions.add(EmployeeWalletTransaction(
      id: nextId('wallet'),
      employeeId: entry.employeeId,
      createdAt: entry.createdAt,
      amount: entry.commissionAmount,
      type: entry.type == FinanceEntryType.refund
          ? EmployeeWalletTransactionType.refund
          : EmployeeWalletTransactionType.commission,
      description: entry.type == FinanceEntryType.refund
          ? 'برگشت پورسانت نوبت ${entry.appointmentId}'
          : 'پورسانت نوبت ${entry.appointmentId}',
      sourceFinanceEntryId: entry.id,
      appointmentId: entry.appointmentId,
      referenceType: 'employee_finance_entry', referenceId: entry.id,
    ));
  }


  void reschedule(Appointment appointment, DateTime newStart, {String? actor, bool byCustomer = false}) {
    final index = _appointments.indexWhere((a) => a.id == appointment.id);
    if (index == -1) return;
    final previous = _appointments[index];
    _appointments[index] = appointment.copyWith(
      startAt: newStart,
      rescheduleCount: appointment.rescheduleCount + 1,
      totalChanges: appointment.totalChanges + 1,
      updatedAt: DateTime.now(),
    );
    log(
      ActivityType.appointmentUpdated,
      'جابه‌جایی نوبت',
      'نوبت ${appointment.customerName} به ${JalaliDate.fromDateTime(newStart).long} ساعت ${newStart.hour.toString().padLeft(2, '0')}:${newStart.minute.toString().padLeft(2, '0')} منتقل شد.',
      actor: byCustomer ? 'مشتری' : actor,
      entity: 'نوبت',
      entityId: appointment.id,
      undoAction: 'appointment_restore',
      undoData: previous.toJson(),
      operationType: 'appointment_reschedule',
      isReversible: true,
    );
    _commit();
  }

  void deleteAppointment(String id) {
    requirePermission('appointments.cancel');
    final appointment = appointmentById(id);
    if (appointment == null) return;
    if (_appointmentPayments.any((item) => item.appointmentId == id) || _employeeFinanceEntries.any((item) => item.appointmentId == id)) {
      throw StateError('این نوبت سند مالی دارد؛ حذف آن مجاز نیست. ابتدا از مسیر مالی سند اصلاحی ثبت کنید.');
    }
    _appointments.removeWhere((a) => a.id == id);
    log(ActivityType.appointmentCancelled, 'حذف نوبت', 'نوبت ${appointment.customerName} حذف شد.', entity: 'نوبت', entityId: id,
      undoAction: 'appointment_deleted', undoData: appointment.toJson(), operationType: 'appointment_delete', isReversible: true);
    _commit();
  }

  // ---------------------------------------------------------------------------
  // مشتریان
  // ---------------------------------------------------------------------------
  Customer? customerById(String id) {
    for (final c in _customers) {
      if (c.id == id && (_isGlobalAdmin || _appointments.any((item) => item.employeeId == _activeEmployeeId && item.customerId == id))) return c;
    }
    return null;
  }

  void addCustomer(Customer customer) {
    requirePermission('customers.create');
    _customers.add(customer);
    log(ActivityType.customerRegistered, 'ثبت مشتری جدید', '${customer.fullName} با شماره ${customer.phone} ثبت شد.', entity: 'مشتری', entityId: customer.id, operationType: 'customer_create', isReversible: false);
    _commit();
  }

  void updateCustomer(Customer customer) {
    requirePermission('customers.edit');
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index == -1) return;
    _customers[index] = customer;
    log(ActivityType.settingsChanged, 'ویرایش مشتری', 'اطلاعات ${customer.fullName} به‌روزرسانی شد.', entity: 'مشتری', entityId: customer.id, operationType: 'customer_update', isReversible: false);
    _commit();
  }

  void deleteCustomer(String id) {
    requirePermission('customers.edit');
    final customer = customerById(id);
    if (customer == null) return;
    final hasHistory = _appointments.any((item) => item.customerId == id) ||
        _appointmentPayments.any((item) => item.customerId == id);
    if (hasHistory) {
      final index = _customers.indexWhere((item) => item.id == id);
      _customers[index] = customer.copyWith(isArchived: true);
      log(ActivityType.settingsChanged, 'بایگانی مشتری', 'پروفایل «${customer.fullName}» به دلیل وجود سابقه نوبت یا مالی بایگانی شد؛ سوابق حفظ شدند.',
        entity: 'مشتری', entityId: id, undoAction: 'customer_restore', undoData: customer.toJson(),
        operationType: 'customer_archive', isReversible: true);
    } else {
      _customers.removeWhere((c) => c.id == id);
      log(ActivityType.settingsChanged, 'حذف مشتری', '${customer.fullName} از فهرست مشتریان حذف شد.',
        entity: 'مشتری', entityId: id, undoAction: 'customer_restore', undoData: customer.toJson(),
        operationType: 'customer_delete', isReversible: true);
    }
    _commit();
  }

  // ---------------------------------------------------------------------------
  // خدمات
  // ---------------------------------------------------------------------------
  Service? serviceById(String id) {
    if (!_isGlobalAdmin && !services.any((item) => item.id == id)) return null;
    for (final s in _services) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// ایجاد دسته‌بندی خدمت با جلوگیری از نام خالی و تکراری.
  void addServiceCategory(String name) {
    requirePermission('services.manage');
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError('نام دسته‌بندی الزامی است.');
    if (_serviceCategories.any((item) => item.toLowerCase() == normalized.toLowerCase())) {
      throw StateError('این دسته‌بندی قبلاً ثبت شده است.');
    }
    _serviceCategories.add(normalized);
    _serviceCategories.sort();
    _commit();
  }

  /// تغییر نام دسته‌بندی و به‌روزرسانی ارجاع تمام خدمات مرتبط.
  void renameServiceCategory(String oldName, String newName) {
    requirePermission('services.manage');
    final normalized = newName.trim();
    if (normalized.isEmpty) throw ArgumentError('نام دسته‌بندی الزامی است.');
    if (oldName == normalized) return;
    if (_serviceCategories.any((item) => item.toLowerCase() == normalized.toLowerCase())) {
      throw StateError('دسته‌بندی دیگری با این نام وجود دارد.');
    }
    if (!_serviceCategories.contains(oldName)) throw StateError('دسته‌بندی پیدا نشد.');
    for (var index = 0; index < _services.length; index++) {
      if (_services[index].category == oldName) {
        _services[index] = _services[index].copyWith(category: normalized);
      }
    }
    _serviceCategories[_serviceCategories.indexOf(oldName)] = normalized;
    _serviceCategories.sort();
    _commit();
  }

  /// حذف دسته‌بندی فقط پس از تعیین تکلیف خدمات وابسته مجاز است.
  void deleteServiceCategory(String name, {String? moveServicesTo}) {
    requirePermission('services.manage');
    if (!_serviceCategories.contains(name)) return;
    final dependents = _services.where((service) => service.category == name).toList();
    final previousServices = dependents.map((service) => service.toJson()).toList();
    if (dependents.isNotEmpty) {
      final target = moveServicesTo?.trim();
      if (target == null || target.isEmpty || target == name || !_serviceCategories.contains(target)) {
        throw StateError('این دسته‌بندی دارای خدمت وابسته است؛ ابتدا دسته‌بندی مقصد را مشخص کنید.');
      }
      for (var index = 0; index < _services.length; index++) {
        if (_services[index].category == name) {
          _services[index] = _services[index].copyWith(category: target);
        }
      }
    }
    _serviceCategories.remove(name);
    log(ActivityType.serviceModified, 'حذف دسته‌بندی خدمت', 'دسته‌بندی «$name» حذف شد؛ ${dependents.length} خدمت وابسته ${moveServicesTo == null ? 'وجود نداشت' : 'به «$moveServicesTo» منتقل شد'}.',
      entity: 'دسته‌بندی خدمت', entityId: name, undoAction: 'service_category_restore',
      undoData: {'name': name, 'services': previousServices}, operationType: 'service_category_delete', isReversible: true);
    _commit();
  }

  void addService(Service service) {
    requirePermission('services.manage');
    if (_services.any((item) => item.id == service.id)) throw StateError('شناسه خدمت تکراری است.');
    final validEmployeeIds = service.employeeIds.where((id) => _employees.any((employee) => employee.id == id)).toSet();
    final normalized = service.copyWith(employeeIds: validEmployeeIds.toList());
    _services.add(normalized);
    if (!_serviceCategories.contains(normalized.category)) {
      _serviceCategories.add(normalized.category);
      _serviceCategories.sort();
    }
    for (var index = 0; index < _employees.length; index++) {
      final employee = _employees[index];
      final assigned = validEmployeeIds.contains(employee.id);
      final ids = employee.serviceIds.where((id) => id != normalized.id).toList();
      if (assigned) ids.add(normalized.id);
      _employees[index] = employee.copyWith(serviceIds: ids);
      if (assigned) {
        final key = _serviceConfigKey(employee.id, normalized.id);
        _employeeServiceConfigs.putIfAbsent(
          key,
          () => EmployeeServiceConfig(employeeId: employee.id, serviceId: normalized.id),
        );
      }
    }
    log(ActivityType.serviceModified, 'افزودن خدمت', 'خدمت «${normalized.title}» اضافه شد.', entity: 'خدمت', entityId: normalized.id, operationType: 'service_create', isReversible: false);
    _commit();
  }

  void updateService(Service service) {
    requirePermission('services.manage');
    final index = _services.indexWhere((s) => s.id == service.id);
    if (index == -1) return;
    final validEmployeeIds = service.employeeIds.where((id) => _employees.any((employee) => employee.id == id)).toSet();
    _services[index] = service.copyWith(employeeIds: validEmployeeIds.toList());
    if (!_serviceCategories.contains(service.category)) { _serviceCategories.add(service.category); _serviceCategories.sort(); }
    for (var employeeIndex = 0; employeeIndex < _employees.length; employeeIndex++) {
      final employee = _employees[employeeIndex];
      final assigned = validEmployeeIds.contains(employee.id);
      final serviceIds = employee.serviceIds.where((id) => id != service.id).toList();
      if (assigned) serviceIds.add(service.id);
      _employees[employeeIndex] = employee.copyWith(serviceIds: serviceIds);
      final key = _serviceConfigKey(employee.id, service.id);
      final config = _employeeServiceConfigs[key];
      if (config == null && assigned) {
        _employeeServiceConfigs[key] = EmployeeServiceConfig(employeeId: employee.id, serviceId: service.id);
      } else if (config != null && config.active != assigned) {
        _employeeServiceConfigs[key] = config.copyWith(active: assigned);
      }
    }
    log(ActivityType.serviceModified, 'ویرایش خدمت', 'خدمت «${service.title}» به‌روزرسانی شد.', entity: 'خدمت', entityId: service.id, operationType: 'service_update', isReversible: false);
    _commit();
  }

  void deleteService(String id) {
    requirePermission('services.manage');
    final service = serviceById(id);
    if (service == null) return;
    final hasHistory = _appointments.any((appointment) => appointment.serviceIds.contains(id)) ||
        _employeeFinanceEntries.any((entry) => entry.serviceId == id);
    if (hasHistory) {
      updateService(service.copyWith(isActive: false, employeeIds: const []));
      log(ActivityType.serviceModified, 'بایگانی خدمت', 'خدمت «${service.title}» به دلیل وجود سابقه نوبت غیرفعال شد؛ سوابق حفظ شدند.',
        entity: 'خدمت', entityId: id, undoAction: 'service_restore', undoData: service.toJson(), operationType: 'service_archive', isReversible: true);
      _commit();
      return;
    }
    final relatedConfigs = _employeeServiceConfigs.values.where((value) => value.serviceId == id).map((value) => value.toJson()).toList();
    _services.removeWhere((item) => item.id == id);
    _employeeServiceConfigs.removeWhere((key, value) => value.serviceId == id);
    for (var index = 0; index < _employees.length; index++) {
      final employee = _employees[index];
      if (employee.serviceIds.contains(id)) {
        _employees[index] = employee.copyWith(serviceIds: employee.serviceIds.where((serviceId) => serviceId != id).toList());
      }
    }
    log(ActivityType.serviceModified, 'حذف خدمت', 'خدمت «${service.title}» حذف شد.', entity: 'خدمت', entityId: id,
      undoAction: 'service_deleted', undoData: {'service': service.toJson(), 'configs': relatedConfigs}, operationType: 'service_delete', isReversible: true);
    _commit();
  }

  void toggleService(String id, bool active) {
    requirePermission('services.manage');
    final service = serviceById(id);
    if (service == null) return;
    updateService(service.copyWith(isActive: active));
  }

  // ---------------------------------------------------------------------------
  // پرسنل
  // ---------------------------------------------------------------------------
  Employee? employeeById(String id) {
    if (!_isGlobalAdmin && id != _activeEmployeeId) return null;
    for (final e in _employees) {
      if (e.id == id) return e;
    }
    return null;
  }

  void addEmployee(Employee employee) {
    requirePermission('employees.create');
    _employees.add(employee);
    _syncEmployeeServiceLinks(employee);
    log(ActivityType.employeeAdded, 'افزودن پرسنل', '${employee.fullName} به تیم اضافه شد.', entity: 'پرسنل', entityId: employee.id, operationType: 'employee_create', isReversible: false);
    _commit();
  }

  void updateEmployee(Employee employee) {
    requirePermission('employees.edit');
    final index = _employees.indexWhere((e) => e.id == employee.id);
    if (index == -1) return;
    _employees[index] = employee;
    _syncEmployeeServiceLinks(employee);
    log(ActivityType.employeeAdded, 'ویرایش پرسنل', 'پروفایل ${employee.fullName} به‌روزرسانی شد.', entity: 'پرسنل', entityId: employee.id, operationType: 'employee_update', isReversible: false);
    _commit();
  }

  /// در صورت وجود سابقه نوبت، پروفایل بایگانی می‌شود تا ارجاعات تاریخی حفظ شوند.
  void deleteEmployee(String id) {
    requirePermission('employees.deactivate');
    final employee = employeeById(id);
    if (employee == null) return;
    final hasHistory = _appointments.any((appointment) => appointment.employeeId == id) ||
        _employeeFinanceEntries.any((entry) => entry.employeeId == id) ||
        _employeeWalletTransactions.any((entry) => entry.employeeId == id) ||
        _employeeWalletSettlements.any((entry) => entry.employeeId == id) ||
        _salaryContracts.containsKey(id) ||
        _payrollAdjustments.any((entry) => entry.employeeId == id) ||
        _payrollAdvances.any((entry) => entry.employeeId == id) ||
        _attendanceRecords.any((entry) => entry.employeeId == id) ||
        _employeeDocuments.any((entry) => entry.employeeId == id) ||
        _employeeLeaves.any((entry) => entry.employeeId == id) ||
        _employeeNotices.any((entry) => entry.employeeId == id) ||
        _performanceTargets.any((entry) => entry.employeeId == id) ||
        _accessAssignments.containsKey(id) ||
        _accessAccounts.any((account) => account.employeeId == id);
    if (hasHistory) {
      final archived = employee.copyWith(isActive: false, status: EmployeeStatus.inactive);
      updateEmployee(archived);
      log(ActivityType.employeeAdded, 'بایگانی پرسنل', 'پروفایل ${employee.fullName} به دلیل وجود سوابق نوبت بایگانی شد.', entity: 'پرسنل', entityId: id,
        undoAction: 'employee_restore', undoData: employee.toJson(), operationType: 'employee_archive', isReversible: true);
      _commit();
      return;
    }
    final relatedConfigs = _employeeServiceConfigs.values.where((value) => value.employeeId == id).map((value) => value.toJson()).toList();
    final relatedExceptions = _employeeScheduleExceptions.values.where((value) => value.employeeId == id).map((value) => value.toJson()).toList();
    final previousPayProfile = _employeePayProfiles[id]?.toJson();
    _employees.removeWhere((item) => item.id == id);
    _employeeServiceConfigs.removeWhere((key, value) => value.employeeId == id);
    _employeeScheduleExceptions.removeWhere((key, value) => value.employeeId == id);
    _employeePayProfiles.remove(id);
    for (var index = 0; index < _services.length; index++) {
      final service = _services[index];
      if (service.employeeIds.contains(id)) {
        _services[index] = service.copyWith(employeeIds: service.employeeIds.where((employeeId) => employeeId != id).toList());
      }
    }
    log(ActivityType.employeeAdded, 'حذف پرسنل', '${employee.fullName} حذف شد.', entity: 'پرسنل', entityId: id,
      undoAction: 'employee_deleted', undoData: {
        'employee': employee.toJson(), 'service_configs': relatedConfigs,
        'schedule_exceptions': relatedExceptions, 'pay_profile': previousPayProfile,
      }, operationType: 'employee_delete', isReversible: true);
    _commit();
  }

  void _requireEmployeeProfileRead(String employeeId) {
    if (currentAccessAccount.employeeId == employeeId) return;
    requirePermission('employees.view_profile');
    if (!canViewEmployee(employeeId)) {
      throw const AccessDeniedException('اجازه مشاهده اطلاعات این پرسنل را ندارید.');
    }
  }

  // حضور و غیاب، پرونده دیجیتال و اعلان‌های آفلاین.
  List<AttendanceRecord> attendanceFor(String employeeId, {DateTime? from, DateTime? to}) {
    _requireEmployeeProfileRead(employeeId);
    return _attendanceRecords.where((item) => item.employeeId == employeeId &&
      (from == null || !item.at.isBefore(from)) && (to == null || !item.at.isAfter(to))).toList()
      ..sort((a,b)=>b.at.compareTo(a.at));
  }

  void recordAttendance(AttendanceRecord record) {
    if (record.isManualCorrection) requirePermission('employees.edit',employeeId:record.employeeId);
    if (currentAccessAccount.employeeId != record.employeeId) {
      requirePermission('employees.edit', employeeId: record.employeeId);
    } else if (!hasPermission('appointments.view_self') && !hasPermission('employees.edit')) {
      throw AccessDeniedException('برای ثبت حضور شخصی دسترسی ندارید.');
    }
    if (employeeById(record.employeeId) == null) throw StateError('پرسنل یافت نشد.');
    if (_attendanceRecords.any((item)=>item.id==record.id)) throw StateError('شناسه حضور تکراری است.');
    if ([record.overtimeMinutes,record.lateMinutes,record.earlyLeaveMinutes].any((value)=>value<0)) throw ArgumentError('دقایق حضور و غیاب نمی‌توانند منفی باشند.');
    if (record.date.year != record.at.year || record.date.month != record.at.month || record.date.day != record.at.day) throw ArgumentError('تاریخ رکورد با زمان ثبت‌شده یکسان نیست.');
    final sameDayEvents = _attendanceRecords.where((item) =>
      item.employeeId == record.employeeId && item.date.year == record.date.year &&
      item.date.month == record.date.month && item.date.day == record.date.day &&
      (item.type == AttendanceEventType.checkIn || item.type == AttendanceEventType.checkOut))
      .toList()..sort((a, b) => a.at.compareTo(b.at));
    DateTime? openCheckIn;
    for (final event in sameDayEvents) {
      if (event.type == AttendanceEventType.checkIn) {
        openCheckIn = event.at;
      } else if (event.type == AttendanceEventType.checkOut && openCheckIn != null) {
        openCheckIn = null;
      }
    }
    final sameDayRecords = _attendanceRecords.where((item) =>
      item.employeeId == record.employeeId && item.date.year == record.date.year &&
      item.date.month == record.date.month && item.date.day == record.date.day);
    if (record.type == AttendanceEventType.absence &&
        sameDayRecords.any((item) => item.type == AttendanceEventType.checkIn ||
          item.type == AttendanceEventType.absence || item.type == AttendanceEventType.mission)) {
      throw StateError('برای این روز حضور، مأموریت یا غیبت قبلاً ثبت شده است.');
    }
    if (record.type == AttendanceEventType.checkIn) {
      if (sameDayRecords.any((item) => item.type == AttendanceEventType.absence)) throw StateError('برای این روز غیبت ثبت شده است.');
      if (openCheckIn != null) throw StateError('ابتدا باید خروج شیفت قبلی ثبت شود.');
    }
    if (record.type == AttendanceEventType.checkOut && (openCheckIn == null || !record.at.isAfter(openCheckIn))) {
      throw StateError('برای این خروج، ورود باز و معتبر وجود ندارد.');
    }
    _attendanceRecords.add(record);
    final employee=employeeById(record.employeeId)!;
    log(ActivityType.settingsChanged,'ثبت حضور و غیاب','رویداد حضور برای ${employee.fullName} ثبت شد.',entity:'حضور و غیاب');
    _commit();
  }

  void updateAttendanceRecord(AttendanceRecord record) {
    requirePermission('employees.edit',employeeId:record.employeeId);
    final index=_attendanceRecords.indexWhere((item)=>item.id==record.id && item.employeeId==record.employeeId);
    if(index<0) throw StateError('رکورد حضور و غیاب پیدا نشد.');
    if(record.at.isBefore(DateTime(2000))) throw ArgumentError('زمان اصلاح معتبر نیست.');
    if([record.overtimeMinutes,record.lateMinutes,record.earlyLeaveMinutes].any((value)=>value<0)) throw ArgumentError('مقادیر دقیقه نمی‌توانند منفی باشند.');
    _attendanceRecords[index]=record.copyWith(isManualCorrection:true,createdBy:currentAccessAccount.name);
    _commit();
  }

  AttendanceSummary attendanceSummary(String employeeId,{required DateTime from,required DateTime to}) {
    final rows=attendanceFor(employeeId,from:from,to:to);
    final present=rows.where((r)=>r.type==AttendanceEventType.checkIn || r.type==AttendanceEventType.mission)
      .map((r)=>DateTime(r.date.year,r.date.month,r.date.day)).toSet();
    final absent=rows.where((r)=>r.type==AttendanceEventType.absence).map((r)=>DateTime(r.date.year,r.date.month,r.date.day)).toSet();
    var worked=0, overtime=0, late=0, early=0;
    final sessions=rows.where((r)=>r.type==AttendanceEventType.checkIn || r.type==AttendanceEventType.checkOut).toList()
      ..sort((a,b)=>a.at.compareTo(b.at));
    DateTime? open;
    for(final event in sessions){
      if(event.type==AttendanceEventType.checkIn) { open=event.at; }
      else if(event.type==AttendanceEventType.checkOut && open!=null) { worked+=event.at.difference(open).inMinutes; open=null; }
    }
    for(final row in rows){overtime+=row.overtimeMinutes;late+=row.lateMinutes;early+=row.earlyLeaveMinutes;}
    return AttendanceSummary(presentDays:present.length,absentDays:absent.length,workedMinutes:worked,overtimeMinutes:overtime,lateMinutes:late,earlyLeaveMinutes:early);
  }

  bool saveAttendancePayrollPolicy(AttendancePayrollPolicy policy) {
    requirePermission('employees.edit');
    if (policy.lateDeductionPerMinute < 0 || policy.absenceDeductionPerDay < 0 || policy.overtimePaymentPerMinute < 0 || policy.earlyLeaveDeductionPerMinute < 0) {
      throw ArgumentError('مقادیر قانون مالی نمی‌توانند منفی باشند.');
    }
    final previous = _attendancePayrollPolicy;
    final changed = previous.enabled != policy.enabled ||
        previous.lateDeductionPerMinute != policy.lateDeductionPerMinute ||
        previous.absenceDeductionPerDay != policy.absenceDeductionPerDay ||
        previous.overtimePaymentPerMinute != policy.overtimePaymentPerMinute ||
        previous.earlyLeaveDeductionPerMinute != policy.earlyLeaveDeductionPerMinute;
    if (!changed) return false;
    _attendancePayrollPolicy = policy;
    log(
      ActivityType.settingsChanged,
      'تغییر قانون مالی حضور و غیاب',
      'قواعد محاسبه اثر مالی تأخیر، غیبت، اضافه‌کاری و خروج زودهنگام تغییر کرد.',
      entity: 'قانون مالی حضور و غیاب',
      entityId: 'attendance-payroll-policy',
      undoAction: 'attendance_payroll_policy_restore',
      undoData: {
        'enabled': previous.enabled,
        'late_deduction_per_minute': previous.lateDeductionPerMinute,
        'absence_deduction_per_day': previous.absenceDeductionPerDay,
        'overtime_payment_per_minute': previous.overtimePaymentPerMinute,
        'early_leave_deduction_per_minute': previous.earlyLeaveDeductionPerMinute,
      },
      operationType: 'financial_attendance_policy_update',
      isReversible: true,
    );
    _commit();
    return true;
  }

  AttendancePayrollPreview attendancePayrollPreview(String employeeId,{required DateTime from,required DateTime to}) {
    final summary = attendanceSummary(employeeId,from:from,to:to);
    final policy = _attendancePayrollPolicy;
    if (!policy.enabled) return const AttendancePayrollPreview(lateDeduction:0,absenceDeduction:0,overtimePayment:0,earlyLeaveDeduction:0,netAdjustment:0);
    final late = summary.lateMinutes * policy.lateDeductionPerMinute;
    final absence = summary.absentDays * policy.absenceDeductionPerDay;
    final overtime = summary.overtimeMinutes * policy.overtimePaymentPerMinute;
    final early = summary.earlyLeaveMinutes * policy.earlyLeaveDeductionPerMinute;
    return AttendancePayrollPreview(lateDeduction:late,absenceDeduction:absence,overtimePayment:overtime,earlyLeaveDeduction:early,netAdjustment:overtime-late-absence-early);
  }

  List<EmployeeDocument> documentsFor(String employeeId) {
    _requireEmployeeProfileRead(employeeId);
    return _employeeDocuments.where((d)=>d.employeeId==employeeId).toList()..sort((a,b)=>b.addedAt.compareTo(a.addedAt));
  }
  void updateEmployeeDocument(EmployeeDocument document){
    requirePermission('employees.edit',employeeId:document.employeeId);
    final index=_employeeDocuments.indexWhere((item)=>item.id==document.id && item.employeeId==document.employeeId);
    if(index<0) throw StateError('سند پیدا نشد.');
    if(document.title.trim().isEmpty || document.fileName.trim().isEmpty) throw ArgumentError('عنوان و فایل سند الزامی است.');
    _employeeDocuments[index]=document; _commit();
  }
  void deleteEmployeeDocument(String id){
    final index=_employeeDocuments.indexWhere((item)=>item.id==id);
    if(index<0)return; requirePermission('employees.edit',employeeId:_employeeDocuments[index].employeeId);
    _employeeDocuments.removeAt(index); _commit();
  }
  void addEmployeeDocument(EmployeeDocument document){
    requirePermission('employees.edit',employeeId:document.employeeId);
    if(employeeById(document.employeeId)==null) throw StateError('پرسنل یافت نشد.');
    if(_employeeDocuments.any((d)=>d.id==document.id)) throw StateError('شناسه سند تکراری است.');
    if(document.title.trim().isEmpty || document.fileName.trim().isEmpty) throw ArgumentError('عنوان و نام فایل الزامی است.');
    _employeeDocuments.add(document); _commit();
  }
  List<EmployeeNotice> noticesFor(String employeeId) {
    _requireEmployeeProfileRead(employeeId);
    return _employeeNotices.where((n)=>n.employeeId==employeeId).toList()..sort((a,b)=>b.createdAt.compareTo(a.createdAt));
  }
  void addEmployeeNotice(EmployeeNotice notice){_employeeNotices.insert(0,notice);_commit();}
  void markEmployeeNoticeRead(String id){
    final i=_employeeNotices.indexWhere((n)=>n.id==id); if(i<0)return;
    final n=_employeeNotices[i]; _employeeNotices[i]=n.markRead(); _commit();
  }
  void _notifyEmployee(String employeeId,EmployeeNoticeType type,String title,String message){
    _employeeNotices.insert(0,EmployeeNotice(id:nextId('notice'),employeeId:employeeId,type:type,title:title,message:message,createdAt:DateTime.now()));
  }
  void _seedEmployeeHr(){
    final now=DateTime.now();
    for(var i=0;i<_employees.length && i<5;i++){
      final e=_employees[i]; final day=DateTime(now.year,now.month,now.day).subtract(Duration(days:i+1));
      if(i==4){
        _attendanceRecords.add(AttendanceRecord(id:'att-absence-${e.id}',employeeId:e.id,date:day,type:AttendanceEventType.absence,at:day.add(const Duration(hours:9)),note:'غیبت نمونه',createdBy:'مدیر سیستم'));
      } else {
        _attendanceRecords.add(AttendanceRecord(id:'att-in-${e.id}',employeeId:e.id,date:day,type:AttendanceEventType.checkIn,at:day.add(Duration(hours:8,minutes:i*7)),lateMinutes:i*7));
        _attendanceRecords.add(AttendanceRecord(id:'att-out-${e.id}',employeeId:e.id,date:day,type:AttendanceEventType.checkOut,at:day.add(Duration(hours:16,minutes:i*7)),overtimeMinutes:i*10));
      }
      if(i==3) _attendanceRecords.add(AttendanceRecord(id:'att-mission-${e.id}',employeeId:e.id,date:day,type:AttendanceEventType.mission,at:day.add(const Duration(hours:11)),note:'مأموریت نمونه',createdBy:'مدیر سیستم'));
      _employeeDocuments.add(EmployeeDocument(id:'doc-contract-${e.id}',employeeId:e.id,title:'قرارداد همکاری',type:EmployeeDocumentType.contract,fileName:'contract-demo.pdf',addedAt:day,expiresAt:day.add(Duration(days:20+i*10)),note:'فایل نمایشی آفلاین'));
      if(i<2) _notifyEmployee(e.id,EmployeeNoticeType.contractExpiring,'اعتبار قرارداد رو به پایان است.','برای بررسی تاریخ اعتبار قرارداد پرسنل اقدام کنید.');
      _notifyEmployee(e.id,EmployeeNoticeType.scheduleChanged,'برنامه کاری به‌روزرسانی شد.','برنامه کاری نمونه برای بررسی رابط کاربری ثبت شده است.');
    }
  }

  // برنامه کاری اختصاصی پرسنل، استثناهای تاریخ‌دار و مرخصی
  String _employeeScheduleKey(String employeeId, String dateKey) => employeeId + '::' + dateKey;

  List<EmployeeLeave> leavesForEmployee(String employeeId) {
    _requireEmployeeProfileRead(employeeId);
    return _employeeLeaves.where((leave) => leave.employeeId == employeeId).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  EmployeeScheduleException? employeeScheduleException(String employeeId, DateTime date) =>
      _employeeScheduleExceptions[_employeeScheduleKey(employeeId, EmployeeScheduleRules.dateKey(date))];

  List<Shift> employeeShiftsForDate(String employeeId, DateTime date) {
    final employee = employeeById(employeeId);
    if (employee == null || !employee.scheduleEnabled || !employee.isAvailableForBooking) return const [];
    final exception = employeeScheduleException(employeeId, date);
    if (exception != null) return exception.isClosed ? const [] : exception.shifts;
    final key = EmployeeScheduleRules.dateKey(date);
    if (employee.daysOff.contains(key)) return const [];
    return employee.shiftsFor(JalaliDate.fromDateTime(date).weekday);
  }

  void saveEmployeeWeeklySchedule(String employeeId, Map<int, List<Shift>> schedule, {bool enabled = true, int bufferMinutes = 0}) {
    final employee = employeeById(employeeId);
    if (employee == null) throw StateError('پرسنل یافت نشد.');
    if (bufferMinutes < 0 || bufferMinutes > 240) throw ArgumentError('فاصله بین نوبت‌ها معتبر نیست.');
    for (final shifts in schedule.values) { EmployeeScheduleRules.validateShifts(shifts); }
    if (schedule.keys.any((day) => day < 0 || day > 6)) throw ArgumentError('روز هفته معتبر نیست.');
    updateEmployee(employee.copyWith(schedule: schedule, scheduleEnabled: enabled, bufferMinutes: bufferMinutes));
    _notifyEmployee(employeeId,EmployeeNoticeType.scheduleChanged,'برنامه کاری تغییر کرد.','برنامه کاری شما توسط مدیر به‌روزرسانی شد.');
    log(ActivityType.settingsChanged, 'به‌روزرسانی برنامه پرسنل', 'برنامه کاری ' + employee.fullName + ' تغییر کرد.', entity: 'برنامه پرسنل');
    _commit();
  }

  void saveEmployeeScheduleException(EmployeeScheduleException exception) {
    requirePermission('employees.edit', employeeId: exception.employeeId);
    final employee = employeeById(exception.employeeId);
    if (employee == null) throw StateError('پرسنل یافت نشد.');
    final parsed = DateTime.tryParse(exception.dateKey);
    if (parsed == null || EmployeeScheduleRules.dateKey(parsed) != exception.dateKey) throw ArgumentError('تاریخ استثنا معتبر نیست.');
    EmployeeScheduleRules.validateShifts(exception.shifts);
    if (!exception.isClosed && exception.shifts.isEmpty) throw ArgumentError('برای ساعات ویژه حداقل یک شیفت تعریف کنید.');
    _employeeScheduleExceptions[_employeeScheduleKey(exception.employeeId, exception.dateKey)] = exception;
    log(ActivityType.settingsChanged, 'ثبت ساعات ویژه پرسنل', exception.dateKey + ' برای ' + employee.fullName + ' ثبت شد.', entity: 'برنامه پرسنل');
    _commit();
  }

  void deleteEmployeeScheduleException(String employeeId, String dateKey) {
    requirePermission('employees.edit', employeeId: employeeId);
    _employeeScheduleExceptions.remove(_employeeScheduleKey(employeeId, dateKey));
    _commit();
  }

  void addEmployeeLeave(EmployeeLeave leave) {
    final employee = employeeById(leave.employeeId);
    if (employee == null) throw StateError('پرسنل یافت نشد.');
    if (currentAccessAccount.employeeId == leave.employeeId) {
      requirePermission('employees.leave.request', employeeId: leave.employeeId);
    } else {
      requirePermission('employees.edit', employeeId: leave.employeeId);
    }
    if (!leave.endAt.isAfter(leave.startAt)) throw ArgumentError('پایان مرخصی باید بعد از شروع آن باشد.');
    if (_employeeLeaves.any((item) => item.id == leave.id)) throw StateError('شناسه مرخصی تکراری است.');
    if (_employeeLeaves.any((item) => item.employeeId == leave.employeeId && item.status != EmployeeLeaveStatus.rejected && item.startAt.isBefore(leave.endAt) && leave.startAt.isBefore(item.endAt))) {
      throw ArgumentError('این مرخصی با درخواست دیگری هم‌پوشانی دارد.');
    }
    _employeeLeaves.add(leave);
    _notifyEmployee(leave.employeeId,EmployeeNoticeType.leaveRequested,'درخواست مرخصی ثبت شد.','درخواست مرخصی شما در انتظار بررسی است.');
    for(final manager in _accessAccounts.where((account)=>account.isEnabled && account.employeeId!=null && account.roleId=='global_admin')){
      _notifyEmployee(manager.employeeId!,EmployeeNoticeType.leaveRequested,'درخواست مرخصی جدید','درخواست مرخصی برای ${employee.fullName} ثبت شده و نیازمند بررسی است.');
    }
    log(ActivityType.settingsChanged, 'ثبت مرخصی پرسنل', 'مرخصی جدید برای ' + employee.fullName + ' ثبت شد.', entity: 'مرخصی پرسنل');
    _commit();
  }

  void updateEmployeeLeave(EmployeeLeave leave) {
    requirePermission('employees.edit', employeeId: leave.employeeId);
    final index = _employeeLeaves.indexWhere((item) => item.id == leave.id && item.employeeId == leave.employeeId);
    if (index < 0) throw StateError('مرخصی یافت نشد.');
    if (!leave.endAt.isAfter(leave.startAt)) throw ArgumentError('پایان مرخصی باید بعد از شروع آن باشد.');
    if (leave.status == EmployeeLeaveStatus.approved) {
      final conflict = _employeeLeaves.any((item) => item.id != leave.id && item.employeeId == leave.employeeId && item.status == EmployeeLeaveStatus.approved && item.startAt.isBefore(leave.endAt) && leave.startAt.isBefore(item.endAt));
      if (conflict) throw ArgumentError('مرخصی با مرخصی تأییدشده دیگری هم‌پوشانی دارد.');
      final appointmentConflict = _appointments.any((appointment) =>
        appointment.employeeId == leave.employeeId &&
        appointment.status != AppointmentStatus.cancelled &&
        appointment.startAt.isBefore(leave.endAt) &&
        leave.startAt.isBefore(appointment.endAt));
      if (appointmentConflict) throw ArgumentError('در این بازه برای پرسنل نوبت ثبت شده است؛ ابتدا نوبت را جابه‌جا یا لغو کنید.');
    }
    _employeeLeaves[index] = leave;
    _notifyEmployee(leave.employeeId,leave.status==EmployeeLeaveStatus.approved?EmployeeNoticeType.leaveApproved:EmployeeNoticeType.leaveRejected,'وضعیت مرخصی تغییر کرد.','درخواست مرخصی شما ${leave.status.label} شد.');
    log(ActivityType.settingsChanged, 'به‌روزرسانی مرخصی پرسنل', 'وضعیت مرخصی ' + leave.id + ' تغییر کرد.', entity: 'مرخصی پرسنل');
    _commit();
  }

  void deleteEmployeeLeave(String id) {
    final matches = _employeeLeaves.where((leave) => leave.id == id).toList();
    if (matches.isEmpty) return;
    requirePermission('employees.edit', employeeId: matches.first.employeeId);
    _employeeLeaves.removeWhere((leave) => leave.id == id);
    _commit();
  }

  bool isEmployeeAvailableAt({required String employeeId, required DateTime startAt, required int durationMinutes, String? ignoreAppointmentId}) {
    final employee = employeeById(employeeId);
    if (employee == null || !employee.isAvailableForBooking || durationMinutes <= 0) return false;
    final endAt = startAt.add(Duration(minutes: durationMinutes));
    final shifts = employeeShiftsForDate(employeeId, startAt);
    final startMinute = startAt.hour * 60 + startAt.minute;
    final endMinute = endAt.hour * 60 + endAt.minute + (endAt.day != startAt.day ? 24 * 60 : 0);
    if (!shifts.any((shift) => startMinute >= shift.startMinutes && endMinute <= shift.endMinutes)) return false;
    if (_employeeLeaves.any((leave) => leave.employeeId == employeeId && leave.status == EmployeeLeaveStatus.approved && leave.overlaps(startAt, endAt))) return false;
    final buffer = Duration(minutes: employee.bufferMinutes);
    for (final appointment in _appointments) {
      if (appointment.id == ignoreAppointmentId || appointment.employeeId != employeeId || appointment.status == AppointmentStatus.cancelled) continue;
      final bufferedStart = appointment.startAt.subtract(buffer);
      final bufferedEnd = appointment.endAt.add(buffer);
      if (startAt.isBefore(bufferedEnd) && bufferedStart.isBefore(endAt)) return false;
    }
    return true;
  }

  String _serviceConfigKey(String employeeId, String serviceId) => '$employeeId::$serviceId';

  List<EmployeeServiceConfig> employeeServiceConfigsFor(String employeeId) =>
      _employeeServiceConfigs.values.where((item) => item.employeeId == employeeId).toList();

  EmployeeServiceConfig? employeeServiceConfig(String employeeId, String serviceId) =>
      _employeeServiceConfigs[_serviceConfigKey(employeeId, serviceId)];

  bool employeeOffersService(String employeeId, String serviceId) {
    final employee = employeeById(employeeId);
    final service = serviceById(serviceId);
    if (employee == null || service == null || !employee.isAvailableForBooking || !service.isActive) return false;
    final config = employeeServiceConfig(employeeId, serviceId);
    return employee.serviceIds.contains(serviceId) && service.employeeIds.contains(employeeId) && (config?.active ?? true);
  }

  List<Employee> eligibleEmployeesForService(String serviceId) =>
      _employees.where((employee) => employeeOffersService(employee.id, serviceId)).toList();

  int effectiveServicePrice(String employeeId, String serviceId) {
    final service = serviceById(serviceId);
    if (service == null) return 0;
    return employeeServiceConfig(employeeId, serviceId)?.customPrice ?? service.price.round();
  }

  int effectiveServiceDuration(String employeeId, String serviceId) {
    final service = serviceById(serviceId);
    if (service == null) return 0;
    return employeeServiceConfig(employeeId, serviceId)?.customDurationMinutes ?? service.totalMinutes;
  }

  void saveEmployeeServiceConfig(EmployeeServiceConfig config) {
    // تنظیم رابطه خدمت/پرسنل از صفحه مدیریت خدمات نیز مجاز است.
    if (!hasPermission('services.manage')) {
      requirePermission('employees.edit', employeeId: config.employeeId);
    }
    final employee = employeeById(config.employeeId);
    final service = serviceById(config.serviceId);
    if (employee == null || service == null) throw StateError('پرسنل یا خدمت انتخاب‌شده وجود ندارد.');
    if (config.customPrice != null && config.customPrice! < 0) throw ArgumentError('قیمت اختصاصی نمی‌تواند منفی باشد.');
    if (config.customDurationMinutes != null && config.customDurationMinutes! <= 0) throw ArgumentError('مدت‌زمان باید بیشتر از صفر باشد.');
    if (config.commissionRateBps != null && (config.commissionRateBps! < 0 || config.commissionRateBps! > 10000)) throw ArgumentError('درصد پورسانت باید بین صفر تا صد باشد.');
    if (config.fixedCommissionAmount != null && config.fixedCommissionAmount! < 0) throw ArgumentError('مبلغ پورسانت نمی‌تواند منفی باشد.');
    _employeeServiceConfigs[_serviceConfigKey(config.employeeId, config.serviceId)] = config;
    final ids = employee.serviceIds.where((id) => id != config.serviceId).toList();
    if (config.active) ids.add(config.serviceId);
    final updated = employee.copyWith(serviceIds: ids);
    final employeeIndex = _employees.indexWhere((item) => item.id == employee.id);
    _employees[employeeIndex] = updated;
    _syncEmployeeServiceLinks(updated);
    log(ActivityType.serviceModified, 'تنظیم خدمت پرسنل', 'تنظیم خدمت «\${service.title}» برای \${employee.fullName} ذخیره شد.', entity: 'پرسنل و خدمات', entityId: service.id, operationType: 'employee_service_config_update', isReversible: false);
    _commit();
  }

  void removeEmployeeServiceConfig(String employeeId, String serviceId) {
    requirePermission('employees.edit', employeeId: employeeId);
    final employee = employeeById(employeeId);
    if (employee == null) return;
    _employeeServiceConfigs.remove(_serviceConfigKey(employeeId, serviceId));
    final updated = employee.copyWith(serviceIds: employee.serviceIds.where((id) => id != serviceId).toList());
    final index = _employees.indexWhere((item) => item.id == employeeId);
    _employees[index] = updated;
    _syncEmployeeServiceLinks(updated);
    log(ActivityType.serviceModified, 'حذف تخصص پرسنل', 'ارتباط خدمت با پرسنل ' + employee.fullName + ' حذف شد.', entity: 'پرسنل و خدمات', entityId: serviceId, operationType: 'employee_service_config_remove', isReversible: false);
    _commit();
  }

  void _syncEmployeeServiceLinks(Employee employee) {
    for (var index = 0; index < _services.length; index++) {
      final service = _services[index];
      final assigned = employee.serviceIds.contains(service.id);
      final ids = service.employeeIds.where((id) => id != employee.id).toList();
      if (assigned) ids.add(employee.id);
      _services[index] = service.copyWith(employeeIds: ids);
      final key = _serviceConfigKey(employee.id, service.id);
      final config = _employeeServiceConfigs[key];
      if (config == null && assigned) {
        _employeeServiceConfigs[key] = EmployeeServiceConfig(employeeId: employee.id, serviceId: service.id);
      } else if (config != null && config.active != assigned) {
        _employeeServiceConfigs[key] = config.copyWith(active: assigned);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // پیامک
  // ---------------------------------------------------------------------------
  void addSms(SmsMessage message) {
    _sms.insert(0, message);
    if (message.status == SmsStatus.failed) {
      log(ActivityType.smsFailed, 'ارسال ناموفق پیامک', 'ارسال پیامک به ${message.phone} ناموفق بود.', entity: 'پیامک');
    } else {
      log(ActivityType.smsSent, 'ارسال پیامک', 'پیامک «${message.templateLabel}» برای ${message.recipientName} ثبت شد.', entity: 'پیامک');
    }
    _commit();
  }

  void updateSms(SmsMessage message) {
    final index = _sms.indexWhere((s) => s.id == message.id);
    if (index == -1) return;
    _sms[index] = message;
    notifyListeners();
  }

  void updateTemplate(SmsTemplate template) {
    final index = _templates.indexWhere((t) => t.key == template.key);
    if (index == -1) {
      _templates.add(template);
    } else {
      _templates[index] = template;
    }
    log(ActivityType.settingsChanged, 'ویرایش قالب پیامک', 'قالب «${template.label}» به‌روزرسانی شد.', entity: 'پیامک');
    _commit();
  }

  // ---------------------------------------------------------------------------
  // تنظیمات
  // ---------------------------------------------------------------------------
  void updateSettings(BusinessSettings settings, {String? logTitle, String? logDescription}) {
    requirePermission('settings.hours.edit');
    final previous = _settings;
    _settings = settings;
    final undoSchedule = logTitle == 'تغییر ساعت کاری' || logTitle == 'تغییر محدودیت‌های تقویم';
    log(ActivityType.settingsChanged, logTitle ?? 'تغییر تنظیمات', logDescription ?? 'تنظیمات مجموعه به‌روزرسانی شد.', entity: 'تنظیمات',
      undoAction: undoSchedule ? 'settings_hours' : null,
      undoData: undoSchedule ? {
        'working_hours': previous.workingHours.map((k, v) => MapEntry(k.toString(), v.map((s) => s.toJson()).toList())),
        'work_schedules': previous.workSchedules.map((k, v) => MapEntry(k.toString(), v.map((s) => s.toJson()).toList())),
        'holidays': previous.holidays,
        'schedule_exceptions': previous.scheduleExceptions.map((e) => {'date_key': e.dateKey, 'title': e.title, 'is_closed': e.isClosed, 'shifts': e.shifts.map((s) => s.toJson()).toList()}).toList(),
      } : null);
    _commit();
  }

  bool canUndoLog(String id) {
    if (_undoneLogIds.contains(id)) return false;
    ActivityLog? target;
    for (final entry in _logs) { if (entry.id == id) { target = entry; break; } }
    final resolvedTarget = target;
    if (resolvedTarget == null || !resolvedTarget.isReversible || resolvedTarget.undoAction == null || resolvedTarget.undoData == null) return false;
    final targetEntityId = resolvedTarget.undoData!['id'];
    if (resolvedTarget.undoAction == 'appointment_created' &&
        (_appointmentPayments.any((item) => item.appointmentId == targetEntityId) ||
         _employeeFinanceEntries.any((item) => item.appointmentId == targetEntityId))) return false;
    final relatedEntityIds = <String>{};
    if (resolvedTarget.undoAction == 'service_category_restore') {
      for (final raw in resolvedTarget.undoData!['services'] as List? ?? const []) {
        final service = Map<String, dynamic>.from(raw as Map);
        if (service['id'] is String) relatedEntityIds.add(service['id'] as String);
      }
    } else if (resolvedTarget.undoAction == 'service_deleted' || resolvedTarget.undoAction == 'service_restore') {
      final service = resolvedTarget.undoAction == 'service_deleted'
          ? Map<String, dynamic>.from(resolvedTarget.undoData!['service'] as Map)
          : resolvedTarget.undoData!;
      if (service['id'] is String) relatedEntityIds.add(service['id'] as String);
      for (final employeeId in service['employee_ids'] as List? ?? const []) {
        if (employeeId is String) relatedEntityIds.add(employeeId);
      }
    } else if (resolvedTarget.undoAction == 'employee_deleted' || resolvedTarget.undoAction == 'employee_restore') {
      final employee = resolvedTarget.undoAction == 'employee_deleted'
          ? Map<String, dynamic>.from(resolvedTarget.undoData!['employee'] as Map? ?? resolvedTarget.undoData!)
          : resolvedTarget.undoData!;
      if (employee['id'] is String) relatedEntityIds.add(employee['id'] as String);
      for (final serviceId in employee['service_ids'] as List? ?? const []) {
        if (serviceId is String) relatedEntityIds.add(serviceId);
      }
    }
    return !_logs.any((other) {
      if (other.id == id || !other.createdAt.isAfter(resolvedTarget.createdAt)) return false;
      if (resolvedTarget.undoAction == 'settings_hours') return other.undoAction == 'settings_hours';
      final sameEntity = resolvedTarget.entityId.isNotEmpty && other.entityId == resolvedTarget.entityId && other.entityName == resolvedTarget.entityName;
      final sameSnapshot = targetEntityId != null && other.undoData?['id'] == targetEntityId;
      final relatedEntityChanged = relatedEntityIds.contains(other.entityId);
      final roleAssignmentChanged =
          (resolvedTarget.undoAction == 'access_role_restore' || resolvedTarget.undoAction == 'access_role_delete') &&
          other.operationType == 'access_assignment' &&
          (other.undoData?['new_role_id'] == targetEntityId || other.undoData?['role_id'] == targetEntityId);
      return sameEntity || sameSnapshot || relatedEntityChanged || roleAssignmentChanged;
    });
  }
  bool undoLog(String id) {
    if (!canUndoLog(id)) return false;
    final entry = _logs.firstWhere((l) => l.id == id);
    final data = entry.undoData!;
    switch (entry.undoAction) {
      case 'appointment_created': _appointments.removeWhere((a) => a.id == data['id']); break;
      case 'appointment_restore':
        final restored = Appointment.fromJson(data);
        final index = _appointments.indexWhere((a) => a.id == restored.id);
        if (index < 0) return false;
        _appointments[index] = restored;
        break;
      case 'appointment_deleted':
        final restored = Appointment.fromJson(data);
        if (_appointments.any((a) => a.id == restored.id)) return false;
        _appointments.add(restored);
        break;
      case 'customer_restore':
        final restored = Customer.fromJson(data);
        final customerIndex = _customers.indexWhere((item) => item.id == restored.id);
        if (customerIndex >= 0) {
          _customers[customerIndex] = restored;
        } else {
          _customers.add(restored);
        }
        break;
      case 'employee_restore':
        final restored = Employee.fromJson(data);
        final index = _employees.indexWhere((item) => item.id == restored.id);
        if (index < 0) return false;
        _employees[index] = restored;
        _syncEmployeeServiceLinks(restored);
        break;
      case 'employee_deleted':
        final restored = Employee.fromJson(Map<String, dynamic>.from(data['employee'] as Map? ?? data));
        if (_employees.any((item) => item.id == restored.id)) return false;
        _employees.add(restored);
        for (final raw in data['service_configs'] as List? ?? const []) {
          final config = EmployeeServiceConfig.fromJson(Map<String, dynamic>.from(raw as Map));
          _employeeServiceConfigs[_serviceConfigKey(config.employeeId, config.serviceId)] = config;
        }
        for (final raw in data['schedule_exceptions'] as List? ?? const []) {
          final exception = EmployeeScheduleException.fromJson(Map<String, dynamic>.from(raw as Map));
          _employeeScheduleExceptions[_employeeScheduleKey(exception.employeeId, exception.dateKey)] = exception;
        }
        if (data['pay_profile'] != null) {
          final profile = EmployeePayProfile.fromJson(Map<String, dynamic>.from(data['pay_profile'] as Map));
          _employeePayProfiles[profile.employeeId] = profile;
        }
        _syncEmployeeServiceLinks(restored);
        break;
      case 'service_restore':
        final restored = Service.fromJson(data);
        final index = _services.indexWhere((item) => item.id == restored.id);
        if (index < 0) return false;
        _services[index] = restored;
        for (final employee in List<Employee>.of(_employees)) {
          final ids = employee.serviceIds.where((value) => value != restored.id).toList();
          if (restored.employeeIds.contains(employee.id)) ids.add(restored.id);
          _employees[_employees.indexWhere((item) => item.id == employee.id)] = employee.copyWith(serviceIds: ids);
          final key = _serviceConfigKey(employee.id, restored.id);
          final config = _employeeServiceConfigs[key];
          if (config != null) _employeeServiceConfigs[key] = config.copyWith(active: restored.employeeIds.contains(employee.id));
          else if (restored.employeeIds.contains(employee.id)) _employeeServiceConfigs[key] = EmployeeServiceConfig(employeeId: employee.id, serviceId: restored.id);
        }
        break;
      case 'service_deleted':
        final restored = Service.fromJson(Map<String, dynamic>.from(data['service'] as Map));
        if (_services.any((item) => item.id == restored.id)) return false;
        _services.add(restored);
        for (final raw in data['configs'] as List? ?? const []) {
          final config = EmployeeServiceConfig.fromJson(Map<String, dynamic>.from(raw as Map));
          _employeeServiceConfigs[_serviceConfigKey(config.employeeId, config.serviceId)] = config;
        }
        for (final employee in List<Employee>.of(_employees)) {
          if (restored.employeeIds.contains(employee.id) && !employee.serviceIds.contains(restored.id)) {
            _employees[_employees.indexWhere((item) => item.id == employee.id)] = employee.copyWith(serviceIds: [...employee.serviceIds, restored.id]);
          }
        }
        break;
      case 'service_category_restore':
        final name = data['name'] as String;
        if (!_serviceCategories.contains(name)) _serviceCategories.add(name);
        for (final raw in data['services'] as List? ?? const []) {
          final restored = Service.fromJson(Map<String, dynamic>.from(raw as Map));
          final index = _services.indexWhere((item) => item.id == restored.id);
          if (index >= 0) _services[index] = restored;
        }
        _serviceCategories.sort();
        break;
      case 'attendance_payroll_policy_restore':
        _attendancePayrollPolicy = AttendancePayrollPolicy(
          enabled: data['enabled'] as bool? ?? false,
          lateDeductionPerMinute: data['late_deduction_per_minute'] as int? ?? 0,
          absenceDeductionPerDay: data['absence_deduction_per_day'] as int? ?? 0,
          overtimePaymentPerMinute: data['overtime_payment_per_minute'] as int? ?? 0,
          earlyLeaveDeductionPerMinute: data['early_leave_deduction_per_minute'] as int? ?? 0,
        );
        break;
      case 'pay_profile_restore':
        final employeeId = data['employee_id'] as String;
        if (data['had_profile'] == true && data['profile'] != null) {
          final restored = EmployeePayProfile.fromJson(Map<String, dynamic>.from(data['profile'] as Map));
          _employeePayProfiles[employeeId] = restored;
        } else {
          _employeePayProfiles.remove(employeeId);
        }
        break;
      case 'access_role_delete':
        final roleId = data['id'] as String;
        if (_accessAssignments.values.any((assignment) => assignment.roleId == roleId) ||
            _accessAccounts.any((account) => account.roleId == roleId)) return false;
        _accessRoles.remove(roleId);
        break;
      case 'access_role_restore':
        final restored = AccessRole(id: data['id'] as String, name: data['name'] as String,
          permissionIds: (data['permission_ids'] as List? ?? const []).cast<String>(),
          description: data['description'] as String? ?? '', isSystem: data['is_system'] as bool? ?? false);
        _accessRoles[restored.id] = restored;
        break;
      case 'access_assignment_restore':
        final employeeId = data['employee_id'] as String;
        if (data['had_assignment'] == true) {
          _accessAssignments[employeeId] = AccessAssignment(employeeId: employeeId,
            roleId: data['role_id'] as String,
            overrides: Map<String, bool>.from(data['overrides'] as Map? ?? const {}),
            canViewOtherEmployees: data['can_view_other_employees'] as bool? ?? false,
            canViewPersonalIncome: data['can_view_personal_income'] as bool? ?? true);
        } else {
          _accessAssignments.remove(employeeId);
        }
        final previousRoleId = data['account_role_id'] as String? ?? 'staff';
        for (var index = 0; index < _accessAccounts.length; index++) {
          final account = _accessAccounts[index];
          if (account.employeeId == employeeId) _accessAccounts[index] = account.copyWith(roleId: previousRoleId);
        }
        break;
      case 'settings_hours':
        Map<int, List<Shift>> parseShifts(dynamic raw) => (raw as Map? ?? {}).map((k, v) => MapEntry(int.parse(k.toString()), (v as List).map((e) => Shift.fromJson(Map<String, dynamic>.from(e as Map))).toList()));
        final exceptions = (data['schedule_exceptions'] as List? ?? []).map((raw) { final e = Map<String, dynamic>.from(raw as Map); return ScheduleException(dateKey: e['date_key'] as String, title: e['title'] as String? ?? '', isClosed: e['is_closed'] as bool? ?? true, shifts: (e['shifts'] as List? ?? []).map((s) => Shift.fromJson(Map<String, dynamic>.from(s as Map))).toList()); }).toList();
        _settings = _settings.copyWith(workingHours: parseShifts(data['working_hours']), workSchedules: parseShifts(data['work_schedules']), holidays: (data['holidays'] as List? ?? []).cast<int>(), scheduleExceptions: exceptions);
        break;
      default: return false;
    }
    _undoneLogIds.add(id);
    if (entry.idempotencyKey != null) _executedOperationKeys.remove(entry.idempotencyKey);
    log(ActivityType.settingsChanged, 'بازگردانی تغییر', 'تغییر «' + entry.title + '» به حالت قبلی بازگردانده شد.', entity: entry.entityName, entityId: entry.entityId, operationType: 'undo', isReversible: false);
    _commit();
    return true;
  }
  /// شبیه‌سازی تأخیر شبکه برای حالت‌های بارگذاری.
  Future<void> delay([int ms = 260]) => Future<void>.delayed(Duration(milliseconds: ms));
}
