import 'package:flutter/foundation.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/business_settings.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/employee_schedule.dart';
import '../../../../data/models/service.dart';
import '../../../../data/repositories/appointment_repository.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/service_repository.dart';

/// حالت نمایش تقویم.
enum CalendarView { daily, weekly, monthly }

/// مدیریت تقویم شمسی (روز/هفته/ماه)، فیلترها و خانه‌های زمانی.
class CalendarProvider extends ChangeNotifier {
  CalendarProvider(
    this._appointments,
    this._employees,
    this._services,
  ) {
    _today = JalaliDate.today();
    _anchor = _today;
    _selected = _today;
    load();
  }

  final AppointmentRepository _appointments;
  final EmployeeRepository _employees;
  final ServiceRepository _services;

  late JalaliDate _today;
  late JalaliDate _anchor;
  late JalaliDate _selected;
  CalendarView _view = CalendarView.monthly;
  String? _employeeId;
  String? _serviceId;
  bool _loading = true;
  String? _loadError;
  String? get loadError => _loadError;
  List<Appointment> _rangeAppointments = const [];
  List<Employee> _employeeList = const [];
  List<Service> _serviceList = const [];
  Map<String,List<EmployeeScheduleException>> _scheduleExceptions = const {};
  Map<String,List<EmployeeLeave>> _employeeLeaves = const {};
  int _loadGeneration = 0;

  JalaliDate get today => _today;
  JalaliDate get anchor => _anchor;
  JalaliDate get selected => _selected;
  CalendarView get view => _view;
  String? get employeeId => _employeeId;
  String? get serviceId => _serviceId;
  bool get loading => _loading;
  List<Employee> get employees => _serviceId == null ? _employeeList : _employeeList.where((employee) => employee.serviceIds.contains(_serviceId)).toList();
  List<Service> get services => _serviceList;
  List<Appointment> get appointments => _rangeAppointments;

  void setView(CalendarView view) {
    _view = view;
    notifyListeners();
  }

  void setSelected(JalaliDate date) {
    _selected = date;
    _anchor = date;
    notifyListeners();
  }

  void selectToday() {
    _today = JalaliDate.today();
    _selected = _today;
    _anchor = _today;
    notifyListeners();
  }

  void setEmployee(String? id) {
    _employeeId = id;
    load();
  }

  void setService(String? id) {
    _serviceId = id;
    load();
  }

  void next() {
    switch (_view) {
      case CalendarView.daily:
        _anchor = _anchor.addDays(1);
        _selected = _anchor;
      case CalendarView.weekly:
        _anchor = _anchor.addDays(7);
      case CalendarView.monthly:
        _anchor = _anchor.addMonths(1);
    }
    notifyListeners();
  }

