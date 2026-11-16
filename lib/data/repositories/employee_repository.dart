import '../mock/app_database.dart';
import '../models/employee.dart';

abstract class EmployeeRepository {
  Future<List<Employee>> fetchEmployees({bool onlyActive = false, String? serviceId});

  Future<Employee?> findById(String id);

  Future<void> create(Employee employee);

  Future<void> update(Employee employee);

  Future<void> delete(String id);
}

class MockEmployeeRepository implements EmployeeRepository {
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
    _db.deleteEmployee(id);
  }
}
