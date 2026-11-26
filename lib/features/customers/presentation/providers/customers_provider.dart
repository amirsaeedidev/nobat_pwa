import '../../../../core/models/page_result.dart';
import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/models/app_failure.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/customer.dart';
import '../../../../data/repositories/customer_repository.dart';

/// مدیریت فهرست مشتریان، جست‌وجو و CRUD.
class CustomersProvider extends DbBoundProvider {
  CustomersProvider(this._repository, AppDatabase db) : super(db) {
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

  PageResult<Customer> get page => _page;
  List<Customer> get items => _page.items;
  String get query => _query;
  int get pageNumber => _pageNumber;
  bool get loading => _loading;
  String? get loadNotice => _loadNotice;
  bool get busy => _busy;
  int get total => _page.total;

  List<Customer> get all => _page.items;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _loadNotice = null;
      _page = await _repository.fetchCustomers(query: _query, page: _pageNumber, pageSize: _pageSize);
    } catch (error) {
      _loadNotice = AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
      _page = PageResult.empty(pageSize: _pageSize);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onDatabaseChanged() {
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      _page = await _repository.fetchCustomers(query: _query, page: _pageNumber, pageSize: _pageSize);
      _loadNotice = null;
    } catch (error) {
      _loadNotice = AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
      _page = PageResult.empty(pageSize: _pageSize);
    }
    notifyListeners();
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

  Future<bool> create(Customer customer) async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.create(customer);
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
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> delete(String id) => _repository.delete(id);

  Future<Customer?> findByPhone(String phone) async {
    final rows = await _repository.fetchAll(query: phone);
    for (final customer in rows) { if (customer.phone == phone) return customer; }
    return null;
  }


}
