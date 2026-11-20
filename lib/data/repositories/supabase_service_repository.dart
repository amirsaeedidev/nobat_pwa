import '../models/employee_service_config.dart';
import '../models/service.dart';
import 'service_repository.dart';
import 'supabase_repository.dart';

/// Remote implementation of the service catalog backed by tenant-scoped
/// app_records. The default application mode remains MockServiceRepository,
/// so the UI continues to work fully offline.
class SupabaseServiceRepository implements ServiceRepository {
  SupabaseServiceRepository({
    required SupabaseRepository records,
    required this.businessId,
  }) : _records = records;

  final SupabaseRepository _records;
  final String businessId;

  static const _services = 'services';
  static const _categoryPrefix = '__category__::';
  static const _employeeServices = 'employee_services';
  static const _employees = 'employees';
  static const _appointments = 'appointments';

  String _configId(String employeeId, String serviceId) => '$employeeId::$serviceId';
  String _categoryId(String name) => '$_categoryPrefix$name';

  @override
  Future<List<Service>> fetchServices({bool onlyActive = false, String query = ''}) async {
    final normalizedQuery = query.trim().toLowerCase();
    final rows = await _records.fetchRecords(businessId: businessId, entityType: _services);
    return rows
        .where((row) => !(row['id'] as String? ?? '').startsWith(_categoryPrefix))
        .map(Service.fromJson)
        .where((service) => (!onlyActive || service.isActive) &&
            (normalizedQuery.isEmpty ||
                service.title.toLowerCase().contains(normalizedQuery) ||
                service.category.toLowerCase().contains(normalizedQuery)))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<Service?> findById(String id) async {
    final row = await _records.fetchRecord(
      businessId: businessId,
      entityType: _services,
      recordId: id,
    );
    return row == null ? null : Service.fromJson(row);
  }

  @override
  Future<void> create(Service service) async {
    final existing = await findById(service.id);
    if (existing != null) throw StateError('شناسه خدمت در Supabase تکراری است.');
    await _records.upsertRecord(
      businessId: businessId,
      entityType: _services,
      recordId: service.id,
      payload: service.toJson(),
    );
    await _syncEmployeeLinks(service);
    await upsertServiceCategory(service.category);
  }

  @override
  Future<void> update(Service service) async {
    if (await findById(service.id) == null) {
      throw StateError('خدمت مورد نظر در Supabase پیدا نشد.');
    }
    await _records.upsertRecord(
      businessId: businessId,
      entityType: _services,
      recordId: service.id,
      payload: service.toJson(),
    );
    await _syncEmployeeLinks(service);
    await upsertServiceCategory(service.category);
  }

  @override
  Future<void> delete(String id) async {
    final service = await findById(id);
    if (service == null) return;

    final appointments = await _records.fetchRecords(
      businessId: businessId,
      entityType: _appointments,
    );
    final hasHistory = appointments.any((row) {
      final ids = (row['service_ids'] as List? ?? const []).map((value) => value.toString());
      return ids.contains(id);
    });

    if (hasHistory) {
      await update(service.copyWith(isActive: false, employeeIds: const []));
      return;
    }

    final configs = await fetchEmployeeServiceConfigs();
    for (final config in configs.where((item) => item.serviceId == id)) {
      await _records.deleteRecord(
        businessId: businessId,
        entityType: _employeeServices,
        recordId: _configId(config.employeeId, id),
      );
    }
    await _records.deleteRecord(
      businessId: businessId,
      entityType: _services,
      recordId: id,
    );
    await _syncEmployeeLinks(service.copyWith(employeeIds: const []));
  }

  @override
  Future<void> toggle(String id, bool isActive) async {
    final service = await findById(id);
    if (service == null) throw StateError('خدمت مورد نظر پیدا نشد.');
    await update(service.copyWith(isActive: isActive));
  }

  Future<List<String>> fetchServiceCategories() async {
    final rows = await _records.fetchRecords(
      businessId: businessId,
      entityType: _services,
    );
    return rows
        .where((row) => (row['id'] as String? ?? '').startsWith(_categoryPrefix))
        .where((row) => row['is_active'] != false)
        .map((row) => (row['name'] as String? ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> createServiceCategory(String name) async {
    await upsertServiceCategory(name);
  }

  Future<void> upsertServiceCategory(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError('نام دسته‌بندی الزامی است.');
    final categories = await fetchServiceCategories();
    if (categories.any((item) => item.toLowerCase() == normalized.toLowerCase())) {
      if (categories.contains(normalized)) return;
      throw StateError('دسته‌بندی دیگری با همین نام وجود دارد.');
    }
    await _records.upsertRecord(
      businessId: businessId,
      entityType: _services,
      recordId: _categoryId(normalized),
      payload: {'name': normalized, 'is_active': true, 'record_kind': 'service_category'},
    );
  }

  Future<void> renameServiceCategory(String oldName, String newName) async {
    final normalized = newName.trim();
    if (normalized.isEmpty) throw ArgumentError('نام دسته‌بندی الزامی است.');
    final categories = await fetchServiceCategories();
    if (!categories.contains(oldName)) throw StateError('دسته‌بندی پیدا نشد.');
    if (categories.any((item) => item.toLowerCase() == normalized.toLowerCase())) {
      throw StateError('دسته‌بندی دیگری با همین نام وجود دارد.');
    }
    final services = await fetchServices();
    for (final service in services.where((item) => item.category == oldName)) {
      await update(service.copyWith(category: normalized));
    }
    await upsertServiceCategory(normalized);
    await _records.upsertRecord(
      businessId: businessId,
      entityType: _services,
      recordId: _categoryId(oldName),
      payload: {'name': oldName, 'is_active': false, 'record_kind': 'service_category'},
    );
  }

  Future<void> deleteServiceCategory(String name, {String? moveServicesTo}) async {
    final categories = await fetchServiceCategories();
    if (!categories.contains(name)) return;
    final services = await fetchServices();
    final dependents = services.where((service) => service.category == name).toList();
    if (dependents.isNotEmpty) {
      final target = moveServicesTo?.trim();
      if (target == null || target.isEmpty || target == name || !categories.contains(target)) {
        throw StateError('این دسته‌بندی دارای خدمت وابسته است؛ ابتدا دسته‌بندی مقصد را مشخص کنید.');
      }
      for (final service in dependents) {
        await update(service.copyWith(category: target));
      }
    }
    await _records.upsertRecord(
      businessId: businessId,
      entityType: _services,
      recordId: _categoryId(name),
      payload: {'name': name, 'is_active': false, 'record_kind': 'service_category'},
    );
  }

  Future<List<EmployeeServiceConfig>> fetchEmployeeServiceConfigs() async {
    final rows = await _records.fetchRecords(
      businessId: businessId,
      entityType: _employeeServices,
    );
    return rows.map(EmployeeServiceConfig.fromJson).toList(growable: false);
  }

  Future<void> upsertEmployeeServiceConfig(EmployeeServiceConfig config) async {
    await _records.upsertRecord(
      businessId: businessId,
      entityType: _employeeServices,
      recordId: _configId(config.employeeId, config.serviceId),
      payload: config.toJson(),
    );
    await _syncEmployeeServiceIds(config.employeeId);
  }

  Future<void> _syncEmployeeLinks(Service service) async {
    final configs = await fetchEmployeeServiceConfigs();
    final assigned = service.employeeIds.toSet();
    final existing = configs.where((item) => item.serviceId == service.id);
    for (final config in existing) {
      final shouldBeActive = assigned.contains(config.employeeId);
      if (config.active != shouldBeActive) {
        await _records.upsertRecord(
          businessId: businessId,
          entityType: _employeeServices,
          recordId: _configId(config.employeeId, service.id),
          payload: config.copyWith(active: shouldBeActive).toJson(),
        );
      }
    }
    for (final employeeId in assigned) {
      if (!existing.any((item) => item.employeeId == employeeId)) {
        final config = EmployeeServiceConfig(employeeId: employeeId, serviceId: service.id);
        await _records.upsertRecord(
          businessId: businessId,
          entityType: _employeeServices,
          recordId: _configId(employeeId, service.id),
          payload: config.toJson(),
        );
      }
    }

    final employeeRows = await _records.fetchRecords(
      businessId: businessId,
      entityType: _employees,
    );
    for (final row in employeeRows) {
      final employeeId = row['id'] as String?;
      if (employeeId == null) continue;
      final ids = (row['service_ids'] as List? ?? const []).map((value) => value.toString()).toSet();
      if (assigned.contains(employeeId)) {
        ids.add(service.id);
      } else {
        ids.remove(service.id);
      }
      await _records.upsertRecord(
        businessId: businessId,
        entityType: _employees,
        recordId: employeeId,
        payload: {...row, 'service_ids': ids.toList()},
      );
    }
  }

  Future<void> _syncEmployeeServiceIds(String employeeId) async {
    final configs = await fetchEmployeeServiceConfigs();
    final serviceIds = configs
        .where((item) => item.employeeId == employeeId && item.active)
        .map((item) => item.serviceId)
        .toSet();
    final employee = await _records.fetchRecord(
      businessId: businessId,
      entityType: _employees,
      recordId: employeeId,
    );
    if (employee == null) return;
    await _records.upsertRecord(
      businessId: businessId,
      entityType: _employees,
      recordId: employeeId,
      payload: {...employee, 'service_ids': serviceIds.toList()},
    );
  }
}
