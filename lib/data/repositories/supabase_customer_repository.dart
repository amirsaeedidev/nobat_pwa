import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/page_result.dart';
import '../models/appointment.dart';
import '../models/customer.dart';
import 'customer_repository.dart';

/// Resolves exactly one active business for the authenticated user.
/// No local or first-membership fallback is permitted.
class SupabaseCustomerTenantScope {
  SupabaseCustomerTenantScope(this.client);

  final SupabaseClient client;
  String? _cachedUserId;
  String? _cachedBusinessId;

  Future<String> get businessId async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('برای مشاهده اطلاعات مشتریان ابتدا وارد حساب شوید.');
    }

    if (_cachedUserId != user.id) {
      _cachedUserId = user.id;
      _cachedBusinessId = null;
    }
    if (_cachedBusinessId != null) return _cachedBusinessId!;

    final memberships = await client
        .from('business_memberships')
        .select('business_id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .limit(2);

    if (memberships.length != 1) {
      throw StateError(
        memberships.isEmpty
            ? 'برای حساب شما مجموعه فعالی ثبت نشده است.'
            : 'چند مجموعه فعال یافت شد؛ ابتدا باید مجموعه انتخاب شود.',
      );
    }

    _cachedBusinessId = memberships.single['business_id'] as String;
    return _cachedBusinessId!;
  }
}

