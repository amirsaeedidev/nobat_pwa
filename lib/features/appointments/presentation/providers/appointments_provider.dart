import 'package:flutter/foundation.dart';
import '../../../../core/models/page_result.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/models/app_failure.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/repositories/appointment_repository.dart';

/// جست‌وجو، فیلتر، صفحه‌بندی و عملیات نوبت‌ها.
class AppointmentsProvider extends ChangeNotifier {
  AppointmentsProvider(this._repository) {
    load();
  }

  final AppointmentRepository _repository;

  PageResult<Appointment> _page = PageResult.empty(pageSize: 8);
  List<Appointment> _allAppointments = const [];
  AppointmentFilter _filter = const AppointmentFilter();
  bool _loading = true;
  String? _loadNotice;
  bool _busy = false;
  int _pageNumber = 1;
  int _pageSize = 8;
  bool _ascending = false;
  int _loadGeneration = 0;

  PageResult<Appointment> get page => _page;
  List<Appointment> get items => _page.items;
  List<Appointment> get allAppointments => _allAppointments;
  AppointmentFilter get filter => _filter;
  bool get loading => _loading;
  String? get loadNotice => _loadNotice;
  bool get busy => _busy;
  int get pageNumber => _pageNumber;
  int get pageSize => _pageSize;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    notifyListeners();
    try {
      _loadNotice = null;
      final results = await Future.wait([
        _repository.fetchAppointments(filter: _filter, page: _pageNumber, pageSize: _pageSize, ascending: _ascending),
        _repository.fetchAll(),
      ]);
      if (generation != _loadGeneration) return;
      _page = results[0] as PageResult<Appointment>;
      _allAppointments = results[1] as List<Appointment>;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _loadNotice = AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
      _page = PageResult.empty(pageSize: _pageSize);
      _allAppointments = const [];
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }


  Future<void> _loadSilently() async {
    final generation = ++_loadGeneration;
    try {
      final results = await Future.wait([
        _repository.fetchAppointments(filter: _filter, page: _pageNumber, pageSize: _pageSize, ascending: _ascending),
        _repository.fetchAll(),
      ]);
      var page = results[0] as PageResult<Appointment>;
      _allAppointments = results[1] as List<Appointment>;
      if (generation != _loadGeneration) return;
      // اگر صفحه فعلی خالی شد به صفحه قبل برگرد.
      if (page.items.isEmpty && _pageNumber > 1) {
        _pageNumber = (page.total / _pageSize).ceil().clamp(1, 999);
        page = await _repository.fetchAppointments(
          filter: _filter,
          page: _pageNumber,
          pageSize: _pageSize,
          ascending: _ascending,
        );
        if (generation != _loadGeneration) return;
      }
      _page = page;
      notifyListeners();
    } catch (error) {
      if (generation != _loadGeneration) return;
      _loadNotice = AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
      _page = PageResult.empty(pageSize: _pageSize);
      _allAppointments = const [];
      notifyListeners();
    }
  }

  void setQuery(String query) {
    _filter = _filter.copyWith(query: query);
    _pageNumber = 1;
    load();
  }

  void setStatus(AppointmentStatus? status) {
    _filter = status == null ? _filter.copyWith(clearStatus: true) : _filter.copyWith(status: status);
    _pageNumber = 1;
    load();
  }

  void setService(String? serviceId) {
    _filter = serviceId == null ? _filter.copyWith(clearService: true) : _filter.copyWith(serviceId: serviceId);
    _pageNumber = 1;
    load();
  }

  void setEmployee(String? employeeId) {
    _filter = employeeId == null ? _filter.copyWith(clearEmployee: true) : _filter.copyWith(employeeId: employeeId);
    _pageNumber = 1;
    load();
  }

  void setDateRange(JalaliDate? from, JalaliDate? to) {
    _filter = _filter.copyWith(
      fromDate: from,
      toDate: to,
      clearDates: from == null && to == null,
    );
    _pageNumber = 1;
    load();
  }

  void clearFilters() {
    _filter = AppointmentFilter(query: _filter.query);
    _pageNumber = 1;
    load();
  }

  void goToPage(int page) {
    _pageNumber = page.clamp(1, _page.totalPages == 0 ? 1 : _page.totalPages);
    load();
  }

  void setPageSize(int size) {
    _pageSize = size;
    _pageNumber = 1;
    load();
  }

  void toggleSort() {
    _ascending = !_ascending;
    load();
  }

  // ---------------------------------------------------------------------------
  // عملیات
  // ---------------------------------------------------------------------------

  /// بررسی تداخل زمانی پیش از ثبت.
  Future<Appointment?> checkConflict({
    required String employeeId,
    required DateTime startAt,
    required int durationMinutes,
    String? ignoreId,
  }) {
    return _repository.findConflict(
      employeeId: employeeId,
      startAt: startAt,
      durationMinutes: durationMinutes,
      ignoreId: ignoreId,
    );
  }

  Future<bool> create(Appointment appointment) async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.create(appointment);
      await load();
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> update(Appointment appointment) async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.update(appointment);
      await load();
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> changeStatus(Appointment appointment, AppointmentStatus status, {String? reason}) async {
    await _repository.changeStatus(appointment, status, reason: reason);
    await load();
  }

  Future<void> reschedule(Appointment appointment, DateTime newStart) async {
    await _repository.reschedule(appointment, newStart);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }

  Future<List<Appointment>> forCustomer(String customerId) => _repository.fetchForCustomer(customerId);

  Future<List<Appointment>> forDay(DateTime day, {String? employeeId, String? serviceId}) =>
      _repository.fetchForDay(day, employeeId: employeeId, serviceId: serviceId);

  Future<Appointment?> byId(String id) => _repository.findById(id);

  /// یافتن همگام (برای فرم‌ها).
  Appointment? appointmentById(String id) {
    for (final item in _page.items) { if (item.id == id) return item; }
    return null;
  }


}
