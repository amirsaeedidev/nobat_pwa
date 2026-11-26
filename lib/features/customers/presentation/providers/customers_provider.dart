import 'package:flutter/foundation.dart';
import '../../../../core/models/page_result.dart';
import '../../../../core/models/app_failure.dart';
import '../../../../data/models/customer.dart';
import '../../../../data/repositories/customer_repository.dart';

/// مدیریت فهرست مشتریان، جست‌وجو و CRUD.
class CustomersProvider extends ChangeNotifier {
  CustomersProvider(this._repository) {
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

  void search(String value) {
    _query = value;
    _pageNumber = 1;
    load();
  }

  void goToPage(int page) {
    _pageNumber = page.clamp(1, 999);
    load();
  }

  Customer? findById(String id) {
    for (final customer in _page.items) { if (customer.id == id) return customer; }
    return null;
  }

  Future<Customer?> byId(String id) => _repository.findById(id);

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

  Future<Customer> createAndReturn(Customer customer) async {
    _busy = true;
    notifyListeners();
    try {
      final saved = await _repository.createAndReturn(customer);
      await load();
      return saved;
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

  Future<void> delete(String id) async { await _repository.delete(id); await load(); }

  Customer? findByPhone(String phone) {
    for (final customer in _page.items) { if (customer.phone == phone) return customer; }
    return null;
  }

  Future<Customer?> findByPhoneRemote(String phone) async {
    final rows = await _repository.fetchAll(query: phone);
    for (final customer in rows) { if (customer.phone == phone) return customer; }
    return null;
  }


}
