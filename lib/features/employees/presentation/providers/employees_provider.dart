import '../../../../core/providers/db_bound_provider.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/employee_repository.dart';

/// مدیریت پرسنل و برنامه کاری در دیتابیس محلی Datamonck.
class EmployeesProvider extends DbBoundProvider {
  EmployeesProvider(this._repository, AppDatabase db) : super(db) {
    load();
  }

  final EmployeeRepository _repository;
  List<Employee> _items = const [];
  bool _loading = true;
  String? _error;

  List<Employee> get items => _items;
  List<Employee> get activeItems => _items.where((e) => e.isAvailableForBooking).toList();
  bool get loading => _loading;
  String? get error => _error;
  int get totalCount => _items.length;
  int get activeCount => _items.where((e) => e.employmentStatus == EmployeeStatus.active).length;
  int get inactiveCount => _items.where((e) => e.employmentStatus == EmployeeStatus.inactive).length;
  int get onLeaveCount => _items.where((e) => e.employmentStatus == EmployeeStatus.onLeave).length;
  int get suspendedCount => _items.where((e) => e.employmentStatus == EmployeeStatus.suspended).length;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repository.fetchEmployees();
    } catch (error) {
      _items = db.employees;
      _error = 'بارگذاری از داده‌های محلی انجام شد.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onDatabaseChanged() {
    _items = db.employees;
    _error = null;
    notifyListeners();
  }

  Future<List<Employee>> forService(String serviceId) => _repository.fetchEmployees(onlyActive: true, serviceId: serviceId);
  Future<Employee?> byId(String id) => _repository.findById(id);

  Employee? byIdSync(String id) {
    for (final employee in _items) {
      if (employee.id == id) return employee;
    }
    return null;
  }

  bool phoneExists(String phone, {String? excludingId}) {
    final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return _items.any((employee) =>
      employee.id != excludingId && employee.phone.replaceAll(RegExp(r'[^0-9]'), '') == normalized);
  }

  Future<bool> create(Employee employee) async {
    if (phoneExists(employee.phone)) return false;
    await _repository.create(employee);
    return true;
  }

  Future<bool> update(Employee employee) async {
    if (phoneExists(employee.phone, excludingId: employee.id)) return false;
    await _repository.update(employee);
    return true;
  }

  Future<bool> remove(String id) async {
    await _repository.delete(id);
    return true;
  }

  String nextId() => 'emp-${DateTime.now().millisecondsSinceEpoch}';
}
