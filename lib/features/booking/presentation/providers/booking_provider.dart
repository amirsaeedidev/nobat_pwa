import 'package:flutter/foundation.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/customer.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/service.dart';
import '../../../../data/repositories/appointment_repository.dart';
import '../../../../data/repositories/customer_repository.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/service_repository.dart';

/// خانه زمانی قابل انتخاب در صفحه رزرو عمومی.
class BookingSlot {
  const BookingSlot({required this.start, required this.isAvailable, this.reason});

  final DateTime start;
  final bool isAvailable;
  final String? reason;

  String get label =>
      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
}

/// فرایند رزرو عمومی مشتری (بدون نیاز به نصب اپلیکیشن).
class BookingProvider extends ChangeNotifier {
  BookingProvider(
    this._appointments,
    this._services,
    this._employees,
    this._customers,
  ) {
    _date = JalaliDate.today();
    loadServices();
  }

  final AppointmentRepository _appointments;
  final ServiceRepository _services;
  final EmployeeRepository _employees;
  final CustomerRepository _customers;

  int _step = 0;
  Service? _service;
  Employee? _employee;
  late JalaliDate _date;
  BookingSlot? _slot;
  String _name = '';
  String _phone = '';
  String _note = '';
  bool _submitting = false;
  Appointment? _created;
  String? _error;

  List<Service> _availableServices = const [];
  List<Employee> _availableEmployees = const [];
  List<BookingSlot> _slots = const [];
  bool _loading = true;
  int _catalogGeneration = 0;
  int _slotGeneration = 0;

  int get step => _step;
  Service? get service => _service;
  Employee? get employee => _employee;
  JalaliDate get date => _date;
  BookingSlot? get slot => _slot;
  String get name => _name;
  String get phone => _phone;
  String get note => _note;
  bool get submitting => _submitting;
  Appointment? get created => _created;
  String? get error => _error;
  List<Service> get availableServices => _availableServices;
  List<Employee> get availableEmployees => _availableEmployees;
  List<BookingSlot> get slots => _slots;
  bool get loading => _loading;
  int get totalSteps => 4;

  bool get canProceed {
    switch (_step) {
      case 0:
        return _service != null;
      case 1:
        return _employee != null;
      case 2:
        return _slot != null;
      case 3:
        return _name.trim().length >= 3 && _phone.trim().length >= 10;
      default:
        return false;
    }
  }


  Future<void> _refreshAfterDatabaseChange() async {
    final generation = ++_catalogGeneration;
    try {
      final services = await _services.fetchServices(onlyActive: true);
      if (generation != _catalogGeneration) return;
      _availableServices = services;
      if (_service != null && !services.any((item) => item.id == _service!.id)) {
        _service = null;
        _employee = null;
        _slot = null;
        _availableEmployees = const [];
        _slots = const [];
        _step = 0;
      } else if (_service != null) {
        final employees = await _employees.fetchEmployees(serviceId: _service!.id);
        if (generation != _catalogGeneration) return;
        _availableEmployees = employees.where((item) => item.isActive).toList();
        if (_employee != null && !_availableEmployees.any((item) => item.id == _employee!.id)) {
          _employee = null;
          _slot = null;
          _slots = const [];
          _step = 1;
        } else if (_employee != null) {
          await _loadSlots();
        }
      }
    } catch (_) {
      _availableServices = const [];
      _error = 'دریافت خدمات از سرور ناموفق بود.';
      _availableEmployees = const [];
      _error = 'دریافت پرسنل از سرور ناموفق بود.';
    }
    if (generation == _catalogGeneration) notifyListeners();
  }