/// Customer data access backed only by Supabase and protected by RLS.
class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository(this.client, this.scope);

  final SupabaseClient client;
  final SupabaseCustomerTenantScope scope;

  static const int _maxPageSize = 500;

  String _normalizeDigits(String value) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final result = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final faIndex = fa.indexOf(char);
      final arIndex = ar.indexOf(char);
      if (faIndex >= 0) {
        result.write(faIndex);
      } else if (arIndex >= 0) {
        result.write(arIndex);
      } else {
        result.write(char);
      }
    }
    return result.toString();
  }

  String _escapeFilter(String value) => value
      .replaceAll(r'\\', r'\\\\')
      .replaceAll('%', r'\\%')
      .replaceAll('_', r'\\_')
      .replaceAll(',', r'\\,')
      .replaceAll('(', r'\\(')
      .replaceAll(')', r'\\)');

  dynamic _applySearch(dynamic query, String value) {
    final term = _escapeFilter(value.trim());
    if (term.isEmpty) return query;
    final phoneTerm = _escapeFilter(_normalizeDigits(value.trim()));
    return query.or(
      'full_name.ilike.%$term%,phone.ilike.%$phoneTerm%,normalized_phone.ilike.%$phoneTerm%',
    );
  }

  Customer _mapCustomer(
    Map<String, dynamic> row, {
    List<Map<String, dynamic>> appointments = const [],
  }) {
    final completed = appointments
        .where((item) => item['status'] == 'completed')
        .toList(growable: false);
    final cancelled = appointments
        .where((item) =>
            item['status'] == 'cancelled' || item['status'] == 'rejected')
        .length;
    final noShow =
        appointments.where((item) => item['status'] == 'no_show').length;
    final visits = completed
        .map((item) =>
            DateTime.tryParse(item['starts_at']?.toString() ?? ''))
        .whereType<DateTime>()
        .toList()
      ..sort();

    final spent = completed.fold<num>(
      0,
      (sum, item) => sum + ((item['price_toman'] as num?) ?? 0),
    );

    return Customer(
      id: row['id'].toString(),
      fullName: row['full_name'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      tags: (row['tags'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      visitCount: completed.length,
      totalSpent: spent,
      cancelCount: cancelled,
      noShowCount: noShow,
      lastVisitAt: visits.isEmpty ? null : visits.last,
      isArchived: row['is_active'] == false,
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> _appointmentsByCustomer(
    String businessId,
    List<String> customerIds,
  ) async {
    if (customerIds.isEmpty) return const {};

    final rows = await client
        .from('appointments')
        .select('customer_id,starts_at,status,price_toman')
        .eq('business_id', businessId)
        .inFilter('customer_id', customerIds)
        .isFilter('deleted_at', null);

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      grouped
          .putIfAbsent(row['customer_id'].toString(), () => <Map<String, dynamic>>[])
          .add(row);
    }
    return grouped;
  }

  Future<List<Map<String, dynamic>>> _fetchCustomerRows({
    required String businessId,
    required String query,
    required int offset,
    required int limit,
  }) async {
    var request = client
        .from('customers')
        .select()
        .eq('business_id', businessId)
        .eq('is_active', true);
    request = _applySearch(request, query) as dynamic;
    return await request
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
  }

  @override
  Future<PageResult<Customer>> fetchCustomers({
    String query = '',
    int page = 1,
    int pageSize = 8,
    String sortBy = 'createdAt',
  }) async {
    if (page < 1 || pageSize < 1) {
      throw ArgumentError('شماره صفحه و اندازه صفحه باید مثبت باشند.');
    }

    final businessId = await scope.businessId;
    final safePageSize = pageSize.clamp(1, _maxPageSize);
    final offset = (page - 1) * safePageSize;

    var request = client
        .from('customers')
        .select()
        .count(CountOption.exact)
        .eq('business_id', businessId)
        .eq('is_active', true);
    request = _applySearch(request, query) as dynamic;

    final response = await request
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + safePageSize - 1);

    final rows = response.data;
    final total = response.count ?? rows.length;
    final ids = rows.map((row) => row['id'].toString()).toList();
    final appointments = await _appointmentsByCustomer(businessId, ids);

    final customers = rows.map<Customer>((raw) {
      final row = Map<String, dynamic>.from(raw);
      return _mapCustomer(
        row,
        appointments: appointments[row['id'].toString()] ?? const [],
      );
    }).toList(growable: false);

    return PageResult<Customer>(
      items: customers,
      total: total,
      page: page,
      pageSize: safePageSize,
    );
  }

  @override
  Future<List<Customer>> fetchAll({String query = ''}) async {
    final businessId = await scope.businessId;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;

    while (true) {
      final batch = await _fetchCustomerRows(
        businessId: businessId,
        query: query,
        offset: offset,
        limit: _maxPageSize,
      );
      rows.addAll(batch.map((row) => Map<String, dynamic>.from(row)));
      if (batch.length < _maxPageSize) break;
      offset += _maxPageSize;
    }

    final appointments = await _appointmentsByCustomer(
      businessId,
      rows.map((row) => row['id'].toString()).toList(),
    );

    return rows
        .map((row) => _mapCustomer(
              row,
              appointments: appointments[row['id'].toString()] ?? const [],
            ))
        .toList(growable: false);
  }

  @override
  Future<Customer?> findById(String id) async {
    final businessId = await scope.businessId;
    final row = await client
        .from('customers')
        .select()
        .eq('business_id', businessId)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;

    final appointmentRows = await client
        .from('appointments')
        .select('customer_id,starts_at,status,price_toman')
        .eq('business_id', businessId)
        .eq('customer_id', id)
        .isFilter('deleted_at', null);

    return _mapCustomer(
      Map<String, dynamic>.from(row),
      appointments: appointmentRows
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }

  @override
  Future<Customer> createAndReturn(Customer customer) async {
    final businessId = await scope.businessId;
    final row = await client
        .from('customers')
        .insert({
          'business_id': businessId,
          'full_name': customer.fullName.trim(),
          'phone': _normalizeDigits(customer.phone.trim()),
          'notes': customer.notes,
          'tags': customer.tags,
          'is_active': !customer.isArchived,
        })
        .select()
        .single();
    return _mapCustomer(Map<String, dynamic>.from(row));
  }

  @override
  Future<void> create(Customer customer) async {
    await createAndReturn(customer);
  }

  @override
  Future<void> update(Customer customer) async {
    final businessId = await scope.businessId;
    final row = await client
        .from('customers')
        .update({
          'full_name': customer.fullName.trim(),
          'phone': _normalizeDigits(customer.phone.trim()),
          'notes': customer.notes,
          'tags': customer.tags,
          'is_active': !customer.isArchived,
        })
        .eq('business_id', businessId)
        .eq('id', customer.id)
        .select('id')
        .maybeSingle();

    if (row == null) {
      throw StateError('مشتری یافت نشد یا مجوز ویرایش آن را ندارید.');
    }
  }

  @override
  Future<void> delete(String id) async {
    final businessId = await scope.businessId;
    final row = await client
        .from('customers')
        .update({'is_active': false})
        .eq('business_id', businessId)
        .eq('id', id)
        .eq('is_active', true)
        .select('id')
        .maybeSingle();

    if (row == null) {
      throw StateError('مشتری یافت نشد یا قبلاً بایگانی شده است.');
    }
  }

  @override
  Future<List<Appointment>> fetchAppointmentsForCustomer(
    Customer customer,
  ) async {
    final businessId = await scope.businessId;
    final rows = await client
        .from('appointments')
        .select(
          'id,reference,customer_id,employee_id,starts_at,ends_at,status,'
          'note,price_toman,created_at,updated_at,reschedule_count,cancel_reason,created_by',
        )
        .eq('business_id', businessId)
        .eq('customer_id', customer.id)
        .isFilter('deleted_at', null)
        .order('starts_at', ascending: false);

    if (rows.isEmpty) return const [];

    final appointmentIds = rows.map((row) => row['id'].toString()).toList();
    final employeeIds = rows
        .map((row) => row['employee_id'].toString())
        .toSet()
        .toList();

    final employeeRows = employeeIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await client
            .from('employees')
            .select('id,full_name')
            .eq('business_id', businessId)
            .inFilter('id', employeeIds);

    final serviceRows = await client
        .from('appointment_services')
        .select('appointment_id,service_id,title_snapshot,sort_order')
        .eq('business_id', businessId)
        .inFilter('appointment_id', appointmentIds)
        .order('sort_order');

    final employeeNames = <String, String>{
      for (final row in employeeRows)
        row['id'].toString(): row['full_name'] as String? ?? '',
    };
    final servicesByAppointment = <String, List<Map<String, dynamic>>>{};
    for (final raw in serviceRows) {
      final row = Map<String, dynamic>.from(raw);
      servicesByAppointment
          .putIfAbsent(
            row['appointment_id'].toString(),
            () => <Map<String, dynamic>>[],
          )
          .add(row);
    }

    return rows.map<Appointment>((raw) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['id'].toString();
      final start = DateTime.parse(row['starts_at'].toString()).toLocal();
      final end = DateTime.parse(row['ends_at'].toString()).toLocal();
      final services = servicesByAppointment[id] ?? const [];
      final statusKey = switch (row['status']?.toString()) {
        'no_show' => 'noShow',
        'rejected' => 'cancelled',
        final value => value ?? 'pending',
      };

      return Appointment(
        id: id,
        reference: row['reference']?.toString() ?? '',
        customerId: customer.id,
        customerName: customer.fullName,
        customerPhone: customer.phone,
        serviceIds: services
            .map((service) => service['service_id'].toString())
            .toList(growable: false),
        serviceName: services
            .map((service) => service['title_snapshot']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .join('، '),
        employeeId: row['employee_id'].toString(),
        employeeName: employeeNames[row['employee_id'].toString()] ?? '',
        startAt: start,
        durationMinutes: end.difference(start).inMinutes,
        status: AppointmentStatus.fromKey(statusKey),
        note: row['note'] as String? ?? '',
        price: row['price_toman'] as num? ?? 0,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
        rescheduleCount: (row['reschedule_count'] as num?)?.toInt() ?? 0,
        cancelReason: row['cancel_reason'] as String?,
        createdBy: row['created_by']?.toString() ?? '',
        serviceSnapshots: services,
      );
    }).toList(growable: false);
  }
}

/// Explicit offline/unconfigured state: never substitute local customer data.
class UnavailableCustomerRepository implements CustomerRepository {
  Never _unavailable() =>
      throw StateError('اتصال واقعی مشتریان به Supabase در دسترس نیست.');

  @override
  Future<PageResult<Customer>> fetchCustomers({
    String query = '',
    int page = 1,
    int pageSize = 8,
    String sortBy = 'createdAt',
  }) async =>
      _unavailable();

  @override
  Future<List<Customer>> fetchAll({String query = ''}) async => _unavailable();

  @override
  Future<Customer?> findById(String id) async => _unavailable();

  @override
  Future<Customer> createAndReturn(Customer customer) async => _unavailable();

  @override
  Future<void> create(Customer customer) async => _unavailable();

  @override
  Future<void> update(Customer customer) async => _unavailable();

  @override
  Future<void> delete(String id) async => _unavailable();

  @override
  Future<List<Appointment>> fetchAppointmentsForCustomer(
    Customer customer,
  ) async =>
      _unavailable();
}
