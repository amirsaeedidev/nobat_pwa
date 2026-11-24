import '../../core/models/page_result.dart';
import '../../core/models/app_failure.dart';
import '../mock/app_database.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import 'operations_repository.dart';
import 'appointment_repository.dart';

abstract class CustomerRepository {
  Future<PageResult<Customer>> fetchCustomers({
    String query = '',
    int page = 1,
    int pageSize = 8,
    String sortBy = 'createdAt',
    bool archivedOnly = false,
  });

  Future<List<Customer>> fetchAll({String query = ''});

  Future<Customer?> findById(String id);

  Future<CustomerProfile?> fetchProfile(String id);

  Future<void> create(Customer customer);

  Future<void> update(Customer customer);

  Future<void> delete(String id);
}

class MockCustomerRepository implements CustomerRepository {
  MockCustomerRepository(this._db);

  final AppDatabase _db;

  List<Customer> _filtered(String query, {bool archivedOnly = false}) {
    _db.requirePermission('customers.view');
    final q = query.trim();
    List<Customer> list;
    if (q.isEmpty) {
      list = _db.allCustomers.where((customer) => customer.isArchived == archivedOnly).toList();
    } else {
      final latin = _toLatin(q);
      list = _db.customers.where((c) {
        return c.isArchived == archivedOnly && (c.fullName.contains(q) || c.phone.contains(latin) || c.phone.contains(q));
      }).toList();
    }
    list.sort((a, b) {
      final aDate = a.lastVisitAt;
      final bDate = b.lastVisitAt;
      if (aDate == null && bDate == null) return a.fullName.compareTo(b.fullName);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return list;
  }

  String _toLatin(String input) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final index = fa.indexOf(ch);
      buffer.write(index >= 0 ? index : ch);
    }
    return buffer.toString();
  }

  @override
  Future<PageResult<Customer>> fetchCustomers({
    String query = '',
    int page = 1,
    int pageSize = 8,
    String sortBy = 'createdAt',
    bool archivedOnly = false,
  }) async {
    return await AppFailure.guard(() async {
      await _db.delay(160);
      final list = _filtered(query, archivedOnly: archivedOnly);
      final start = (page - 1) * pageSize;
      if (start >= list.length) {
        return PageResult(items: const [], total: list.length, page: page, pageSize: pageSize);
      }
      final end = (start + pageSize).clamp(0, list.length);
      return PageResult(items: list.sublist(start, end), total: list.length, page: page, pageSize: pageSize);
    }, fallback: AppErrorKind.fetch);
  }

  @override
  Future<List<Customer>> fetchAll({String query = ''}) async => _filtered(query);

  @override
  Future<Customer?> findById(String id) async {
    _db.requirePermission('customers.view');
    return _db.customerById(id);
  }

  @override
  Future<CustomerProfile?> fetchProfile(String id) async {
    final customer = await findById(id);
    if (customer == null) return null;
    final appointments = await MockAppointmentRepository(_db).fetchForCustomer(id);
    final completed = appointments.where((a) => a.status == AppointmentStatus.completed).toList();
    final cancelled = appointments.where((a) => a.status == AppointmentStatus.cancelled).length;
    final noShow = appointments.where((a) => a.status == AppointmentStatus.noShow).length;
    final lastVisit = completed.isEmpty ? null : completed.map((a) => a.startAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final services = completed.expand((a) => a.serviceName.split('،')).map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList()..sort();
    final billed = completed.fold<num>(0, (sum, a) => sum + a.price);
    return CustomerProfile(
      customer: customer.copyWith(
        visitCount: completed.length,
        totalSpent: billed,
        cancelCount: cancelled,
        noShowCount: noShow,
        lastVisitAt: lastVisit,
      ),
      appointments: appointments,
      services: services,
      completedVisits: completed.length,
      cancelledAppointments: cancelled,
      noShowAppointments: noShow,
      lastVisitAt: lastVisit,
      financeVisible: true,
      totalBilled: billed,
      totalPaid: customer.totalSpent,
      outstanding: 0,
    );
  }

  @override
  Future<void> create(Customer customer) async {
    await AppFailure.guard(() async {
      await _db.delay(220);
      _db.addCustomer(customer);
    }, fallback: AppErrorKind.save);
  }

  @override
  Future<void> update(Customer customer) async {
    await AppFailure.guard(() async {
      await _db.delay(200);
      _db.updateCustomer(customer);
    }, fallback: AppErrorKind.save);
  }

  @override
  Future<void> delete(String id) async {
    await AppFailure.guard(() async {
      await _db.delay(160);
      await OperationsRepository(_db).deleteCustomer(id);
    }, fallback: AppErrorKind.save);
  }
}
