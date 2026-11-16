import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/jalali.dart';
import '../models/activity_log.dart';
import '../models/appointment.dart';
import '../models/business_settings.dart';
import '../models/customer.dart';
import '../models/employee.dart';
import '../models/enums.dart';
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
  BusinessSettings get settings => _settings;

  String nextId(String prefix) => '$prefix-${++_idCounter}';

  void _seed() {
    _customers.addAll(MockSeed.customers());
    _services.addAll(MockSeed.services());
    _employees.addAll(MockSeed.employees());
    _appointments.addAll(MockSeed.appointments());
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
    _commit();
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
    _services.removeWhere((s) => s.id == id);
    if (service != null) {
      log(ActivityType.serviceModified, 'حذف خدمت', 'خدمت «${service.title}» حذف شد.', entity: 'خدمت');
    }
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
    log(ActivityType.employeeAdded, 'افزودن پرسنل', '${employee.fullName} به تیم اضافه شد.', entity: 'پرسنل');
    _commit();
  }

  void updateEmployee(Employee employee) {
    final index = _employees.indexWhere((e) => e.id == employee.id);
    if (index == -1) return;
    _employees[index] = employee;
    log(ActivityType.employeeAdded, 'ویرایش پرسنل', 'پروفایل ${employee.fullName} به‌روزرسانی شد.', entity: 'پرسنل');
    _commit();
  }

  void deleteEmployee(String id) {
    final employee = employeeById(id);
    _employees.removeWhere((e) => e.id == id);
    if (employee != null) {
      log(ActivityType.employeeAdded, 'حذف پرسنل', '${employee.fullName} حذف شد.', entity: 'پرسنل');
    }
    _commit();
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
    if (target == null || target.undoAction == null || target.undoData == null) return false;
    final targetEntityId = target.undoData!['id'];
    return !_logs.any((other) {
      if (other.id == id || !other.createdAt.isAfter(target.createdAt)) return false;
      if (target.undoAction == 'settings_hours') return other.undoAction == 'settings_hours';
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
