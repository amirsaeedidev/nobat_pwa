import '../mock/app_database.dart';
import '../models/service.dart';
import '../models/employee_service_config.dart';
import 'operations_repository.dart';

class ServiceAppointmentSummary {
  const ServiceAppointmentSummary({
    required this.reference,
    required this.title,
    required this.startsAt,
    required this.status,
    required this.price,
  });

  final String reference;
  final String title;
  final DateTime startsAt;
  final String status;
  final num price;
}

class ServiceHistoryPage {
  const ServiceHistoryPage({required this.totalCount, required this.items});
  final int totalCount;
  final List<ServiceAppointmentSummary> items;
}

abstract class ServiceRepository {
  Future<List<Service>> fetchServices({bool onlyActive = false, String query = ''});

  Future<Service?> findById(String id);

  Future<ServiceHistoryPage> fetchServiceHistory(String serviceId, {int limit = 8}) async =>
      const ServiceHistoryPage(totalCount: 0, items: []);

  Future<void> create(Service service);

  Future<void> update(Service service);

  Future<String> saveCatalogItem(Service service, List<EmployeeServiceConfig> configs) async {
    if (service.id.startsWith('srv-')) {
      await create(service);
    } else {
      await update(service);
    }
    for (final config in configs) {
      await saveEmployeeServiceConfig(config);
    }
    return service.id;
  }

  Future<void> delete(String id);

  Future<void> toggle(String id, bool isActive);

  Future<List<String>> fetchCategories();
  Future<void> addCategory(String name);
  Future<void> renameCategory(String oldName, String newName);
  Future<void> deleteCategory(String name, {String? moveServicesTo});

  Future<List<EmployeeServiceConfig>> fetchEmployeeServiceConfigs();
  Future<void> saveEmployeeServiceConfig(EmployeeServiceConfig config);
}

class MockServiceRepository extends ServiceRepository {
  MockServiceRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Service>> fetchServices({bool onlyActive = false, String query = ''}) async {
    await _db.delay(140);
    final q = query.trim();
    return _db.services
        .where((s) => (!onlyActive || s.isActive) && (q.isEmpty || s.title.contains(q)))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<Service?> findById(String id) async => _db.serviceById(id);

  @override
  Future<void> create(Service service) async {
    await _db.delay(220);
    _db.addService(service);
  }

  @override
  Future<void> update(Service service) async {
    await _db.delay(200);
    _db.updateService(service);
  }

  @override
  Future<void> delete(String id) async {
    await _db.delay(180);
    await OperationsRepository(_db).deleteService(id);
  }

  @override
  Future<void> toggle(String id, bool isActive) async {
    await _db.delay(120);
    _db.toggleService(id, isActive);
  }

  @override
  Future<List<String>> fetchCategories() async {
    await _db.delay(60);
    return _db.serviceCategories;
  }

  @override
  Future<void> addCategory(String name) async {
    await _db.delay(80);
    _db.addServiceCategory(name);
  }

  @override
  Future<void> renameCategory(String oldName, String newName) async {
    await _db.delay(80);
    _db.renameServiceCategory(oldName, newName);
  }

  @override
  Future<void> deleteCategory(String name, {String? moveServicesTo}) async {
    await OperationsRepository(_db).deleteServiceCategory(name, moveServicesTo: moveServicesTo);
  }

  @override
  Future<List<EmployeeServiceConfig>> fetchEmployeeServiceConfigs() async {
    await _db.delay(80);
    return _db.employees.expand((employee) => _db.employeeServiceConfigsFor(employee.id)).toList();
  }

  @override
  Future<void> saveEmployeeServiceConfig(EmployeeServiceConfig config) async {
    await _db.delay(80);
    _db.saveEmployeeServiceConfig(config);
  }
}
