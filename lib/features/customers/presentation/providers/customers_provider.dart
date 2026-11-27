import 'dart:async';
import '../../../../core/models/page_result.dart';
import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/models/app_failure.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/customer.dart';
import '../../../../data/repositories/customer_repository.dart';

/// مدیریت فهرست مشتریان، جست‌وجو و CRUD.
class CustomersProvider extends DbBoundProvider {
  CustomersProvider(this._repository, AppDatabase? db, {SupabaseAuthStateNotifier? authStateNotifier}) : super(authStateNotifier: authStateNotifier, testOnlyLocalChanges: db) {
    load();
  }

  final CustomerRepository _repository;

  PageResult<Customer> _page = PageResult.empty(pageSize: 8);
  String _query = '';
  int _pageNumber = 1;
  final int _pageSize = 8;
  bool _loading = true;
  String? _loadNotice;
  bool _busy = false;
  bool _showArchived = false;

  PageResult<Customer> get page => _page;
  List<Customer> get items => _page.items;
  String get query => _query;
  int get pageNumber => _pageNumber;
  bool get loading => _loading;
  String? get loadNotice => _loadNotice;
  bool get busy => _busy;
  bool get showArchived => _showArchived;
  int get total => _page.total;

  List<Customer> get all => _page.items;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _loadNotice = null;
      _page = await _repository.fetchCustomers(query: _query, page: _pageNumber, pageSize: _pageSize, archivedOnly: _showArchived);
    } catch (error) {
      _loadNotice = AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
      _page = PageResult.empty(pageSize: _pageSize);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onAuthenticatedTenantChanged() => unawaited(load());

  @override
  void onTenantContextCleared() {
    _page = PageResult.empty(pageSize: _pageSize);
    _loading = false;
    _loadNotice = null;
    _busy = false;
    _showArchived = false;
  }

  @override
  void onDatabaseChanged() {
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      _page = await _repository.fetchCustomers(query: _query, page: _pageNumber, pageSize: _pageSize, archivedOnly: _showArchived);
      _loadNotice = null;
    } catch (error) {
      _page = PageResult.empty(pageSize: _pageSize);
      _loadNotice = AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
    }
    notifyListeners();
  }

  Future<void> toggleArchived() async {
    _showArchived = !_showArchived;
    _pageNumber = 1;
    await load();
  }

  void search(String query) {
    _query = query;
    _pageNumber = 1;
    load();
  }

  void goToPage(int page) {
    _pageNumber = page.clamp(1, _page.totalPages == 0 ? 1 : _page.totalPages);
    load();
  }

  Future<Customer?> byId(String id) => _repository.findById(id);

  Future<CustomerProfile?> fetchProfile(String id) => _repository.fetchProfile(id);

  Future<List<Customer>> fetchAll() => _repository.fetchAll();

  Future<Customer?> findByPhoneRemote(String phone) async {
    final normalized = FaNum.toLatin(phone).replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.isEmpty) return null;
    var matches = await _repository.fetchAll(query: phone.trim());
    if (matches.isEmpty) {
      matches = await _repository.fetchAll(query: normalized);
    }
    for (final customer in matches) {
      final candidate = FaNum.toLatin(customer.phone).replaceAll(RegExp(r'[^0-9]'), '');
      if (candidate == normalized) return customer;
    }
    return null;
  }

  Future<bool> create(Customer customer) async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.create(customer);
      await load();
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> update(Customer customer) async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.update(customer);
      await load();
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }

  Customer? findById(String id) {
    for (final c in _page.items) {
      if (c.id == id) return c;
    }
    return null;
  }

  Customer? findByPhone(String phone) {
    for (final c in _page.items) {
      if (c.phone == phone) return c;
    }
    return null;
  }
}
