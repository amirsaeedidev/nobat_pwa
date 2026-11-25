import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/business_settings.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/employee_schedule.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/service.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/repositories/appointment_repository.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/service_repository.dart';

/// حالت نمایش تقویم.
enum CalendarView { daily, weekly, monthly }

/// تقویم کاملاً متصل به Repositoryهای Supabase؛ هیچ وابستگی به AppDatabase ندارد.
class CalendarProvider extends ChangeNotifier {
  CalendarProvider(
    this._appointments,
    this._employees,
    this._services, {
    this.settingsRepository,
    this.authStateNotifier,
  }) {
    _today = JalaliDate.today();
    _anchor = _today;
    _selected = _today;
    authStateNotifier?.addListener(_handleAuthChange);
    if (authStateNotifier == null || authStateNotifier!.hasActiveBusiness) {
      unawaited(load());
    } else {
      _loading = false;
    }
  }

  final AppointmentRepository _appointments;
  final EmployeeRepository _employees;
  final ServiceRepository _services;
  final SettingsRepository? settingsRepository;
  final SupabaseAuthStateNotifier? authStateNotifier;

  late JalaliDate _today;
  late JalaliDate _anchor;
  late JalaliDate _selected;
  CalendarView _view = CalendarView.monthly;
  String? _employeeId;
  String? _serviceId;
  AppointmentStatus? _statusFilter;
  bool _loading = true;
  String? _error;
  List<Appointment> _rangeAppointments = const [];
  List<Employee> _employeeList = const [];
  List<Service> _serviceList = const [];
  List<EmployeeWorkingHour> _workingHours = const [];
  List<BusinessHoliday> _businessHolidays = const [];
  List<int> _weeklyHolidays = const [];
  List<ScheduleException> _businessScheduleExceptions = const [];
  List<EmployeeScheduleException> _scheduleExceptions = const [];
  List<EmployeeLeaveBlock> _leaveBlocks = const [];
  int _loadGeneration = 0;
  bool _disposed = false;

  JalaliDate get today => _today;
  JalaliDate get anchor => _anchor;
  JalaliDate get selected => _selected;
  CalendarView get view => _view;
  String? get employeeId => _employeeId;
  String? get serviceId => _serviceId;
  AppointmentStatus? get statusFilter => _statusFilter;
  bool get loading => _loading;
  String? get error => _error;
  List<Employee> get employees => _serviceId == null
      ? _employeeList
      : _employeeList.where((employee) => employee.serviceIds.contains(_serviceId)).toList(growable: false);
  List<Service> get services => _serviceList;
  List<Appointment> get appointments => _rangeAppointments.where(_matchesFilters).toList(growable: false);
  List<EmployeeScheduleException> get scheduleExceptions => _scheduleExceptions;
  List<EmployeeLeaveBlock> get leaveBlocks => _leaveBlocks;
  List<BusinessHoliday> get businessHolidays => _businessHolidays;
  List<int> get weeklyHolidays => _weeklyHolidays;
  List<ScheduleException> get businessScheduleExceptions => _businessScheduleExceptions;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _handleAuthChange() {
    if (_disposed) return;
    if (authStateNotifier?.hasActiveBusiness == true) {
      unawaited(load());
    } else {
      _loadGeneration++;
      _clearData();
      _loading = false;
      _error = 'عضویت فعال مجموعه تأیید نشده است.';
      _safeNotify();
    }
  }

  void _clearData() {
    _rangeAppointments = const [];
    _employeeList = const [];
    _serviceList = const [];
    _workingHours = const [];
    _businessHolidays = const [];
    _weeklyHolidays = const [];
    _businessScheduleExceptions = const [];
    _scheduleExceptions = const [];
    _leaveBlocks = const [];
  }

  void setView(CalendarView view) {
    if (_view == view) return;
    _view = view;
    unawaited(load());
  }

  void setSelected(JalaliDate date) {
    _selected = date;
    _anchor = date;
    unawaited(load());
  }

  void selectToday() {
    _today = JalaliDate.today();
    _selected = _today;
    _anchor = _today;
    unawaited(load());
  }

  void setEmployee(String? id) {
    if (_employeeId == id) return;
    _employeeId = id;
    unawaited(load());
  }

  void setStatus(AppointmentStatus? status) {
    if (_statusFilter == status) return;
    _statusFilter = status;
    _safeNotify();
  }

  void setService(String? id) {
    if (_serviceId == id) return;
    _serviceId = id;
    if (_employeeId != null && !_employeeList.any((employee) =>
        employee.id == _employeeId && (id == null || employee.serviceIds.contains(id)))) {
      _employeeId = null;
    }
    unawaited(load());
  }