  void previous() {
    switch (_view) {
      case CalendarView.daily:
        _anchor = _anchor.addDays(-1);
        _selected = _anchor;
      case CalendarView.weekly:
        _anchor = _anchor.addDays(-7);
      case CalendarView.monthly:
        _anchor = _anchor.addMonths(-1);
    }
    notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    notifyListeners();
    try {
      final employees = await _employees.fetchEmployees();
      final services = await _services.fetchServices();
      final appointments = await _appointments.fetchAll();
      final availability = await Future.wait(employees.map((employee) async => [
        await _employees.fetchScheduleExceptions(employee.id),
        await _employees.fetchLeaves(employee.id),
      ]));
      if (generation != _loadGeneration) return;
      _employeeList = employees;
      _serviceList = services;
      _rangeAppointments = appointments;
      _scheduleExceptions = {for (var i=0;i<employees.length;i++) employees[i].id: availability[i][0] as List<EmployeeScheduleException>};
      _employeeLeaves = {for (var i=0;i<employees.length;i++) employees[i].id: availability[i][1] as List<EmployeeLeave>};
      _loadError = null;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _employeeList = const [];
      _serviceList = const [];
      _rangeAppointments = const [];
      _scheduleExceptions = const {};
      _employeeLeaves = const {};
      _loadError = error.toString();
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }


  /// همه نوبت‌های یک روز (با اعمال فیلترها).
  List<Appointment> appointmentsOn(JalaliDate date) {
    return _rangeAppointments.where((a) {
      if (!a.jalali.sameDay(date)) return false;
      if (_employeeId != null && a.employeeId != _employeeId) return false;
      if (_serviceId != null && !a.serviceIds.contains(_serviceId)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  /// روزهای هفته جاری (شنبه تا جمعه) برای نمای هفتگی.
  List<JalaliDate> get weekDays {
    final start = _anchor.addDays(-_anchor.weekday);
    return [for (var i = 0; i < 7; i++) start.addDays(i)];
  }

  /// جدول ماه شمسی: ۴۲ خانه (۶ هفته) با خانه‌های ماه قبل/بعد.
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
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(CalendarCell(date: JalaliDate(first.year, first.month, d), isCurrentMonth: true));
    }
    var next = JalaliDate(month.year, month.month, 1).addMonths(1);
    var i = 1;
    while (cells.length < 42) {
      cells.add(CalendarCell(date: JalaliDate(next.year, next.month, i), isCurrentMonth: false));
      i++;
    }
    return cells;
  }

  /// خانه‌های زمانی یک روز بر اساس ساعات کاری و نوبت‌های ثبت‌شده.
  List<TimeSlot> slotsFor(JalaliDate date, {int? intervalMinutes, String? employee}) {
    final stepMinutes = intervalMinutes ?? 30;
    final dayAppointments = appointmentsOn(date)
        .where((a) => employee == null || a.employeeId == employee)
        .toList();
    final selectedEmployee = employee == null ? null : _employeeList.where((e) => e.id == employee).firstOrNull;
    final dateKey = EmployeeScheduleRules.dateKey(date.toDateTime());
    final exception = selectedEmployee == null ? null : (_scheduleExceptions[selectedEmployee.id] ?? const <EmployeeScheduleException>[]).where((item) => item.dateKey == dateKey).firstOrNull;
    final shifts = selectedEmployee == null ? const <Shift>[] : exception == null ? selectedEmployee.shiftsFor(date.weekday) : (exception.isClosed ? const <Shift>[] : exception.shifts);
    final leaves = selectedEmployee == null ? const <EmployeeLeave>[] : (_employeeLeaves[selectedEmployee.id] ?? const <EmployeeLeave>[]);
    final slots = <TimeSlot>[];
    for (final shift in shifts) {
      for (var minutes = shift.startMinutes; minutes < shift.endMinutes; minutes += stepMinutes) {
      final hour = minutes ~/ 60;
      final minute = minutes % 60;
      final start = date.toDateTime().add(Duration(hours: hour, minutes: minute));
      final busy = dayAppointments.where((a) {
        return !start.isBefore(a.startAt) && start.isBefore(a.endAt);
      }).toList();
        final end = start.add(const Duration(minutes: 30));
        final onLeave = leaves.any((leave) => leave.overlaps(start, end));
        if (onLeave) continue;
        slots.add(TimeSlot(hour: hour, minute: minute, appointment: busy.isEmpty ? null : busy.first, isPast: date.sameDay(today) && DateTime.now().isAfter(start)));
      }
    }
    return slots;
  }

  /// آیا روز تعطیل است؟
  ScheduleException? exceptionFor(JalaliDate date) => null;

  bool isHoliday(JalaliDate date, {String? employeeId}) {
    if (employeeId != null) {
      final employee = _employeeList.where((e) => e.id == employeeId).firstOrNull;
      if (employee == null) return true;
      final key = EmployeeScheduleRules.dateKey(date.toDateTime());
      final exception = (_scheduleExceptions[employee.id] ?? const <EmployeeScheduleException>[]).where((item) => item.dateKey == key).firstOrNull;
      if (exception?.isClosed == true) return true;
      final shifts = exception == null ? employee.shiftsFor(date.weekday) : exception.shifts;
      if (shifts.isEmpty) return true;
      final start = date.toDateTime();
      return (_employeeLeaves[employee.id] ?? const <EmployeeLeave>[]).any((leave) => leave.status == EmployeeLeaveStatus.approved && !leave.startAt.isAfter(start) && leave.endAt.isAfter(start));
    }
    return false;
  }

  int get monthlyAppointmentsCount => _rangeAppointments
      .where((a) => a.jalali.month == _anchor.month && a.jalali.year == _anchor.year)
      .length;
}

/// یک خانه از جدول ماه.
class CalendarCell {
  const CalendarCell({required this.date, required this.isCurrentMonth});

  final JalaliDate date;
  final bool isCurrentMonth;
}

/// یک خانه زمانی در نمای روزانه.
class TimeSlot {
  const TimeSlot({
    required this.hour,
    required this.minute,
    this.appointment,
    this.isPast = false,
  });

  final int hour;
  final int minute;
  final Appointment? appointment;
  final bool isPast;

  bool get isBooked => appointment != null;
  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
