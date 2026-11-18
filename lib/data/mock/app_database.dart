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
  AppDatabase() {
    _seed();
  }

  final List<Customer> _customers = [];
  final List<Appointment> _appointments = [];
  final List<Service> _services = [];
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
  BusinessSettings _settings = const BusinessSettings();

  int _idCounter = 5000;
  final Set<String> _undoneLogIds = {};

  List<Customer> get customers => List.unmodifiable(_customers);
  List<Appointment> get appointments => List.unmodifiable(_appointments);
  List<Service> get services => List.unmodifiable(_services);
  List<Employee> get employees => List.unmodifiable(_employees);
  List<SmsMessage> get smsMessages => List.unmodifiable(_sms);
  List<ActivityLog> get activityLogs => List.unmodifiable(_logs);
  List<SmsTemplate> get smsTemplates => List.unmodifiable(_templates);
  List<EmployeeFinanceEntry> get employeeFinanceEntries => List.unmodifiable(_employeeFinanceEntries);
  List<PayrollAdjustment> get payrollAdjustments => List.unmodifiable(_payrollAdjustments);
  List<PayrollAdvance> get payrollAdvances => List.unmodifiable(_payrollAdvances);
  List<EmployeePerformanceTarget> get performanceTargets => List.unmodifiable(_performanceTargets);
  List<EmployeeWalletTransaction> get employeeWalletTransactions => List.unmodifiable(_employeeWalletTransactions);
  List<EmployeeWalletSettlement> get employeeWalletSettlements => List.unmodifiable(_employeeWalletSettlements);
  List<AppointmentPayment> get appointmentPayments => List.unmodifiable(_appointmentPayments);
  List<BusinessExpense> get businessExpenses => List.unmodifiable(_businessExpenses);
  List<EmployeeLeave> get employeeLeaves => List.unmodifiable(_employeeLeaves);
  List<AttendanceRecord> get attendanceRecords => List.unmodifiable(_attendanceRecords);
  List<EmployeeDocument> get employeeDocuments => List.unmodifiable(_employeeDocuments);
  List<EmployeeNotice> get employeeNotices => List.unmodifiable(_employeeNotices);
  List<AccessRole> get accessRoles => List.unmodifiable(_accessRoles.values);
  List<AccessAccount> get accessAccounts => List.unmodifiable(_accessAccounts);
  AccessAccount get currentAccessAccount => _accessAccounts.firstWhere((account) => account.id == _currentAccessAccountId, orElse: () => _accessAccounts.first);
  String get currentAccessRoleName => _accessRoles[currentAccessAccount.roleId]?.name ?? 'نقش نامشخص';
  List<EmployeeScheduleException> get employeeScheduleExceptions => List.unmodifiable(_employeeScheduleExceptions.values);
  EmployeePayProfile payProfileFor(String employeeId) {
    requirePermission('finance.salary.view', employeeId: employeeId);
    return _employeePayProfiles[employeeId] ?? EmployeePayProfile(employeeId: employeeId);
  }
  BusinessSettings get settings => _settings;

  /// داده‌های نمونه پرداخت و هزینه مجموعه؛ صرفاً برای Datamonck آفلاین.
  void _seedBusinessFinance() {
    var index = 0;
    for (final appointment in _appointments.where((item) => item.status == AppointmentStatus.completed)) {
      final received = _employeeFinanceEntries
          .where((entry) => entry.appointmentId == appointment.id && entry.type == FinanceEntryType.commission)
          .fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      if (received <= 0) continue;
      final methods = BusinessPaymentMethod.values;
      _appointmentPayments.add(AppointmentPayment(
        id: 'payment-seed-${appointment.id}',
        appointmentId: appointment.id,
        customerId: appointment.customerId,
        createdAt: appointment.startAt,
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
    String? idempotencyKey,
  }) {
    requirePermission('finance.payment.create');
    final matches = _appointments.where((item) => item.id == appointmentId).toList();
    if (matches.isEmpty) throw StateError('نوبت مورد نظر پیدا نشد.');
    if (amount <= 0 || description.trim().isEmpty) throw ArgumentError('مبلغ و توضیحات پرداخت معتبر نیست.');
    if (idempotencyKey != null &&
        (idempotencyKey.trim().isEmpty || _appointmentPayments.any((item) => item.idempotencyKey == idempotencyKey))) {
      throw StateError('این پرداخت قبلاً ثبت شده است.');
    }
    final appointment = matches.first;
    final recognized = _employeeFinanceEntries
        .where((entry) => entry.appointmentId == appointmentId)
        .fold<int>(0, (sum, entry) => sum + (entry.type == FinanceEntryType.refund ? entry.receivedAmount : entry.type == FinanceEntryType.commission ? entry.receivedAmount : 0));
    final billable = recognized > 0 ? recognized : appointment.price.round();
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
    log(ActivityType.settingsChanged, 'ثبت دریافت مشتری', 'دریافت مبلغ $amount برای نوبت ${appointment.reference} ثبت شد.', entity: 'دریافت‌های مجموعه');
    _commit();
    return payment;
  }

  AppointmentPayment refundAppointmentPayment({
    required String paymentId,
    required int amount,
    required String description,
    DateTime? createdAt,
    String? idempotencyKey,
  }) {
    requirePermission('finance.payment.create');
    final matches = _appointmentPayments.where((item) => item.id == paymentId && item.type == BusinessPaymentType.receipt).toList();
    if (matches.isEmpty) throw StateError('رسید دریافت پیدا نشد.');
    final original = matches.first;
    if (amount <= 0 || description.trim().isEmpty) throw ArgumentError('مبلغ و توضیحات برگشت معتبر نیست.');
    if (idempotencyKey != null &&
        (idempotencyKey.trim().isEmpty || _appointmentPayments.any((item) => item.idempotencyKey == idempotencyKey))) {
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
      return sum + (entry.receivedAmount - already).clamp(0, entry.receivedAmount);
    });
    var left = amount.clamp(0, refundable);
    var remainingWeight = refundable;
    for (var i = 0; i < originals.length && left > 0; i++) {
      final entry = originals[i];
      final already = _employeeFinanceEntries.where((item) =>
        item.type == FinanceEntryType.refund && item.reversesEntryId == entry.id)
        .fold<int>(0, (value, item) => value - item.receivedAmount);
      final available = (entry.receivedAmount - already).clamp(0, entry.receivedAmount);
      if (available == 0) continue;
      final share = i == originals.length - 1 || remainingWeight <= 0
          ? left
          : (amount * available ~/ remainingWeight).clamp(0, available);
      final allocation = share.clamp(0, available).clamp(0, left);
      if (allocation > 0) {
        recordCommissionRefund(entry.id, allocation);
        left -= allocation;
      }
      remainingWeight -= available;
    }
    log(ActivityType.settingsChanged, 'ثبت برگشت وجه مشتری', 'برگشت مبلغ $amount برای نوبت ثبت شد.', entity: 'دریافت‌های مجموعه');
    _commit();
    return refund;
  }

  void addBusinessExpense(BusinessExpense expense) {
    requirePermission('finance.payment.create');
    if (expense.amount <= 0 || expense.description.trim().isEmpty ||
        expense.sourceDocumentId.trim().isEmpty || expense.createdBy.trim().isEmpty) {
      throw ArgumentError('مبلغ، شرح، سند منبع و ثبت‌کننده هزینه الزامی است.');
    }
    if (_businessExpenses.any((item) => item.id == expense.id || item.sourceDocumentId == expense.sourceDocumentId)) {
      throw StateError('شناسه هزینه یا سند منبع تکراری است.');
    }
    _businessExpenses.add(expense);
    log(ActivityType.settingsChanged, 'ثبت هزینه مجموعه', 'هزینه ${expense.category.label} با سند ${expense.sourceDocumentId} ثبت شد.', entity: 'امور مالی مجموعه');
    _commit();
  }

  String nextId(String prefix) => '$prefix-${++_idCounter}';

  void _seed() {
    _customers.addAll(MockSeed.customers());
    _services.addAll(MockSeed.services());
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
    _seedWalletHistory();
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
  void log(ActivityType type, String title, String description, {String actor = 'مدیر سیستم', String entity = '', String? undoAction, Map<String, dynamic>? undoData}) {
    _logs.insert(
      0,
      ActivityLog(
        id: nextId('log'),
        type: type,
        title: title,
        description: description,
        actor: actor,
        createdAt: DateTime.now(),
        entityName: entity,
        undoAction: undoAction,
        undoData: undoData,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // کنترل دسترسی و نقش‌ها — منبع حقیقت در لایه داده
  // ---------------------------------------------------------------------------
  void _seedAccessControl() {
    for (final role in AccessRole.defaults()) { _accessRoles[role.id] = role; }
    final custom = AccessRole(
      id: 'custom_limited', name: 'نقش سفارشی محدود',
      permissionIds: const ['appointments.view_self', 'customers.view'],
      description: 'نقش نمونه برای بررسی دسترسی محدود',
    );
    _accessRoles[custom.id] = custom;
    _accessAccounts.addAll(const [
      AccessAccount(id: 'demo-global-admin', name: 'فاطمه رضایی — مدیر کل', roleId: 'global_admin', employeeId: 'emp-fateme'),
      AccessAccount(id: 'demo-manager', name: 'مدیر مجموعه آزمایشی', roleId: 'manager', employeeId: 'emp-shima'),
      AccessAccount(id: 'demo-operator', name: 'نیما احمدی — اپراتور', roleId: 'operator', employeeId: 'emp-nima'),
      AccessAccount(id: 'demo-staff', name: 'زهرا نوری — پرسنل', roleId: 'staff', employeeId: 'emp-zahra'),
      AccessAccount(id: 'demo-accountant', name: 'الهه یاری — حسابدار', roleId: 'accountant', employeeId: 'emp-elham'),
      AccessAccount(id: 'demo-custom', name: 'امیر کاظمی — نقش سفارشی', roleId: 'custom_limited', employeeId: 'emp-amir'),
    ]);
    for (final account in _accessAccounts.where((item) => item.employeeId != null)) {
      _accessAssignments[account.employeeId!] = AccessAssignment(
        employeeId: account.employeeId!,
        roleId: account.roleId,
        canViewOtherEmployees: account.roleId == 'global_admin' || account.roleId == 'manager' || account.roleId == 'operator' || account.roleId == 'accountant',
        canViewPersonalIncome: account.roleId != 'custom_limited',
      );
    }
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
    if (override != null) return override;
    final roleId = assignment?.roleId ?? account.roleId;
    final allowed = _accessRoles[roleId]?.permissionIds.contains(permissionId) ?? false;
    if (!allowed) return false;
    if (permissionId.startsWith('finance.') && employeeId != null) {
      return canViewEmployee(employeeId) && (employeeId != subjectId || (assignment?.canViewPersonalIncome ?? true));
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
    if (!hasPermission(permissionId, employeeId: employeeId)) {
      final matches = AccessPermission.all.where((item) => item.id == permissionId).toList();
      throw AccessDeniedException('برای انجام این عملیات دسترسی «${matches.isEmpty ? permissionId : matches.first.label}» را ندارید.');
    }
  }

  bool canOpenRoute(String path) {
    if (path == '/book' || path.startsWith('/book/')) return true;
    if (path == '/dashboard' || path == '/access-denied') return true;
    if (path.startsWith('/settings/permissions')) return hasPermission('permissions.manage');
    if (path.startsWith('/settings/hours')) return hasPermission('settings.hours.edit');
    if (path.startsWith('/settings')) return hasPermission('settings.view') || hasPermission('permissions.manage');
    if (path.startsWith('/employees')) {
      final parts = path.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.length == 1) return hasPermission('employees.view_list');
      if (parts.length == 2 && parts[1] == 'new') return hasPermission('employees.create');
      final employeeId = parts.length > 1 ? parts[1] : '';
      if (parts.contains('wallet')) return canViewEmployeeIncome(employeeId) && hasPermission('finance.salary.view', employeeId: employeeId);
      if (parts.contains('finance')) return canViewEmployeeIncome(employeeId) && hasPermission('finance.salary.view', employeeId: employeeId);
      if (parts.contains('analytics')) return canViewEmployeeIncome(employeeId);
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
    if (path.startsWith('/reports')) return hasPermission('finance.income.view') || hasPermission('finance.salary.view');
    if (path.startsWith('/activity') || path.startsWith('/sms')) return hasPermission('settings.view');
    return true;
  }

  bool canOpenNavigation(String path) {
    if (path == '/dashboard') return true;
    if (path == '/appointments' || path == '/calendar') return hasPermission('appointments.view_all') || hasPermission('appointments.view_self');
    if (path == '/customers') return hasPermission('customers.view');
    if (path == '/services') return hasPermission('services.manage');
    if (path == '/employees') return hasPermission('employees.view_list');
    if (path == '/reports') return hasPermission('finance.income.view') || hasPermission('finance.salary.view');
    if (path == '/activity' || path == '/sms') return hasPermission('settings.view');
    if (path == '/settings') return hasPermission('settings.view') || hasPermission('permissions.manage');
    return false;
  }

  void createAccessRole({required String name, required List<String> permissionIds}) {
    requirePermission('permissions.manage');
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError('نام نقش الزامی است.');
    if (_accessRoles.values.any((role) => role.name == normalized)) throw StateError('نقشی با این نام وجود دارد.');
    final id = 'custom-${DateTime.now().microsecondsSinceEpoch}';
    _accessRoles[id] = AccessRole(id: id, name: normalized, permissionIds: List.unmodifiable(permissionIds.where(AccessPermission.ids.contains)));
    _commit();
  }

  void updateAccessRole(String roleId, {required String name, required List<String> permissionIds}) {
    requirePermission('permissions.manage');
    final current = _accessRoles[roleId];
    if (current == null || current.isSystem) throw StateError('نقش سیستمی قابل ویرایش نیست.');
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError('نام نقش الزامی است.');
    _accessRoles[roleId] = current.copyWith(name: normalized, permissionIds: permissionIds.where(AccessPermission.ids.contains).toList());
    _commit();
  }

  void resetAccessRole(String roleId) {
    requirePermission('permissions.manage');
    final defaults = {for (final role in AccessRole.defaults()) role.id: role};
    final original = defaults[roleId];
    if (original == null) throw StateError('نقش پیش‌فرض پیدا نشد.');
    _accessRoles[roleId] = original;
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
    if (!_accessRoles.containsKey(roleId)) throw StateError('نقش انتخاب‌شده پیدا نشد.');
    if (roleId == 'global_admin' && currentAccessAccount.roleId != 'global_admin') {
      throw AccessDeniedException('فقط مدیر کل می‌تواند نقش مدیر کل را اختصاص دهد.');
    }
    _accessAssignments[employeeId] = AccessAssignment(
      employeeId: employeeId, roleId: roleId,
      overrides: Map.unmodifiable(Map.fromEntries(overrides.entries.where((entry) => AccessPermission.ids.contains(entry.key)))),
      canViewOtherEmployees: canViewOtherEmployees,
      canViewPersonalIncome: canViewPersonalIncome,
    );
    for (var index = 0; index < _accessAccounts.length; index++) {
      final account = _accessAccounts[index];
      if (account.employeeId == employeeId) _accessAccounts[index] = account.copyWith(roleId: roleId);
    }
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
      if (a.id == id) return a;
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

  void addAppointment(Appointment appointment, {String actor = 'پذیرش'}) {
    requirePermission('appointments.create');
    _appointments.add(appointment);
    log(
      ActivityType.appointmentCreated,
      'ثبت نوبت جدید',
      'نوبت ${appointment.serviceName} برای ${appointment.customerName} در ${appointment.jalali.long} ساعت ${appointment.startAt.hour.toString().padLeft(2, '0')}:${appointment.startAt.minute.toString().padLeft(2, '0')} ثبت شد.',
      actor: actor,
      entity: 'نوبت',
      undoAction: 'appointment_created',
      undoData: appointment.toJson(),
    );
    _commit();
  }

  void updateAppointment(Appointment appointment, {String actor = 'پذیرش'}) {
    requirePermission('appointments.edit');
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
    );
    _commit();
  }

  void changeStatus(Appointment appointment, AppointmentStatus status, {String? reason, String actor = 'پذیرش'}) {
    requirePermission(status == AppointmentStatus.cancelled ? 'appointments.cancel' : status == AppointmentStatus.completed ? 'appointments.complete' : 'appointments.edit');
    final index = _appointments.indexWhere((a) => a.id == appointment.id);
    if (index == -1) return;
    final previous = _appointments[index];
    _appointments[index] = appointment.copyWith(status: status, cancelReason: reason, updatedAt: DateTime.now());
    final type = switch (status) {
      AppointmentStatus.cancelled => ActivityType.appointmentCancelled,
      AppointmentStatus.completed => ActivityType.appointmentCompleted,
      _ => ActivityType.appointmentUpdated,
    };
    log(
      type,
      status == AppointmentStatus.cancelled ? 'لغو نوبت' : 'تغییر وضعیت نوبت',
      'وضعیت نوبت ${appointment.customerName} به «${status.label}» تغییر کرد.${reason != null ? ' دلیل: $reason' : ''}',
      actor: actor,
      entity: 'نوبت',
      undoAction: 'appointment_restore',
      undoData: previous.toJson(),
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
    _employeePayProfiles[profile.employeeId] = profile;
    log(ActivityType.settingsChanged, 'تغییر قرارداد مالی پرسنل', 'قواعد حقوق و پورسانت ذخیره شد.', entity: 'امور مالی پرسنل');
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
    log(ActivityType.settingsChanged, 'ثبت سابقه حقوق ثابت', 'قرارداد حقوق ثابت جدید ثبت شد.', entity: 'حقوق پرسنل');
    _commit();
  }

  void addPayrollAdjustment(PayrollAdjustment adjustment) {
    requirePermission('finance.payment.create');
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
      );
      _employeeWalletTransactions.add(walletEntry);
      _payrollAdjustments[_payrollAdjustments.length - 1] = PayrollAdjustment(
        id: adjustment.id, employeeId: adjustment.employeeId, amount: adjustment.amount,
        date: adjustment.date, description: adjustment.description, createdBy: adjustment.createdBy,
        status: adjustment.status, bonusType: adjustment.bonusType, deductionType: adjustment.deductionType,
        relatedAdvanceId: adjustment.relatedAdvanceId, sourceWalletTransactionId: walletEntry.id,
      );
    }
    log(ActivityType.settingsChanged, 'ثبت آیتم حقوق', 'پاداش یا کسورات پرسنل ثبت شد.', entity: 'حقوق پرسنل');
    _commit();
  }

  void addPayrollAdvance(PayrollAdvance advance) {
    requirePermission('finance.advance.create');
    if (!_employees.any((item) => item.id == advance.employeeId)) throw StateError('پرسنل پیدا نشد.');
    if (advance.amount <= 0 || advance.description.trim().isEmpty) throw ArgumentError('مبلغ و توضیحات مساعده الزامی است.');
    if (_payrollAdvances.any((item) => item.id == advance.id)) throw StateError('شناسه مساعده تکراری است.');
    var savedAdvance = advance;
    if (advance.status == AdvanceStatus.paid && advance.sourceWalletTransactionId == null) {
      final walletEntry = EmployeeWalletTransaction(
        id: nextId('wallet'), employeeId: advance.employeeId, createdAt: advance.paidAt ?? DateTime.now(),
        amount: -advance.amount, type: EmployeeWalletTransactionType.advance,
        description: advance.description, idempotencyKey: 'payroll-advance-${advance.id}',
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
    for (var index = 0; index < _employees.length && index < 5; index++) {
      final employee = _employees[index];
      _salaryContracts[employee.id] = [SalaryContract(
        id: 'salary-seed-${employee.id}', employeeId: employee.id,
        monthlyBase: index == 0 ? 18000000 : 8000000 + index * 1000000,
        effectiveFrom: DateTime(now.year, now.month, 1), period: SalaryPeriod.monthly,
      )];
      _payrollAdjustments.add(PayrollAdjustment(
        id: 'bonus-seed-${employee.id}', employeeId: employee.id, amount: 500000 + index * 100000,
        date: now, description: 'پاداش عملکرد آزمایشی', createdBy: 'مدیر سیستم',
        status: PayrollRecordStatus.approved, bonusType: PayrollBonusType.performance,
      ));
      if (index.isOdd) {
        _payrollAdjustments.add(PayrollAdjustment(
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
      final rate = (snapshot?['commission_rate_bps'] as num?)?.toInt() ?? rule?.rateBps ?? profile.generalRateBps;
      final fixed = (snapshot?['fixed_commission_amount'] as num?)?.toInt() ?? rule?.fixedAmount ?? 0;
      final basisKey = snapshot?['commission_basis'] as String?;
      var basis = profile.basis;
      for (final item in CommissionBasis.values) {
        if (item.name == basisKey) { basis = item; break; }
      }
      final base = CommissionCalculator.base(basis: basis, grossAmount: gross, discountAmount: discount, receivedAmount: received);
      final calculatedCommission = switch (profile.method) { EmployeePaymentMethod.fixedMonthly => 0, EmployeePaymentMethod.fixedPerService => fixed, _ => CommissionCalculator.commission(baseAmount: base, rateBps: rate, fixedAmount: fixed) };
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
    log(ActivityType.settingsChanged, 'ثبت برگشت وجه پورسانت', 'سند اصلاحی برگشت وجه ثبت شد.', entity: 'دفتر مالی پرسنل');
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
    requirePermission('finance.salary.view', employeeId: employeeId);
    return _employeeWalletTransactions.where((entry) {
        if (entry.employeeId != employeeId) return false;
        if (from != null && entry.createdAt.isBefore(from)) return false;
        if (to != null && entry.createdAt.isAfter(to)) return false;
        return true;
      }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<EmployeeWalletSettlement> walletSettlementsFor(String employeeId) {
    requirePermission('finance.settlement.view', employeeId: employeeId);
    return _employeeWalletSettlements.where((entry) => entry.employeeId == employeeId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  EmployeeWalletSummary walletSummaryFor(String employeeId) =>
      EmployeeWalletSummary.fromTransactions(walletTransactionsFor(employeeId));

  int walletBalanceFor(String employeeId) => walletSummaryFor(employeeId).balance;

  /// ثبت حقوق پایه و اثر حضور و غیاب در دفتر کل، بدون تکرار برای ماه جاری.
  int accruePayrollBaseToWallet(String employeeId, {DateTime? at}) {
    requirePermission('finance.payment.create', employeeId: employeeId);
    final date = at ?? DateTime.now();
    final payroll = payrollFor(employeeId, at: date);
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
        idempotencyKey: attendanceKey,
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
  }) {
    requirePermission(type == EmployeeWalletTransactionType.advance ? 'finance.advance.create' : 'finance.payment.create');
    if (!_employees.any((employee) => employee.id == employeeId)) throw StateError('پرسنل مورد نظر پیدا نشد.');
    if (amount == 0) throw ArgumentError('مبلغ تراکنش نمی‌تواند صفر باشد.');
    if (description.trim().isEmpty) throw ArgumentError('توضیحات تراکنش الزامی است.');
    final creditOnly = type == EmployeeWalletTransactionType.fixedSalary || type == EmployeeWalletTransactionType.bonus || type == EmployeeWalletTransactionType.commission;
    final debitOnly = type == EmployeeWalletTransactionType.advance || type == EmployeeWalletTransactionType.penalty || type == EmployeeWalletTransactionType.deduction || type == EmployeeWalletTransactionType.refund || type == EmployeeWalletTransactionType.salaryPayment;
    if ((creditOnly && amount < 0) || (debitOnly && amount > 0)) throw ArgumentError('جهت مبلغ با نوع تراکنش هم‌خوانی ندارد.');
    if (idempotencyKey != null && (idempotencyKey.trim().isEmpty || _employeeWalletTransactions.any((entry) => entry.idempotencyKey == idempotencyKey))) {
      throw StateError('این عملیات مالی قبلاً ثبت شده است.');
    }
    final entry = EmployeeWalletTransaction(
      id: nextId('wallet'),
      employeeId: employeeId,
      createdAt: createdAt ?? DateTime.now(),
      amount: amount,
      type: type,
      description: description.trim(),
      idempotencyKey: idempotencyKey,
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
    log(ActivityType.settingsChanged, 'ثبت تراکنش کیف پول', 'تراکنش «${type.label}» برای پرسنل ثبت شد.', entity: 'کیف پول پرسنل');
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
    );
    final correction = EmployeeWalletTransaction(
      id: nextId('wallet'),
      employeeId: original.employeeId,
      createdAt: DateTime.now(),
      amount: correctedAmount,
      type: EmployeeWalletTransactionType.adjustment,
      description: description.trim(),
      reversalOfId: original.id,
    );
    _employeeWalletTransactions.addAll([reversal, correction]);
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
    log(ActivityType.settingsChanged, 'اصلاح سند مالی', 'تراکنش ${original.id} با سند معکوس و اصلاحیه جایگزین شد.', entity: 'کیف پول پرسنل');
    _commit();
    return [reversal, correction];
  }

  EmployeeWalletSettlement settleEmployeeWallet({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required EmployeeWalletPeriodType periodType,
    required int paidAmount,
    required String idempotencyKey,
  }) {
    requirePermission('finance.payment.create', employeeId: employeeId);
    if (!_employees.any((employee) => employee.id == employeeId)) throw StateError('پرسنل مورد نظر پیدا نشد.');
    if (periodEnd.isBefore(periodStart)) throw ArgumentError('بازه تسویه معتبر نیست.');
    if (paidAmount <= 0) throw ArgumentError('مبلغ پرداخت باید بیشتر از صفر باشد.');
    if (idempotencyKey.trim().isEmpty || _employeeWalletTransactions.any((entry) => entry.idempotencyKey == idempotencyKey)) {
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
    );
    _employeeWalletSettlements.add(settlement);
    _employeeWalletTransactions.add(EmployeeWalletTransaction(
      id: nextId('wallet'),
      employeeId: employeeId,
      createdAt: now,
      amount: -paidAmount,
      type: EmployeeWalletTransactionType.salaryPayment,
      description: 'پرداخت تسویه ${settlement.receiptNumber}',
      settlementId: settlementId,
      idempotencyKey: idempotencyKey,
    ));
    log(ActivityType.settingsChanged, 'ثبت تسویه پرسنل', 'پرداخت ${paidAmount} تومان برای تسویه پرسنل ثبت شد.', entity: 'تسویه حساب');
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
    ));
  }

  void _seedWalletHistory() {
    final now = DateTime.now();
    final examples = <(String, EmployeeWalletTransactionType, int, int, String)>[
      ('emp-fateme', EmployeeWalletTransactionType.fixedSalary, 12000000, 2, 'حقوق ثابت ماهانه'),
      ('emp-fateme', EmployeeWalletTransactionType.advance, -2000000, 12, 'مساعده پرسنل'),
      ('emp-fateme', EmployeeWalletTransactionType.bonus, 1500000, 8, 'پاداش عملکرد'),
      ('emp-shima', EmployeeWalletTransactionType.fixedSalary, 9000000, 2, 'حقوق ثابت ماهانه'),
      ('emp-shima', EmployeeWalletTransactionType.advance, -1000000, 10, 'مساعده علی‌الحساب'),
      ('emp-shima', EmployeeWalletTransactionType.deduction, -350000, 6, 'کسورات توافق‌شده'),
      ('emp-zahra', EmployeeWalletTransactionType.fixedSalary, 8500000, 2, 'حقوق ثابت ماهانه'),
      ('emp-zahra', EmployeeWalletTransactionType.bonus, 700000, 7, 'پاداش رضایت مشتری'),
      ('emp-elham', EmployeeWalletTransactionType.fixedSalary, 10000000, 2, 'حقوق ثابت ماهانه'),
      ('emp-elham', EmployeeWalletTransactionType.penalty, -250000, 5, 'جریمه ثبت آزمایشی'),
      ('emp-amir', EmployeeWalletTransactionType.fixedSalary, 11000000, 2, 'حقوق ثابت ماهانه'),
      ('emp-amir', EmployeeWalletTransactionType.advance, -1500000, 4, 'مساعده'),
    ];
    for (var index = 0; index < examples.length; index++) {
      final item = examples[index];
      if (!_employees.any((employee) => employee.id == item.$1)) continue;
      _employeeWalletTransactions.add(EmployeeWalletTransaction(
        id: 'wallet-seed-${index + 1}',
        employeeId: item.$1,
        createdAt: now.subtract(Duration(days: item.$4)),
        amount: item.$3,
        type: item.$2,
        description: item.$5,
      ));
    }
    final periodStart = DateTime(now.year, now.month, 1);
    final periodEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    int periodCreditsAndDebits(String employeeId) => _employeeWalletTransactions.where((entry) =>
      entry.employeeId == employeeId &&
      entry.status == EmployeeWalletTransactionStatus.posted &&
      entry.type != EmployeeWalletTransactionType.salaryPayment &&
      !entry.createdAt.isBefore(periodStart) &&
      !entry.createdAt.isAfter(periodEnd),
    ).fold<int>(0, (sum, entry) => sum + entry.amount);
    final fatemeDue = periodCreditsAndDebits('emp-fateme');
    final zahraDue = periodCreditsAndDebits('emp-zahra');
    const paid = 4000000;
    const settlementId = 'settlement-seed-fateme';
    _employeeWalletSettlements.add(EmployeeWalletSettlement(
      id: settlementId,
      employeeId: 'emp-fateme',
      periodType: EmployeeWalletPeriodType.monthly,
      periodStart: periodStart,
      periodEnd: periodEnd,
      dueAmount: fatemeDue,
      paidAmount: paid,
      remainingAfter: fatemeDue - paid,
      createdAt: now.subtract(const Duration(days: 2)),
      status: EmployeeWalletSettlementStatus.partial,
      receiptNumber: 'RC-MOCK-0001',
    ));
    _employeeWalletTransactions.add(EmployeeWalletTransaction(
      id: 'wallet-seed-payment-1',
      employeeId: 'emp-fateme',
      createdAt: now.subtract(const Duration(days: 2)),
      amount: -paid,
      type: EmployeeWalletTransactionType.salaryPayment,
      description: 'پرداخت علی‌الحساب حقوق — رسید RC-MOCK-0001',
      settlementId: settlementId,
    ));

    const fullSettlementId = 'settlement-seed-zahra';
    _employeeWalletSettlements.add(EmployeeWalletSettlement(
      id: fullSettlementId,
      employeeId: 'emp-zahra',
      periodType: EmployeeWalletPeriodType.monthly,
      periodStart: periodStart,
      periodEnd: periodEnd,
      dueAmount: zahraDue,
      paidAmount: zahraDue,
      remainingAfter: 0,
      createdAt: now.subtract(const Duration(days: 1)),
      status: EmployeeWalletSettlementStatus.completed,
      receiptNumber: 'RC-MOCK-0002',
    ));
    _employeeWalletTransactions.add(EmployeeWalletTransaction(
      id: 'wallet-seed-payment-2',
      employeeId: 'emp-zahra',
      createdAt: now.subtract(const Duration(days: 1)),
      amount: -zahraDue,
      type: EmployeeWalletTransactionType.salaryPayment,
      description: 'تسویه کامل حقوق و پاداش — رسید RC-MOCK-0002',
      settlementId: fullSettlementId,
    ));
  }

  void reschedule(Appointment appointment, DateTime newStart, {String actor = 'پذیرش', bool byCustomer = false}) {
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
      undoAction: 'appointment_restore',
      undoData: previous.toJson(),
    );
    _commit();
  }

  void deleteAppointment(String id) {
    requirePermission('appointments.cancel');
    final appointment = appointmentById(id);
    _appointments.removeWhere((a) => a.id == id);
    if (appointment != null) {
      log(ActivityType.appointmentCancelled, 'حذف نوبت', 'نوبت ${appointment.customerName} حذف شد.', entity: 'نوبت', undoAction: 'appointment_deleted', undoData: appointment.toJson());
    }
    _commit();
  }

  // ---------------------------------------------------------------------------
  // مشتریان
  // ---------------------------------------------------------------------------
  Customer? customerById(String id) {
    for (final c in _customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  void addCustomer(Customer customer) {
    requirePermission('customers.create');
    _customers.add(customer);
    log(ActivityType.customerRegistered, 'ثبت مشتری جدید', '${customer.fullName} با شماره ${customer.phone} ثبت شد.', entity: 'مشتری');
    _commit();
  }

  void updateCustomer(Customer customer) {
    requirePermission('customers.edit');
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index == -1) return;
    _customers[index] = customer;
    log(ActivityType.settingsChanged, 'ویرایش مشتری', 'اطلاعات ${customer.fullName} به‌روزرسانی شد.', entity: 'مشتری');
    _commit();
  }

  void deleteCustomer(String id) {
    requirePermission('customers.edit');
    final customer = customerById(id);
    _customers.removeWhere((c) => c.id == id);
    if (customer != null) {
      log(ActivityType.settingsChanged, 'حذف مشتری', '${customer.fullName} از فهرست مشتریان حذف شد.', entity: 'مشتری');
    }
    _commit();
  }

  // ---------------------------------------------------------------------------
  // خدمات
  // ---------------------------------------------------------------------------
  Service? serviceById(String id) {
    for (final s in _services) {
      if (s.id == id) return s;
    }
    return null;
  }

  void addService(Service service) {
    requirePermission('services.manage');
    _services.add(service);
    log(ActivityType.serviceModified, 'افزودن خدمت', 'خدمت «${service.title}» اضافه شد.', entity: 'خدمت');
    _commit();
  }

  void updateService(Service service) {
    requirePermission('services.manage');
    final index = _services.indexWhere((s) => s.id == service.id);
    if (index == -1) return;
    final validEmployeeIds = service.employeeIds.where((id) => _employees.any((employee) => employee.id == id)).toSet();
    _services[index] = service.copyWith(employeeIds: validEmployeeIds.toList());
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
    log(ActivityType.serviceModified, 'ویرایش خدمت', 'خدمت «${service.title}» به‌روزرسانی شد.', entity: 'خدمت');
    _commit();
  }

  void deleteService(String id) {
    requirePermission('services.manage');
    final service = serviceById(id);
    if (service == null) return;
    final hasHistory = _appointments.any((appointment) => appointment.serviceIds.contains(id));
    if (hasHistory) {
      updateService(service.copyWith(isActive: false, employeeIds: const []));
      log(ActivityType.serviceModified, 'بایگانی خدمت', 'خدمت «${service.title}» به دلیل وجود سابقه نوبت غیرفعال شد؛ سوابق حفظ شدند.', entity: 'خدمت');
      return;
    }
    _services.removeWhere((item) => item.id == id);
    _employeeServiceConfigs.removeWhere((key, value) => value.serviceId == id);
    for (var index = 0; index < _employees.length; index++) {
      final employee = _employees[index];
      if (employee.serviceIds.contains(id)) {
        _employees[index] = employee.copyWith(serviceIds: employee.serviceIds.where((serviceId) => serviceId != id).toList());
      }
    }
    log(ActivityType.serviceModified, 'حذف خدمت', 'خدمت «${service.title}» حذف شد.', entity: 'خدمت');
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
    for (final e in _employees) {
      if (e.id == id) return e;
    }
    return null;
  }

  void addEmployee(Employee employee) {
    requirePermission('employees.create');
    _employees.add(employee);
    _syncEmployeeServiceLinks(employee);
    log(ActivityType.employeeAdded, 'افزودن پرسنل', '${employee.fullName} به تیم اضافه شد.', entity: 'پرسنل');
    _commit();
  }

  void updateEmployee(Employee employee) {
    requirePermission('employees.edit');
    final index = _employees.indexWhere((e) => e.id == employee.id);
    if (index == -1) return;
    _employees[index] = employee;
    _syncEmployeeServiceLinks(employee);
    log(ActivityType.employeeAdded, 'ویرایش پرسنل', 'پروفایل ${employee.fullName} به‌روزرسانی شد.', entity: 'پرسنل');
    _commit();
  }

  /// در صورت وجود سابقه نوبت، پروفایل بایگانی می‌شود تا ارجاعات تاریخی حفظ شوند.
  void deleteEmployee(String id) {
    requirePermission('employees.deactivate');
    final employee = employeeById(id);
    if (employee == null) return;
    final hasHistory = _appointments.any((appointment) => appointment.employeeId == id);
    if (hasHistory) {
      final archived = employee.copyWith(isActive: false, status: EmployeeStatus.inactive);
      updateEmployee(archived);
      log(ActivityType.employeeAdded, 'بایگانی پرسنل', 'پروفایل ${employee.fullName} به دلیل وجود سوابق نوبت بایگانی شد.', entity: 'پرسنل');
      _commit();
      return;
    }
    _employees.removeWhere((item) => item.id == id);
    for (var index = 0; index < _services.length; index++) {
      final service = _services[index];
      if (service.employeeIds.contains(id)) {
        _services[index] = service.copyWith(employeeIds: service.employeeIds.where((employeeId) => employeeId != id).toList());
      }
    }
    log(ActivityType.employeeAdded, 'حذف پرسنل', '${employee.fullName} حذف شد.', entity: 'پرسنل');
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

  void saveAttendancePayrollPolicy(AttendancePayrollPolicy policy) {
    requirePermission('employees.edit');
    if (policy.lateDeductionPerMinute < 0 || policy.absenceDeductionPerDay < 0 || policy.overtimePaymentPerMinute < 0 || policy.earlyLeaveDeductionPerMinute < 0) {
      throw ArgumentError('مقادیر قانون مالی نمی‌توانند منفی باشند.');
    }
    _attendancePayrollPolicy = policy;
    _commit();
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
    if (currentAccessAccount.employeeId != leave.employeeId) requirePermission('employees.edit', employeeId: leave.employeeId);
    if (!leave.endAt.isAfter(leave.startAt)) throw ArgumentError('پایان مرخصی باید بعد از شروع آن باشد.');
    if (_employeeLeaves.any((item) => item.id == leave.id)) throw StateError('شناسه مرخصی تکراری است.');
    if (_employeeLeaves.any((item) => item.employeeId == leave.employeeId && item.status != EmployeeLeaveStatus.rejected && item.startAt.isBefore(leave.endAt) && leave.startAt.isBefore(item.endAt))) {
      throw ArgumentError('این مرخصی با درخواست دیگری هم‌پوشانی دارد.');
    }
    _employeeLeaves.add(leave);
    _notifyEmployee(leave.employeeId,EmployeeNoticeType.leaveRequested,'درخواست مرخصی ثبت شد.','درخواست مرخصی شما در انتظار بررسی است.');
    for(final manager in _accessAccounts.where((account)=>account.isEnabled && account.employeeId!=null && (account.roleId=='global_admin'||account.roleId=='manager'))){
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
    requirePermission('employees.edit', employeeId: config.employeeId);
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
    log(ActivityType.serviceModified, 'تنظیم خدمت پرسنل', 'تنظیم خدمت «\${service.title}» برای \${employee.fullName} ذخیره شد.', entity: 'پرسنل و خدمات');
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
    if (resolvedTarget == null || resolvedTarget.undoAction == null || resolvedTarget.undoData == null) return false;
    final targetEntityId = resolvedTarget.undoData!['id'];
    return !_logs.any((other) {
      if (other.id == id || !other.createdAt.isAfter(resolvedTarget.createdAt)) return false;
      if (resolvedTarget.undoAction == 'settings_hours') return other.undoAction == 'settings_hours';
      return targetEntityId != null && other.undoData?['id'] == targetEntityId;
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
      case 'settings_hours':
        Map<int, List<Shift>> parseShifts(dynamic raw) => (raw as Map? ?? {}).map((k, v) => MapEntry(int.parse(k.toString()), (v as List).map((e) => Shift.fromJson(Map<String, dynamic>.from(e as Map))).toList()));
        final exceptions = (data['schedule_exceptions'] as List? ?? []).map((raw) { final e = Map<String, dynamic>.from(raw as Map); return ScheduleException(dateKey: e['date_key'] as String, title: e['title'] as String? ?? '', isClosed: e['is_closed'] as bool? ?? true, shifts: (e['shifts'] as List? ?? []).map((s) => Shift.fromJson(Map<String, dynamic>.from(s as Map))).toList()); }).toList();
        _settings = _settings.copyWith(workingHours: parseShifts(data['working_hours']), workSchedules: parseShifts(data['work_schedules']), holidays: (data['holidays'] as List? ?? []).cast<int>(), scheduleExceptions: exceptions);
        break;
      default: return false;
    }
    _undoneLogIds.add(id);
    log(ActivityType.settingsChanged, 'بازگردانی تغییر', 'تغییر «' + entry.title + '» به حالت قبلی بازگردانده شد.', actor: 'مدیر سیستم', entity: entry.entityName);
    _commit();
    return true;
  }
  /// شبیه‌سازی تأخیر شبکه برای حالت‌های بارگذاری.
  Future<void> delay([int ms = 260]) => Future<void>.delayed(Duration(milliseconds: ms));
}