  void next() {
    switch (_view) {
      case CalendarView.daily:
        _anchor = _anchor.addDays(1);
        _selected = _anchor;
      case CalendarView.weekly:
        _anchor = _anchor.addDays(7);
        _selected = _anchor;
      case CalendarView.monthly:
        _anchor = _anchor.addMonths(1);
        _selected = JalaliDate(_anchor.year, _anchor.month, 1);
    }
    unawaited(load());
  }

  void previous() {
    switch (_view) {
      case CalendarView.daily:
        _anchor = _anchor.addDays(-1);
        _selected = _anchor;
      case CalendarView.weekly:
        _anchor = _anchor.addDays(-7);
        _selected = _anchor;
      case CalendarView.monthly:
        _anchor = _anchor.addMonths(-1);
        _selected = JalaliDate(_anchor.year, _anchor.month, 1);
    }
    unawaited(load());
  }

  (JalaliDate, JalaliDate) get _visibleRange {
    switch (_view) {
      case CalendarView.daily:
        return (_selected, _selected);
      case CalendarView.weekly:
        final days = weekDays;
        return (days.first, days.last);
      case CalendarView.monthly:
        final first = JalaliDate(_anchor.year, _anchor.month, 1);
        final gridStart = first.addDays(-first.weekday);
        return (gridStart, gridStart.addDays(41));
    }
  }

