import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/jalali.dart';
import '../models/activity_log.dart';
import '../models/appointment.dart';
import '../models/business_settings.dart';
import '../models/customer.dart';
import '../models/employee.dart';
import '../models/enums.dart';
import '../models/employee_finance.dart';
import '../models/employee_service_config.dart';
import '../models/employee_schedule.dart';
import '../models/service.dart';
import '../models/sms_message.dart';
import 'mock_seed.dart';

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
  final List<EmployeeFinanceEntry> _employeeFinanceEntries = [];
  final Map<String, EmployeeServiceConfig> _employeeServiceConfigs = {};
  final Map<String, EmployeeScheduleException> _employeeScheduleExceptions = {};
  final List<EmployeeLeave> _employeeLeaves = [];
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
  List<EmployeeLeave> get employeeLeaves => List.unmodifiable(_employeeLeaves);
  List<EmployeeScheduleException> get employeeScheduleExceptions => List.unmodifiable(_employeeScheduleExceptions.values);
  EmployeePayProfile payProfileFor(String employeeId) => _employeePayProfiles[employeeId] ?? EmployeePayProfile(employeeId: employeeId);
  BusinessSettings get settings => _settings;

  String nextId(String prefix) => '$prefix-${++_idCounter}';

  void _seed() {
    _customers.addAll(MockSeed.customers());
    _services.addAll(MockSeed.services());
    _employees.addAll(MockSeed.employees());
    for (final employee in _employees) {
      _syncEmployeeServiceLinks(employee);
      for (final serviceId in employee.serviceIds) {
        _employeeServiceConfigs[_serviceConfigKey(employee.id, serviceId)] = EmployeeServiceConfig(employeeId: employee.id, serviceId: serviceId);
      }
    }
    _appointments.addAll(MockSeed.appointments());
    for (var index = 0; index < _employees.length; index++) { final employee = _employees[index]; _employeePayProfiles[employee.id] = EmployeePayProfile(employeeId: employee.id, method: index == 0 ? EmployeePaymentMethod.fixedPlusCommission : EmployeePaymentMethod.commissionOnly, monthlySalary: index == 0 ? 12000000 : 0, generalRateBps: 3000, basis: CommissionBasis.afterDiscount); }
    for (final appointment in _appointments.where((item) => item.status == AppointmentStatus.completed)) { _createCommissionEntries(appointment); }
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
    if (!_employees.any((employee) => employee.id == profile.employeeId)) throw StateError('پرسنل مورد نظر پیدا نشد.');
    if (profile.monthlySalary < 0 || profile.generalRateBps < 0 || profile.generalRateBps > 10000) throw ArgumentError('حقوق یا درصد پورسانت معتبر نیست.');
    for (final rule in profile.rules) { if (rule.rateBps < 0 || rule.rateBps > 10000 || rule.fixedAmount < 0) throw ArgumentError('قانون پورسانت معتبر نیست.'); }
    _employeePayProfiles[profile.employeeId] = profile;
    log(ActivityType.settingsChanged, 'تغییر قرارداد مالی پرسنل', 'قواعد حقوق و پورسانت ذخیره شد.', entity: 'امور مالی پرسنل');
    _commit();
  }
  List<EmployeeFinanceEntry> financeEntriesFor(String employeeId) => _employeeFinanceEntries.where((entry) => entry.employeeId == employeeId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  bool hasCommissionForAppointment(String appointmentId) => _employeeFinanceEntries.any((entry) => entry.appointmentId == appointmentId && entry.type == FinanceEntryType.commission);
  bool finalizeCompletedAppointment(String appointmentId, {int discountAmount = 0, int? finalPaidAmount}) {
    final appointment = appointmentById(appointmentId);
    if (appointment == null || appointment.status != AppointmentStatus.completed || hasCommissionForAppointment(appointmentId)) return false;
    final profile = payProfileFor(appointment.employeeId);
    final grossTotal = appointment.price.round();
    final receivedTotal = finalPaidAmount ?? (grossTotal - discountAmount);
    if (grossTotal < 0 || discountAmount < 0 || discountAmount > grossTotal || receivedTotal < 0 || receivedTotal > grossTotal) throw ArgumentError('مبلغ خدمت، تخفیف یا دریافتی معتبر نیست.');
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
      final commission = switch (profile.method) { EmployeePaymentMethod.fixedMonthly => 0, EmployeePaymentMethod.fixedPerService => fixed, _ => CommissionCalculator.commission(baseAmount: base, rateBps: rate, fixedAmount: fixed) };
      _employeeFinanceEntries.add(EmployeeFinanceEntry(id: nextId('finance'), employeeId: appointment.employeeId, appointmentId: appointment.id, serviceId: serviceId, createdAt: DateTime.now(), type: FinanceEntryType.commission, methodSnapshot: profile.method.name, basisSnapshot: profile.basis.name, grossAmount: gross, discountAmount: discount, receivedAmount: received, calculationBase: base, rateBps: rate, fixedAmount: fixed, commissionAmount: commission, companyShare: received - commission));
    }
    log(ActivityType.appointmentCompleted, 'ثبت پورسانت نوبت', 'سند پورسانت برای نوبت تکمیل‌شده ایجاد شد.', entity: 'دفتر مالی پرسنل');
    _commit();
    return true;
  }
  bool recordCommissionRefund(String entryId, int refundAmount) {
    if (refundAmount <= 0) throw ArgumentError('مبلغ برگشت باید بیشتر از صفر باشد.');
    EmployeeFinanceEntry? original;
    for (final entry in _employeeFinanceEntries) { if (entry.id == entryId && entry.type == FinanceEntryType.commission) { original = entry; break; } }
    if (original == null) return false;
    final refunded = _employeeFinanceEntries.where((entry) => entry.type == FinanceEntryType.refund && entry.reversesEntryId == entryId).fold<int>(0, (sum, entry) => sum - entry.receivedAmount);
    if (refunded + refundAmount > original.receivedAmount) throw ArgumentError('مبلغ برگشت از دریافتی این خدمت بیشتر است.');
    final commissionRefund = original.receivedAmount == 0 ? 0 : (original.commissionAmount * refundAmount + original.receivedAmount ~/ 2) ~/ original.receivedAmount;
    _employeeFinanceEntries.add(EmployeeFinanceEntry(id: nextId('finance'), employeeId: original.employeeId, appointmentId: original.appointmentId, serviceId: original.serviceId, createdAt: DateTime.now(), type: FinanceEntryType.refund, methodSnapshot: original.methodSnapshot, basisSnapshot: original.basisSnapshot, grossAmount: -refundAmount, discountAmount: 0, receivedAmount: -refundAmount, calculationBase: -refundAmount, rateBps: original.rateBps, fixedAmount: 0, commissionAmount: -commissionRefund, companyShare: -(refundAmount - commissionRefund), reversesEntryId: entryId));
    log(ActivityType.settingsChanged, 'ثبت برگشت وجه پورسانت', 'سند اصلاحی برگشت وجه ثبت شد.', entity: 'دفتر مالی پرسنل');
    _commit();
    return true;
  }
  void _createCommissionEntries(Appointment appointment) {
    if (appointment.status != AppointmentStatus.completed || hasCommissionForAppointment(appointment.id)) return;
    final profile = payProfileFor(appointment.employeeId);
    final ids = appointment.serviceIds.isEmpty ? <String>[''] : appointment.serviceIds;
    final total = appointment.price.round();
    for (var index = 0; index < ids.length; index++) {
      final serviceId = ids[index];
      final amount = total ~/ ids.length + (index == 0 ? total % ids.length : 0);
      final service = serviceById(serviceId);
      final rule = profile.ruleFor(serviceId: serviceId, category: service?.category ?? '', date: appointment.startAt);
      final rate = rule?.rateBps ?? profile.generalRateBps;
      final fixed = rule?.fixedAmount ?? 0;
      final commission = profile.method == EmployeePaymentMethod.fixedMonthly ? 0 : profile.method == EmployeePaymentMethod.fixedPerService ? fixed : CommissionCalculator.commission(baseAmount: amount, rateBps: rate, fixedAmount: fixed);
      _employeeFinanceEntries.add(EmployeeFinanceEntry(id: nextId('finance'), employeeId: appointment.employeeId, appointmentId: appointment.id, serviceId: serviceId, createdAt: appointment.updatedAt ?? appointment.startAt, type: FinanceEntryType.commission, methodSnapshot: profile.method.name, basisSnapshot: profile.basis.name, grossAmount: amount, discountAmount: 0, receivedAmount: amount, calculationBase: amount, rateBps: rate, fixedAmount: fixed, commissionAmount: commission, companyShare: amount - commission));
    }
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
    _customers.add(customer);
    log(ActivityType.customerRegistered, 'ثبت مشتری جدید', '${customer.fullName} با شماره ${customer.phone} ثبت شد.', entity: 'مشتری');
    _commit();
  }

  void updateCustomer(Customer customer) {
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index == -1) return;
    _customers[index] = customer;
    log(ActivityType.settingsChanged, 'ویرایش مشتری', 'اطلاعات ${customer.fullName} به‌روزرسانی شد.', entity: 'مشتری');
    _commit();
  }

  void deleteCustomer(String id) {
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
    _services.add(service);
    log(ActivityType.serviceModified, 'افزودن خدمت', 'خدمت «${service.title}» اضافه شد.', entity: 'خدمت');
    _commit();
  }

  void updateService(Service service) {
    final index = _services.indexWhere((s) => s.id == service.id);
    if (index == -1) return;
    _services[index] = service;
    log(ActivityType.serviceModified, 'ویرایش خدمت', 'خدمت «${service.title}» به‌روزرسانی شد.', entity: 'خدمت');
    _commit();
  }

  void deleteService(String id) {
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
    _employees.add(employee);
    _syncEmployeeServiceLinks(employee);
    log(ActivityType.employeeAdded, 'افزودن پرسنل', '${employee.fullName} به تیم اضافه شد.', entity: 'پرسنل');
    _commit();
  }

  void updateEmployee(Employee employee) {
    final index = _employees.indexWhere((e) => e.id == employee.id);
    if (index == -1) return;
    _employees[index] = employee;
    _syncEmployeeServiceLinks(employee);
    log(ActivityType.employeeAdded, 'ویرایش پرسنل', 'پروفایل ${employee.fullName} به‌روزرسانی شد.', entity: 'پرسنل');
    _commit();
  }

  /// در صورت وجود سابقه نوبت، پروفایل بایگانی می‌شود تا ارجاعات تاریخی حفظ شوند.
  void deleteEmployee(String id) {
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

  // برنامه کاری اختصاصی پرسنل، استثناهای تاریخ‌دار و مرخصی
  String _employeeScheduleKey(String employeeId, String dateKey) => employeeId + '::' + dateKey;

  List<EmployeeLeave> leavesForEmployee(String employeeId) =>
      _employeeLeaves.where((leave) => leave.employeeId == employeeId).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));

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
    log(ActivityType.settingsChanged, 'به‌روزرسانی برنامه پرسنل', 'برنامه کاری ' + employee.fullName + ' تغییر کرد.', entity: 'برنامه پرسنل');
    _commit();
  }

  void saveEmployeeScheduleException(EmployeeScheduleException exception) {
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
    _employeeScheduleExceptions.remove(_employeeScheduleKey(employeeId, dateKey));
    _commit();
  }

  void addEmployeeLeave(EmployeeLeave leave) {
    final employee = employeeById(leave.employeeId);
    if (employee == null) throw StateError('پرسنل یافت نشد.');
    if (!leave.endAt.isAfter(leave.startAt)) throw ArgumentError('پایان مرخصی باید بعد از شروع آن باشد.');
    if (_employeeLeaves.any((item) => item.id == leave.id)) throw StateError('شناسه مرخصی تکراری است.');
    if (_employeeLeaves.any((item) => item.employeeId == leave.employeeId && item.status != EmployeeLeaveStatus.rejected && item.startAt.isBefore(leave.endAt) && leave.startAt.isBefore(item.endAt))) {
      throw ArgumentError('این مرخصی با درخواست دیگری هم‌پوشانی دارد.');
    }
    _employeeLeaves.add(leave);
    log(ActivityType.settingsChanged, 'ثبت مرخصی پرسنل', 'مرخصی جدید برای ' + employee.fullName + ' ثبت شد.', entity: 'مرخصی پرسنل');
    _commit();
  }

  void updateEmployeeLeave(EmployeeLeave leave) {
    final index = _employeeLeaves.indexWhere((item) => item.id == leave.id && item.employeeId == leave.employeeId);
    if (index < 0) throw StateError('مرخصی یافت نشد.');
    if (!leave.endAt.isAfter(leave.startAt)) throw ArgumentError('پایان مرخصی باید بعد از شروع آن باشد.');
    if (leave.status == EmployeeLeaveStatus.approved) {
      final conflict = _employeeLeaves.any((item) => item.id != leave.id && item.employeeId == leave.employeeId && item.status == EmployeeLeaveStatus.approved && item.startAt.isBefore(leave.endAt) && leave.startAt.isBefore(item.endAt));
      if (conflict) throw ArgumentError('مرخصی با مرخصی تأییدشده دیگری هم‌پوشانی دارد.');
    }
    _employeeLeaves[index] = leave;
    log(ActivityType.settingsChanged, 'به‌روزرسانی مرخصی پرسنل', 'وضعیت مرخصی ' + leave.id + ' تغییر کرد.', entity: 'مرخصی پرسنل');
    _commit();
  }

  void deleteEmployeeLeave(String id) {
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
    if (_employeeLeaves.any((leave) => leave.employeeId == employeeId && leave.overlaps(startAt, endAt))) return false;
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
    return config == null ? employee.serviceIds.contains(serviceId) && service.employeeIds.contains(employeeId) : config.active;
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
