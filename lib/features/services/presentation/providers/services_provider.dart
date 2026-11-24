import 'dart:async';
import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/models/app_failure.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/service.dart';
import '../../../../data/models/employee_service_config.dart';
import '../../../../data/repositories/service_repository.dart';

/// مدیریت خدمات.
class ServicesProvider extends DbBoundProvider {
  ServicesProvider(this._repository, AppDatabase db, {SupabaseAuthStateNotifier? authStateNotifier}) : super(db, authStateNotifier: authStateNotifier) {
    load();
  }

  final ServiceRepository _repository;

  List<Service> _items = const [];
  List<String> _categories = const [];
  final Map<String, EmployeeServiceConfig> _employeeConfigs = {};
  bool _loading = true;
  String? _loadNotice;
  String _query = '';
  bool _activeOnly = false;
  bool _inactiveOnly = false;
  String? _categoryFilter;
  num? _minimumPrice;
  num? _maximumPrice;

  List<Service> get items => _items;
  bool get loading => _loading;
  String? get loadNotice => _loadNotice;
  String get query => _query;
  bool get activeOnly => _activeOnly;
  bool get inactiveOnly => _inactiveOnly;
  List<String> get categories => _categories;
  EmployeeServiceConfig? employeeServiceConfig(String employeeId, String serviceId) =>
      _employeeConfigs['$employeeId::$serviceId'];
  String? get categoryFilter => _categoryFilter;
  num? get minimumPrice => _minimumPrice;
  num? get maximumPrice => _maximumPrice;
  List<Service> get activeServices => _items.where((s) => s.isActive).toList();
  int get activeCount => _items.where((s) => s.isActive).length;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.fetchServices(onlyActive: _activeOnly),
        _repository.fetchCategories(),
        _repository.fetchEmployeeServiceConfigs(),
      ]);
      _loadNotice = null;
      _items = results[0] as List<Service>;
      _categories = results[1] as List<String>;
      _employeeConfigs
        ..clear()
        ..addEntries((results[2] as List<EmployeeServiceConfig>).map(
          (config) => MapEntry('${config.employeeId}::${config.serviceId}', config),
        ));
    } catch (error) {
      _loadNotice = AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
      _items = const [];
      _categories = const [];
      _employeeConfigs.clear();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onAuthenticatedTenantChanged() => unawaited(load());

  @override
  void onTenantContextCleared() {
    _items = const [];
    _categories = const [];
    _employeeConfigs.clear();
    _loading = false;
    _loadNotice = null;
  }

  @override
  void onDatabaseChanged() {
    _items = db.services;
    _categories = db.serviceCategories;
    _employeeConfigs
      ..clear()
      ..addEntries(db.employees
          .expand((employee) => db.employeeServiceConfigsFor(employee.id))
          .map((config) => MapEntry('${config.employeeId}::${config.serviceId}', config)));
    notifyListeners();
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  void setActiveOnly(bool value) {
    _activeOnly = value;
    _inactiveOnly = false;
    load();
  }

  void setInactiveOnly(bool value) {
    _inactiveOnly = value;
    _activeOnly = false;
    load();
  }

  void setCategoryFilter(String? value) { _categoryFilter = value; notifyListeners(); }

  void setPriceRange({num? minimum, num? maximum}) {
    _minimumPrice = minimum;
    _maximumPrice = maximum;
    notifyListeners();
  }

  List<Service> get filtered {
    final q = _query.trim();
    return _items.where((s) {
      if (_activeOnly && !s.isActive) return false;
      if (_inactiveOnly && s.isActive) return false;
      if (_categoryFilter != null && s.category != _categoryFilter) return false;
      if (_minimumPrice != null && s.price < _minimumPrice!) return false;
      if (_maximumPrice != null && s.price > _maximumPrice!) return false;
      if (q.isEmpty) return true;
      return s.title.contains(q) || s.category.contains(q);
    }).toList();
  }

  Future<Service?> byId(String id) => _repository.findById(id);

  Future<bool> create(Service service) async {
    await _repository.create(service);
    return true;
  }

  Future<bool> update(Service service) async {
    await _repository.update(service);
    return true;
  }

  Future<void> remove(String id) => _repository.delete(id);

  Future<void> toggle(String id, bool active) => _repository.toggle(id, active);

  Future<void> addCategory(String name) async {
    await _repository.addCategory(name);
    _categories = await _repository.fetchCategories();
    notifyListeners();
  }

  Future<void> renameCategory(String oldName, String newName) async {
    await _repository.renameCategory(oldName, newName);
    _categories = await _repository.fetchCategories();
    if (_categoryFilter == oldName) _categoryFilter = newName.trim();
    notifyListeners();
  }

  Future<void> deleteCategory(String name, {String? moveServicesTo}) async {
    await _repository.deleteCategory(name, moveServicesTo: moveServicesTo);
    _categories = await _repository.fetchCategories();
    if (_categoryFilter == name) _categoryFilter = null;
    await load();
  }

  Future<void> saveEmployeeServiceConfig(EmployeeServiceConfig config) async {
    await _repository.saveEmployeeServiceConfig(config);
    _employeeConfigs['${config.employeeId}::${config.serviceId}'] = config;
    notifyListeners();
  }

  String nextId() => 'srv-${DateTime.now().millisecondsSinceEpoch}';
}
