import '../../core/models/page_result.dart';
import '../mock/app_database.dart';
import '../models/appointment.dart';
import '../models/enums.dart';

/// قرارداد دسترسی به داده نوبت‌ها؛ UI فقط به این abstraction وابسته است.
abstract class AppointmentRepository {
  Future<PageResult<Appointment>> fetchAppointments({
    AppointmentFilter filter = const AppointmentFilter(),
    int page = 1,
    int pageSize = 8,
    bool ascending = true,
  });

  Future<List<Appointment>> fetchAll({AppointmentFilter filter = const AppointmentFilter()});

  Future<List<Appointment>> fetchForDay(DateTime day, {String? employeeId, String? serviceId});

  Future<List<Appointment>> fetchForCustomer(String customerId);

  Future<Appointment?> findById(String id);

  Future<Appointment?> findConflict({
    required String employeeId,
    required DateTime startAt,
    required int durationMinutes,
    String? ignoreId,
  });

  Future<void> create(Appointment appointment);

  Future<void> update(Appointment appointment);

  Future<void> changeStatus(Appointment appointment, AppointmentStatus status, {String? reason, int discountAmount = 0, int? finalPaidAmount});

  Future<void> reschedule(Appointment appointment, DateTime newStart, {bool byCustomer = false});

  Future<void> delete(String id);
}

class MockAppointmentRepository implements AppointmentRepository {
  MockAppointmentRepository(this._db);

  final AppDatabase _db;

  bool _canSee(Appointment appointment) => _db.hasPermission('appointments.view_all') ||
      (_db.hasPermission('appointments.view_self') && _db.currentAccessAccount.employeeId == appointment.employeeId);

  List<Appointment> _visible(List<Appointment> source) {
    if (!_db.hasPermission('appointments.view_all') && !_db.hasPermission('appointments.view_self')) _db.requirePermission('appointments.view_all');
    return source.where(_canSee).toList();
  }

  @override
  Future<PageResult<Appointment>> fetchAppointments({
    AppointmentFilter filter = const AppointmentFilter(),
    int page = 1,
    int pageSize = 8,
    bool ascending = true,
  }) async {
    await _db.delay(180);
    final filtered = _visible(_db.appointments).where(filter.matches).toList()
      ..sort((a, b) => ascending ? a.startAt.compareTo(b.startAt) : b.startAt.compareTo(a.startAt));
    final start = (page - 1) * pageSize;
    if (start >= filtered.length) {
      return PageResult(items: const [], total: filtered.length, page: page, pageSize: pageSize);
    }
    final end = (start + pageSize).clamp(0, filtered.length);
    return PageResult(items: filtered.sublist(start, end), total: filtered.length, page: page, pageSize: pageSize);
  }

  @override
  Future<List<Appointment>> fetchAll({AppointmentFilter filter = const AppointmentFilter()}) async {
    await _db.delay(120);
    return _visible(_db.appointments).where(filter.matches).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  @override
  Future<List<Appointment>> fetchForDay(DateTime day, {String? employeeId, String? serviceId}) async {
    final list = _visible(_db.appointments).where((a) {
      final sameDay = a.startAt.year == day.year && a.startAt.month == day.month && a.startAt.day == day.day;
      if (!sameDay) return false;
      if (employeeId != null && a.employeeId != employeeId) return false;
      if (serviceId != null && !a.serviceIds.contains(serviceId)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return list;
  }

  @override
  Future<List<Appointment>> fetchForCustomer(String customerId) async {
    final list = _visible(_db.appointments).where((a) => a.customerId == customerId).toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return list;
  }

  @override
  Future<Appointment?> findById(String id) async {
    final appointment = _db.appointmentById(id);
    return appointment != null && _canSee(appointment) ? appointment : null;
  }

  @override
  Future<Appointment?> findConflict({
    required String employeeId,
    required DateTime startAt,
    required int durationMinutes,
    String? ignoreId,
  }) async =>
      _db.findConflict(employeeId: employeeId, startAt: startAt, durationMinutes: durationMinutes, ignoreId: ignoreId);

  @override
  Future<void> create(Appointment appointment) async {
    await _db.delay(240);
    _db.addAppointment(appointment);
  }

  @override
  Future<void> update(Appointment appointment) async {
    await _db.delay(200);
    _db.updateAppointment(appointment);
  }

  @override
  Future<void> changeStatus(Appointment appointment, AppointmentStatus status, {String? reason, int discountAmount = 0, int? finalPaidAmount}) async {
    await _db.delay(160);
    _db.changeStatus(appointment, status, reason: reason, discountAmount: discountAmount, finalPaidAmount: finalPaidAmount);
  }

  @override
  Future<void> reschedule(Appointment appointment, DateTime newStart, {bool byCustomer = false}) async {
    if (!byCustomer) _db.requirePermission('appointments.edit');
    await _db.delay(200);
    _db.reschedule(appointment, newStart, byCustomer: byCustomer);
  }

  @override
  Future<void> delete(String id) async {
    _db.requirePermission('appointments.cancel');
    await _db.delay(160);
    _db.deleteAppointment(id);
  }
}
