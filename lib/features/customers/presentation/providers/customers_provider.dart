import 'package:flutter/foundation.dart';

import '../../../../core/models/page_result.dart';
import '../../../../core/models/app_failure.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/customer.dart';
import '../../../../data/repositories/customer_repository.dart';

class CustomerProfileData {
  const CustomerProfileData({
    required this.customer,
    required this.appointments,
  });

  final Customer customer;
  final List<Appointment> appointments;
}

/// مدیریت فهرست، جست‌وجو، صفحه‌بندی و پروفایل مشتریان.
/// خطای شبکه یا Supabase هرگز با داده محلی جایگزین نمی‌شود.
class CustomersProvider extends ChangeNotifier {
  CustomersProvider(this._repository, [Object? _legacyDatabase]) {
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
  int _loadGeneration = 0;

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
    final maxPage = _page.totalPages == 0 ? 1 : _page.totalPages;
    _pageNumber = page.clamp(1, maxPage);
    load();
  }

  Customer? findById(String id) {
    for (final customer in _page.items) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  Future<Customer?> byId(String id) => _repository.findById(id);

  Future<CustomerProfileData?> profileById(String id) async {
    final customer = await _repository.findById(id);
    if (customer == null) return null;
    final appointments =
        await _repository.fetchAppointmentsForCustomer(customer);
    return CustomerProfileData(
      customer: customer,
      appointments: appointments,
    );
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    notifyListeners();
    try {
      _loadNotice = null;
      final result = await _repository.fetchCustomers(
        query: _query,
        page: _pageNumber,
        pageSize: _pageSize,
      );
      if (generation != _loadGeneration) return;
      _page = result;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _loadNotice =
          AppFailure.from(error, fallback: AppErrorKind.fetch).persianMessage;
      _page = PageResult.empty(pageSize: _pageSize);
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
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

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }

  Customer? findByPhone(String phone) {
    for (final customer in _page.items) {
      if (customer.phone == phone) return customer;
    }
    return null;
  }

  Future<Customer?> findByPhoneRemote(String phone) async {
    final rows = await _repository.fetchAll(query: phone);
    for (final customer in rows) {
      if (customer.phone == phone) return customer;
    }
    return null;
  }
}