  Future<List<Appointment>> _loadAppointments(JalaliDate from, JalaliDate to) async {
    final result = <Appointment>[];
    var page = 1;
    const pageSize = 100;
    var total = 0;
    do {
      final pageResult = await _appointments.fetchAppointments(
        filter: AppointmentFilter(
          fromDate: from,
          toDate: to,
        ),
        page: page,
        pageSize: pageSize,
        ascending: true,
      );
      result.addAll(pageResult.items);
      total = pageResult.total;
      if (pageResult.items.isEmpty) break;
      page++;
    } while (result.length < total);
    return result;
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final auth = authStateNotifier;
    if (auth != null && !auth.hasActiveBusiness) {
      _clearData();
      _loading = false;
      _error = 'برای مشاهده تقویم، اتصال و عضویت فعال مجموعه لازم است.';
      _safeNotify();
      return;
    }

    final range = _visibleRange;
    final from = range.$1.toDateTime();
    final to = range.$2.toDateTime();
    _loading = true;
    _error = null;
    _safeNotify();

    try {
      final results = await Future.wait<dynamic>([
        _employees.fetchEmployees(onlyActive: true, serviceId: _serviceId),
        _services.fetchServices(onlyActive: true),
        _loadAppointments(range.$1, range.$2),
        _employees.fetchWorkingHours(employeeId: _employeeId),
        _employees.fetchBusinessHolidays(from: from, to: to),
        if (settingsRepository != null) settingsRepository!.fetchSettings(),
      ]);
      if (generation != _loadGeneration || _disposed) return;

      final employees = results[0] as List<Employee>;
      final employeeIds = employees.map((employee) => employee.id).toList(growable: false);
      final exceptionAndLeaveResults = await Future.wait(
        employeeIds.map((id) async =>
            _employees.fetchScheduleExceptions(employeeId: id, from: from, to: to)),
      );
      final leaveBlocks = await _employees.fetchCalendarLeaveBlocks(
        employeeIds: employeeIds,
        from: from,
        to: to,
      );
      if (generation != _loadGeneration || _disposed) return;

      _employeeList = employees;
      _serviceList = results[1] as List<Service>;
      _rangeAppointments = results[2] as List<Appointment>;
      _workingHours = results[3] as List<EmployeeWorkingHour>;
      _businessHolidays = results[4] as List<BusinessHoliday>;
      final businessSettings = settingsRepository == null ? null : results[5] as BusinessSettings;
      _weeklyHolidays = businessSettings?.holidays ?? const [];
      _businessScheduleExceptions = businessSettings?.scheduleExceptions ?? const [];
      _scheduleExceptions = exceptionAndLeaveResults
          .expand((items) => items)
          .toList(growable: false);
      _leaveBlocks = leaveBlocks;
      _error = null;
    } catch (error) {
      if (generation != _loadGeneration || _disposed) return;
      _clearData();
      _error = 'دریافت اطلاعات تقویم از سرور ناموفق بود: $error';
    } finally {
      if (generation == _loadGeneration && !_disposed) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  /// روزهای هفته جاری (شنبه تا جمعه) برای نمای هفتگی.
  List<JalaliDate> get weekDays {
    final start = _anchor.addDays(-_anchor.weekday);
    return [for (var i = 0; i < 7; i++) start.addDays(i)];
  }

  /// جدول ماه شمسی: ۴۲ خانه با خانه‌های ماه قبل/بعد.
  List<CalendarCell> monthGrid(JalaliDate month) {
    final first = JalaliDate(month.year, month.month, 1);
    final leading = first.weekday;
    final daysInMonth = first.monthLength;
    final prevMonth = JalaliDate(month.year, month.month, 1).addMonths(-1);
    final prevDays = prevMonth.monthLength;
    final cells = <CalendarCell>[];
    for (var i = leading - 1; i >= 0; i--) {
      cells.add(CalendarCell(
        date: JalaliDate(prevMonth.year, prevMonth.month, prevDays - i),
        isCurrentMonth: false,
      ));
    }
    for (var day = 1; day <= daysInMonth; day++) {
      cells.add(CalendarCell(date: JalaliDate(first.year, first.month, day), isCurrentMonth: true));
    }
    final next = JalaliDate(month.year, month.month, 1).addMonths(1);
    var day = 1;
    while (cells.length < 42) {
      cells.add(CalendarCell(date: JalaliDate(next.year, next.month, day), isCurrentMonth: false));
      day++;
    }
    return cells;
  }

  String _dateKey(DateTime date) => EmployeeScheduleRules.dateKey(date);

  BusinessHoliday? holidayFor(JalaliDate date) {
    final key = _dateKey(date.toDateTime());
    for (final holiday in _businessHolidays) {
      if (holiday.dateKey == key) return holiday;
    }
    return null;
  }

  EmployeeScheduleException? employeeExceptionFor(JalaliDate date, String employeeId) {
    final key = _dateKey(date.toDateTime());
    for (final exception in _scheduleExceptions) {
      if (exception.employeeId == employeeId && exception.dateKey == key) return exception;
    }
    return null;
  }

  ScheduleException? businessExceptionFor(JalaliDate date) {
    final key = _dateKey(date.toDateTime());
    final matches = _businessScheduleExceptions.where((item) => item.dateKey == key).toList();
    return matches.isEmpty ? null : matches.first;
  }

  ScheduleException? exceptionFor(JalaliDate date, {String? employeeId}) {
    final key = _dateKey(date.toDateTime());
    if (employeeId != null) {
      final item = employeeExceptionFor(date, employeeId);
      if (item != null) {
        return ScheduleException(dateKey: key, title: item.title, isClosed: item.isClosed, shifts: item.shifts);
      }
      return businessExceptionFor(date);
    }
    final businessException = businessExceptionFor(date);
    if (businessException != null) return businessException;
    final matches = _scheduleExceptions.where((value) => value.dateKey == key).toList();
    if (matches.isEmpty) return null;
    final item = matches.first;
    return ScheduleException(
      dateKey: key,
      title: item.title,
      isClosed: item.isClosed,
      shifts: item.shifts,
    );
  }

  bool _businessClosed(JalaliDate date) {
    if (holidayFor(date) != null) return true;
    final exception = businessExceptionFor(date);
    if (exception?.isClosed == true) return true;
    return _weeklyHolidays.contains(date.weekday) && exception == null;
  }

  List<Shift> _intersectShifts(List<Shift> employeeShifts, List<Shift> businessShifts) {
    final result = <Shift>[];
    for (final employeeShift in employeeShifts) {
      for (final businessShift in businessShifts) {
        final start = employeeShift.startMinutes > businessShift.startMinutes
            ? employeeShift.startMinutes
            : businessShift.startMinutes;
        final end = employeeShift.endMinutes < businessShift.endMinutes
            ? employeeShift.endMinutes
            : businessShift.endMinutes;
        if (start < end) {
          result.add(Shift(
            start: '${(start ~/ 60).toString().padLeft(2, '0')}:${(start % 60).toString().padLeft(2, '0')}',
            end: '${(end ~/ 60).toString().padLeft(2, '0')}:${(end % 60).toString().padLeft(2, '0')}',
          ));
        }
      }
    }
    return result;
  }

  List<Shift> shiftsFor(Employee employee, JalaliDate date) {
    if (!employee.scheduleEnabled || _businessClosed(date)) return const [];
    final employeeException = employeeExceptionFor(date, employee.id);
    var employeeShifts = employeeException != null
        ? (employeeException.isClosed ? const <Shift>[] : employeeException.shifts)
        : _workingHours
            .where((hour) => hour.employeeId == employee.id &&
                hour.weekday == date.weekday &&
                hour.isEffectiveOn(date.toDateTime()))
            .map((hour) => hour.shift)
            .toList(growable: false);
    final businessException = businessExceptionFor(date);
    if (businessException != null && !businessException.isClosed) {
      employeeShifts = _intersectShifts(employeeShifts, businessException.shifts);
    }
    return employeeShifts;
  }

  bool _onApprovedLeave(String employeeId, DateTime start, DateTime end) =>
      _leaveBlocks.any((leave) => leave.employeeId == employeeId && leave.overlaps(start, end));

  bool isHoliday(JalaliDate date, {String? employeeId}) {
    if (_businessClosed(date)) return true;
    final candidates = _employeeList.where((item) => employeeId == null || item.id == employeeId);
    if (candidates.isEmpty) return true;
    return !candidates.any((employee) {
      final shifts = shiftsFor(employee, date);
      if (shifts.isEmpty) return false;
      final dayStart = date.toDateTime();
      final dayEnd = dayStart.add(const Duration(days: 1));
      return !_leaveBlocks.any((leave) => leave.employeeId == employee.id &&
          !leave.startAt.isAfter(dayStart) && !leave.endAt.isBefore(dayEnd));
    });
  }

  bool _matchesFilters(Appointment appointment) {
    if (_employeeId != null && appointment.employeeId != _employeeId) return false;
    if (_serviceId != null && !appointment.serviceIds.contains(_serviceId)) return false;
    if (_statusFilter != null && appointment.status != _statusFilter) return false;
    return true;
  }

  List<Appointment> appointmentsOn(JalaliDate date) {
    return _rangeAppointments.where((appointment) =>
        appointment.jalali.sameDay(date) && _matchesFilters(appointment)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  /// خانه‌های زمانی با ظرفیت واقعی پرسنل، شیفت‌های معتبر، مرخصی و نوبت‌های فعال.
  List<TimeSlot> slotsFor(JalaliDate date, {int? intervalMinutes, String? employee}) {
    final step = intervalMinutes ?? 15;
    if (step <= 0) throw ArgumentError.value(step, 'intervalMinutes');
    if (_businessClosed(date)) return const [];

    final candidates = _employeeList.where((item) =>
        (employee == null || item.id == employee) &&
        (_employeeId == null || item.id == _employeeId) &&
        (_serviceId == null || item.serviceIds.contains(_serviceId)));
    final workingByMinute = <int, Set<String>>{};
    for (final person in candidates) {
      for (final shift in shiftsFor(person, date)) {
        for (var minute = shift.startMinutes; minute < shift.endMinutes; minute += step) {
          final start = date.toDateTime().add(Duration(minutes: minute));
          final end = start.add(Duration(minutes: step));
          final exception = employeeExceptionFor(date, person.id);
          final effectiveHours = _workingHours.where((hour) =>
              hour.employeeId == person.id &&
              hour.weekday == date.weekday &&
              hour.isEffectiveOn(date.toDateTime()) &&
              hour.shift.startMinutes <= minute &&
              hour.shift.endMinutes >= minute + step);
          final isExceptionSlot = exception != null &&
              !exception.isClosed &&
              exception.shifts.any((item) => item.startMinutes <= minute && item.endMinutes >= minute + step);
          final isWeeklySlot = exception == null && effectiveHours.isNotEmpty;
          final hasBreak = exception == null && _workingHours.any((hour) =>
              hour.employeeId == person.id &&
              hour.weekday == date.weekday &&
              hour.isEffectiveOn(date.toDateTime()) &&
              hour.breakStart != null &&
              hour.breakEnd != null &&
              _timeMinutes(hour.breakStart!) < minute + step &&
              _timeMinutes(hour.breakEnd!) > minute);
          if ((!isExceptionSlot && !isWeeklySlot) || hasBreak || _onApprovedLeave(person.id, start, end)) {
            continue;
          }
          workingByMinute.putIfAbsent(minute, () => <String>{}).add(person.id);
        }
      }
    }

    final dayAppointments = _rangeAppointments
        .where((item) => item.jalali.sameDay(date))
        .toList(growable: false);
    final activeAppointments = dayAppointments.where((item) => item.status.isActive).toList();
    final result = <TimeSlot>[];
    final minutes = workingByMinute.keys.toList()..sort();
    for (final minute in minutes) {
      final start = date.toDateTime().add(Duration(minutes: minute));
      final end = start.add(Duration(minutes: step));
      final working = workingByMinute[minute]!;
      final availableCount = working.where((employeeId) {
        final employee = _employeeList.where((person) => person.id == employeeId).toList();
        final buffer = Duration(minutes: employee.isEmpty ? 0 : employee.first.bufferMinutes);
        return !activeAppointments.any((item) =>
            item.employeeId == employeeId &&
            item.startAt.isBefore(end.add(buffer)) &&
            start.isBefore(item.endAt.add(buffer)));
      }).length;
      final slotAppointments = appointmentsOn(date).where((item) {
        final appointmentMinute = item.startAt.hour * 60 + item.startAt.minute;
        return appointmentMinute >= minute && appointmentMinute < minute + step;
      }).toList(growable: false);
      result.add(TimeSlot(
        date: date,
        hour: minute ~/ 60,
        minute: minute % 60,
        appointments: slotAppointments,
        capacity: working.length,
        availableCapacity: availableCount,
        isPast: date.sameDay(today) && DateTime.now().isAfter(start),
      ));
    }
    return result;
  }

  static int _timeMinutes(String value) {
    final parts = value.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  /// جابه‌جایی تقویمی؛ کنترل محلی برای UX و کنترل نهایی با RPC دیتابیس.
  Future<void> rescheduleAppointment(Appointment appointment, DateTime newStart) async {
    final employees = _employeeList.where((item) => item.id == appointment.employeeId).toList();
    if (employees.isEmpty) throw StateError('پرسنل نوبت در اطلاعات واقعی تقویم پیدا نشد.');
    final employee = employees.first;
    final start = newStart;
    final end = start.add(Duration(minutes: appointment.durationMinutes));
    final jalali = JalaliDate.fromDateTime(start);
    if (_businessClosed(jalali)) {
      throw StateError('این تاریخ طبق تنظیمات واقعی مجموعه تعطیل است.');
    }
    final exception = employeeExceptionFor(jalali, employee.id);
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    final shiftCovers = shiftsFor(employee, jalali).any((shift) =>
        shift.startMinutes <= startMinute && shift.endMinutes >= endMinute);
    final breakConflict = exception == null && _workingHours.any((hour) =>
        hour.employeeId == employee.id &&
        hour.weekday == jalali.weekday &&
        hour.isEffectiveOn(start) &&
        hour.shift.startMinutes <= startMinute &&
        hour.shift.endMinutes >= endMinute &&
        !hour.covers(start, end));
    if (!employee.scheduleEnabled || !shiftCovers || breakConflict) {
      throw StateError('زمان انتخاب‌شده خارج از ساعات کاری یا در زمان استراحت پرسنل است.');
    }
    if (_onApprovedLeave(employee.id, start, end)) {
      throw StateError('پرسنل در زمان انتخاب‌شده مرخصی تأییدشده دارد.');
    }
    final buffer = Duration(minutes: employee.bufferMinutes);
    final conflict = _rangeAppointments.any((other) =>
        other.id != appointment.id &&
        other.employeeId == employee.id &&
        other.status.isActive &&
        other.startAt.isBefore(end.add(buffer)) &&
        start.isBefore(other.endAt.add(buffer)));
    if (conflict) throw StateError('این بازه با نوبت دیگری تداخل دارد.');
    await _appointments.reschedule(appointment, newStart);
    await load();
  }

  int get monthlyAppointmentsCount => appointments
      .where((appointment) =>
          appointment.jalali.month == _anchor.month &&
          appointment.jalali.year == _anchor.year)
      .length;

  @override
  void dispose() {
    _disposed = true;
    authStateNotifier?.removeListener(_handleAuthChange);
    _loadGeneration++;
    super.dispose();
  }
}

/// یک خانه از جدول ماه.
class CalendarCell {
  const CalendarCell({required this.date, required this.isCurrentMonth});
  final JalaliDate date;
  final bool isCurrentMonth;
}

/// یک خانه زمانی تقویم با ظرفیت و فهرست نوبت‌های واقعی.
class TimeSlot {
  const TimeSlot({
    required this.date,
    required this.hour,
    required this.minute,
    this.appointments = const [],
    this.capacity = 0,
    this.availableCapacity = 0,
    this.isPast = false,
  });

  final JalaliDate date;
  final int hour;
  final int minute;
  final List<Appointment> appointments;
  final int capacity;
  final int availableCapacity;
  final bool isPast;

  Appointment? get appointment => appointments.isEmpty ? null : appointments.first;
  bool get isBooked => appointments.isNotEmpty;
  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  DateTime get startAt => date.toDateTime().add(Duration(hours: hour, minutes: minute));
}
