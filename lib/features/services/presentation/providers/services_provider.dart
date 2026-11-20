import '../../../../core/providers/db_bound_provider.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/service.dart';
import '../../../../data/repositories/service_repository.dart';

/// مدیریت خدمات.
class ServicesProvider extends DbBoundProvider {
  ServicesProvider(this._repository, AppDatabase db) : super(db) {
    load();
  }

  final ServiceRepository _repository;

  List<Service> _items = const [];
  bool _loading = true;
  String _query = '';
  bool _activeOnly = false;
  String? _categoryFilter;
  num? _minimumPrice;
  num? _maximumPrice;

  List<Service> get items => _items;
  bool get loading => _loading;
  String get query => _query;
  bool get activeOnly => _activeOnly;
  List<String> get categories => db.serviceCategories;
  String? get categoryFilter => _categoryFilter;
  num? get minimumPrice => _minimumPrice;
  num? get maximumPrice => _maximumPrice;
  List<Service> get activeServices => _items.where((s) => s.isActive).toList();
  int get activeCount => _items.where((s) => s.isActive).length;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _items = await _repository.fetchServices(onlyActive: _activeOnly);
    } catch (_) {
      _items = db.services;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onDatabaseChanged() {
    _items = db.services;
    notifyListeners();
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  void setActiveOnly(bool value) {
    _activeOnly = value;
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

  void addCategory(String name) { db.addServiceCategory(name); notifyListeners(); }
  void renameCategory(String oldName, String newName) { db.renameServiceCategory(oldName, newName); notifyListeners(); }
  void deleteCategory(String name, {String? moveServicesTo}) {
    db.deleteServiceCategory(name, moveServicesTo: moveServicesTo);
    notifyListeners();
  }

  String nextId() => 'srv-${DateTime.now().millisecondsSinceEpoch}';
}
