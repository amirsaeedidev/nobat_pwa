import '../mock/app_database.dart';
import '../models/employee.dart';
import '../models/employee_schedule.dart';
import 'operations_repository.dart';

abstract class EmployeeRepository {
  Future<List<Employee>> fetchEmployees({bool onlyActive = false, String? serviceId});

  Future<Employee?> findById(String id);

  Future<void> create(Employee employee);

  Future<void> update(Employee employee);

  Future<void> delete(String id);

  Future<List<EmployeeWorkingHour>> fetchWorkingHours({String? employeeId}) async => const [];

  Future<List<BusinessHoliday>> fetchBusinessHolidays({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  Future<List<EmployeeScheduleException>> fetchScheduleExceptions({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async => const [];

  Future<void> saveScheduleException(EmployeeScheduleException exception) async {
    throw UnsupportedError('ذخیره استثنای برنامه کاری پشتیبانی نمی‌شود.');
  }

  Future<void> deleteScheduleException(String employeeId, String dateKey) async {
    throw UnsupportedError('حذف استثنای برنامه کاری پشتیبانی نمی‌شود.');
  }

  Future<List<EmployeeLeave>> fetchLeaves(String employeeId) async => const [];

  Future<void> createLeave(EmployeeLeave leave) async {
    throw UnsupportedError('ثبت مرخصی پشتیبانی نمی‌شود.');
  }

  Future<void> reviewLeave(EmployeeLeave leave) async {
    throw UnsupportedError('بررسی مرخصی پشتیبانی نمی‌شود.');
  }
}

class MockEmployeeRepository extends EmployeeRepository {
  MockEmployeeRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Employee>> fetchEmployees({bool onlyActive = false, String? serviceId}) async {
    await _db.delay(140);
    final canList = _db.hasPermission('employees.view_list');
    if (!canList && !_db.hasPermission('employees.view_profile')) _db.requirePermission('employees.view_list');
    return _db.employees.where((e) {
      if (canList && !_db.canViewEmployee(e.id)) return false;
      if (!canList && e.id != _db.currentAccessAccount.employeeId) return false;
      if (onlyActive && !e.isAvailableForBooking) return false;
      if (serviceId != null && !e.serviceIds.contains(serviceId)) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<EmployeeWorkingHour>> fetchWorkingHours({String? employeeId}) async {
    final employees = await fetchEmployees();
    return employees
        .where((employee) => employeeId == null || employee.id == employeeId)
        .expand((employee) => employee.schedule.entries.expand((entry) =>
            entry.value.map((shift) => EmployeeWorkingHour(
                  employeeId: employee.id,
                  weekday: entry.key,
                  shift: shift,
                ))))
        .toList(growable: false);
  }

  @override
  Future<Employee?> findById(String id) async {
    if (!_db.canViewEmployee(id) || (!_db.hasPermission('employees.view_list') && !_db.hasPermission('employees.view_profile'))) return null;
    return _db.employeeById(id);
  }

  @override
  Future<void> create(Employee employee) async {
    await _db.delay(200);
    _db.addEmployee(employee);
  }

  @override
  Future<void> update(Employee employee) async {
    await _db.delay(180);
    _db.updateEmployee(employee);
  }

  @override
  Future<void> delete(String id) async {
    await _db.delay(160);
    await OperationsRepository(_db).deleteEmployee(id);
  }
}