  Future<void> loadServices() async {
    final generation = ++_catalogGeneration;
    _loading = true;
    notifyListeners();
    try {
      final services = await _services.fetchServices(onlyActive: true);
      if (generation != _catalogGeneration) return;
      _availableServices = services;
    } catch (_) {
      if (generation != _catalogGeneration) return;
      _availableServices = const [];
      _error = 'دریافت خدمات از سرور ناموفق بود.';
    } finally {
      if (generation == _catalogGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void nextStep() {
    if (_step < 3) {
      _step++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_step > 0) {
      _step--;
      notifyListeners();
    }
  }

  void goToStep(int step) {
    _step = step.clamp(0, 3);
    notifyListeners();
  }

  Future<void> selectService(Service service) async {
    _service = service;
    _employee = null;
    _slot = null;
    _availableEmployees = await _employees.fetchEmployees(serviceId: service.id);
    _availableEmployees = _availableEmployees.where((e) => e.isActive).toList();
    _step = 1;
    notifyListeners();
  }

  Future<void> selectEmployee(Employee employee) async {
    _employee = employee;
    _slot = null;
    await _loadSlots();
    _step = 2;
    notifyListeners();
  }

  void selectDate(JalaliDate date) {
    _date = date;
    _slot = null;
    _loadSlots();
    notifyListeners();
  }

  void selectSlot(BookingSlot slot) {
    if (!slot.isAvailable) return;
    _slot = slot;
    notifyListeners();
  }

  /// تاریخ‌های قابل انتخاب تا سقف مجاز رزرو.
  List<JalaliDate> get selectableDates {
    final maxDays = (_service?.advanceDays ?? 30).clamp(1, 90);
    final today = JalaliDate.today();
    return [for (var i = 0; i < maxDays; i++) today.addDays(i)];
  }

  bool isDateEnabled(JalaliDate date) {
    if (_employee != null) return _employee!.scheduleEnabled && _employee!.shiftsFor(date.weekday).isNotEmpty;
    return false;
  }

  Future<void> _loadSlots() async {
    final generation = ++_slotGeneration;
    final service = _service;
    final employee = _employee;
    if (service == null || employee == null) {
      _slots = const [];
      return;
    }
    _loading = true;
    notifyListeners();
    final existing = await _appointments.fetchForDay(_date.toDateTime(), employeeId: employee.id);
    if (generation != _slotGeneration) return;
    final shifts = employee.scheduleEnabled ? employee.shiftsFor(_date.weekday) : const <Shift>[];
    final interval = 30;
    final slots = <BookingSlot>[];
    for (final shift in shifts) {
      for (var minutes = shift.startMinutes; minutes + service.durationMinutes <= shift.endMinutes; minutes += interval) {
        final start = _date.toDateTime().add(Duration(minutes: minutes));
        if (start.isBefore(DateTime.now())) {
          slots.add(BookingSlot(start: start, isAvailable: false, reason: 'گذشته'));
          continue;
        }
        final conflict = existing.any((a) {
          if (a.status == AppointmentStatus.cancelled) return false;
          final end = start.add(Duration(minutes: service.durationMinutes + service.bufferMinutes));
          return a.startAt.isBefore(end) && start.isBefore(a.endAt);
        });
        final scheduleAvailable = shifts.any((shift) => minutes >= shift.startMinutes && minutes + service.totalMinutes <= shift.endMinutes);
        final available = !conflict && scheduleAvailable;
        slots.add(
          BookingSlot(
            start: start,
            isAvailable: available,
            reason: conflict ? 'رزرو شده' : (scheduleAvailable ? null : 'مرخصی یا فاصله بین نوبت‌ها'),
          ),
        );
      }
    }
    if (generation != _slotGeneration) return;
    _slots = slots;
    _loading = false;
    notifyListeners();
  }

  void setName(String value) {
    _name = value;
    notifyListeners();
  }

  void setPhone(String value) {
    _phone = value;
    notifyListeners();
  }

  void setNote(String value) {
    _note = value;
    notifyListeners();
  }

  /// ثبت نهایی رزرو (ساخت مشتری در صورت جدید بودن).
  Future<bool> submit() async {
    final service = _service;
    final employee = _employee;
    final slot = _slot;
    if (service == null || employee == null || slot == null) {
      _error = 'لطفاً همه مراحل را تکمیل کنید';
      notifyListeners();
      return false;
    }
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final conflict = await _appointments.findConflict(
        employeeId: employee.id,
        startAt: slot.start,
        durationMinutes: service.totalMinutes,
      );
      if (conflict != null) {
        _error = 'این زمان هم‌اکنون رزرو شده است. لطفاً زمان دیگری انتخاب کنید.';
        _submitting = false;
        notifyListeners();
        return false;
      }
      final inShift = employee.scheduleEnabled && employee.shiftsFor(_date.weekday).any((shift) => slot.start.hour * 60 + slot.start.minute >= shift.startMinutes && slot.start.hour * 60 + slot.start.minute + service.totalMinutes <= shift.endMinutes);
      if (!inShift) {
        _error = 'این زمان خارج از برنامه کاری پرسنل است یا با مرخصی و فاصله بین نوبت‌ها تداخل دارد.';
        _submitting = false;
        notifyListeners();
        return false;
      }

      var customer = (await _customers.fetchAll(query: _phone)).where((c) => c.phone == _phone.trim()).firstOrNull;
      if (customer == null) {
        customer = Customer(
          id: '',
          fullName: _name.trim(),
          phone: _phone.trim(),
          createdAt: DateTime.now(),
          tags: const ['رزرو آنلاین'],
        );
        await _customers.create(customer);
        final matches = await _customers.fetchAll(query: _phone);
        customer = matches.where((c) => c.phone == _phone.trim()).firstOrNull;
        if (customer == null) throw StateError('مشتری پس از ثبت در سرور بازیابی نشد.');
      }

      final reference = 'DT-' + DateTime.now().millisecondsSinceEpoch.toString();
      final bookedPrice = service.priceAt(slot.start);
      final bookedDuration = service.durationMinutes + service.prepMinutes + service.bufferMinutes;
      final appointment = Appointment(
        id: 'booking-' + DateTime.now().microsecondsSinceEpoch.toString(),
        reference: reference,
        customerId: customer.id,
        customerName: customer.fullName,
        customerPhone: customer.phone,
        serviceIds: [service.id],
        serviceName: service.title,
        employeeId: employee.id,
        employeeName: employee.fullName,
        startAt: slot.start,
        durationMinutes: bookedDuration,
        status: service.requiresConfirmation ? AppointmentStatus.pending : AppointmentStatus.confirmed,
        price: bookedPrice,
        serviceSnapshots: [{
          'service_id': service.id,
          'title': service.title,
          'category': service.category,
          'price': bookedPrice,
          'direct_cost': service.directCost,
          'duration_minutes': bookedDuration,
        }],
        note: _note,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'صفحه رزرو آنلاین',
      );
      await _appointments.create(appointment);
      _created = appointment;
      _submitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'ثبت نوبت در سرور ناموفق بود: ' + e.toString();
      _submitting = false;
      notifyListeners();
      return false;
    }
  }

  /// بازنشانی فرایند برای رزرو جدید.
  void reset() {
    _step = 0;
    _service = null;
    _employee = null;
    _slot = null;
    _name = '';
    _phone = '';
    _note = '';
    _created = null;
    _error = null;
    _date = JalaliDate.today();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // مدیریت نوبت توسط مشتری (لغو / جابه‌جایی)
  // ---------------------------------------------------------------------------

  /// آیا مشتری می‌تواند این نوبت را لغو کند؟
  String? cancelBlockReason(Appointment appointment) {
    return null; // سیاست نهایی لغو توسط RPC و مجوزهای سرور اعمال می‌شود.
  }

  /// آیا مشتری می‌تواند این نوبت را جابه‌جا کند؟
  String? rescheduleBlockReason(Appointment appointment) {
    return null; // سیاست نهایی جابه‌جایی توسط RPC و مجوزهای سرور اعمال می‌شود.
  }

  Future<void> customerCancel(Appointment appointment, {String reason = 'لغو توسط مشتری'}) async {
    await _appointments.changeStatus(appointment, AppointmentStatus.cancelled, reason: reason);
    notifyListeners();
  }

  Future<bool> customerReschedule(Appointment appointment, DateTime newStart) async {
    final conflict = await _appointments.findConflict(
      employeeId: appointment.employeeId,
      startAt: newStart,
      durationMinutes: appointment.durationMinutes,
      ignoreId: appointment.id,
    );
    if (conflict != null) {
      _error = 'این زمان قبلاً رزرو شده است.';
      notifyListeners();
      return false;
    }
    await _appointments.reschedule(appointment, newStart, byCustomer: true);
    notifyListeners();
    return true;
  }

  /// یافتن نوبت‌های مشتری با شماره موبایل.
  Future<List<Appointment>> lookup(String phone) async {
    final normalized = phone.trim();
    final matches = await _customers.fetchAll(query: normalized);
    final customer = matches.where((c) => c.phone == normalized).firstOrNull;
    if (customer == null) return const [];
    return _appointments.fetchForCustomer(customer.id);
  }

  Future<List<Appointment>> lookupByReference(String reference) async {
    final page = await _appointments.fetchAppointments(filter: AppointmentFilter(query: reference.trim()), page: 1, pageSize: 20);
    return page.items.where((a) => a.reference == reference.trim()).toList();
  }
}
