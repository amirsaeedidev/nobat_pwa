import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/page_result.dart';
import '../../core/utils/fa_num.dart';
import '../models/appointment.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import 'customer_repository.dart';

/// Customer data is read and written only through the authenticated tenant's
/// Supabase rows. RLS remains the final authorization boundary.
class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository({
    required SupabaseClient client,
    required String? Function() businessId,
    required bool Function() canViewFinance,
  })  : _client = client,
        _businessId = businessId,
        _canViewFinance = canViewFinance;

  final SupabaseClient _client;
  final String? Function() _businessId;
  final bool Function() _canViewFinance;

  static const _customerColumns =
      'id,full_name,phone,notes,tags,is_active,created_at';

  static const _appointmentColumns =
      'id,reference,customer_id,employee_id,starts_at,ends_at,status,note,price_toman,discount_toman,reschedule_count,cancel_reason,created_at,updated_at,customers(full_name,phone),employees(full_name),appointment_services(service_id,title_snapshot,duration_minutes,price_toman,sort_order)';

  String _tenant() {
    if (_client.auth.currentUser == null) {
      throw StateError('نشست Supabase منقضی شده است؛ دوباره وارد شوید.');
    }
    final id = _businessId();
    if (id == null || id.isEmpty) {
      throw StateError('عضویت فعال مجموعه تأیید نشده است.');
    }
    return id;
  }

  String _normalizedPhone(String value) {
    return FaNum.toLatin(value).replaceAll(RegExp(r'[^0-9+]'), '');
  }

  String _safeFilterValue(String value) {
    return value
        .replaceAll(',', ' ')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .trim();
  }

  Map<String, dynamic> _customerJson(Map<String, dynamic> row) => {
        'id': row['id'],
        'full_name': row['full_name'],
        'phone': row['phone'],
        'notes': row['notes'],
        'tags': row['tags'],
        'created_at': row['created_at'],
        'is_archived': row['is_active'] == false,
      };

  Customer _customer(Map<String, dynamic> row) =>
      Customer.fromJson(_customerJson(row));

  Appointment _appointment(Map<String, dynamic> row) {
    final rawCustomer = row['customers'];
    final customer = rawCustomer is Map
        ? Map<String, dynamic>.from(rawCustomer)
        : <String, dynamic>{};
    final rawEmployee = row['employees'];
    final employee = rawEmployee is Map
        ? Map<String, dynamic>.from(rawEmployee)
        : <String, dynamic>{};
    final services = (row['appointment_services'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((a, b) => ((a['sort_order'] as num?) ?? 0)
          .compareTo((b['sort_order'] as num?) ?? 0));
    final start = DateTime.parse(row['starts_at'] as String).toLocal();
    final end = DateTime.parse(row['ends_at'] as String).toLocal();
    final rawStatus = row['status'] as String? ?? 'pending';
    final status = rawStatus == 'rejected'
        ? AppointmentStatus.cancelled
        : AppointmentStatus.fromKey(
            rawStatus == 'no_show' ? 'noShow' : rawStatus,
          );
    final names = services
        .map((item) => item['title_snapshot'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return Appointment(
      id: row['id'] as String,
      reference: row['reference'] as String? ?? '',
      customerId: row['customer_id'] as String,
      customerName: customer['full_name'] as String? ?? '',
      customerPhone: customer['phone'] as String? ?? '',
      serviceIds: services
          .map((item) => item['service_id'] as String)
          .toList(growable: false),
      serviceName: names.join('، '),
      employeeId: row['employee_id'] as String,
      employeeName: employee['full_name'] as String? ?? '',
      startAt: start,
      durationMinutes: end.difference(start).inMinutes,
      status: status,
      note: row['note'] as String? ?? '',
      price: row['price_toman'] as num? ?? 0,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.tryParse(row['created_at'] as String)?.toLocal(),
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.tryParse(row['updated_at'] as String)?.toLocal(),
      rescheduleCount: (row['reschedule_count'] as num?)?.toInt() ?? 0,
      cancelReason: row['cancel_reason'] as String?,
      serviceSnapshots: services
          .map((item) => {
                'service_id': item['service_id'],
                'title': item['title_snapshot'],
                'duration_minutes': item['duration_minutes'],
                'price': item['price_toman'],
              })
          .toList(growable: false),
    );
  }

  dynamic _applySearch(dynamic request, String query) {
    final value = query.trim();
    if (value.isEmpty) return request;
    final safe = _safeFilterValue(value);
    final clauses = <String>['full_name.ilike.%$safe%', 'phone.ilike.%$safe%'];
    final phone = _normalizedPhone(value);
    if (phone.isNotEmpty) {
      clauses.add('normalized_phone.ilike.%$phone%');
      const latinDigits = '0123456789';
      const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
      final persianPhone = phone.split('').map((digit) {
        final index = latinDigits.indexOf(digit);
        return index < 0 ? digit : persianDigits[index];
      }).join();
      clauses.add('phone.ilike.%$persianPhone%');
    }
    return request.or(clauses.join(','));
  }

  @override
  Future<PageResult<Customer>> fetchCustomers({
    String query = '',
    int page = 1,
    int pageSize = 8,
    String sortBy = 'createdAt',
    bool archivedOnly = false,
  }) async {
    final tenant = _tenant();
    if (page < 1 || pageSize < 1 || pageSize > 100) {
      throw ArgumentError('شماره صفحه یا اندازه صفحه معتبر نیست.');
    }
    final start = (page - 1) * pageSize;
    final sortColumn = switch (sortBy) {
      'fullName' => 'full_name',
      _ => 'created_at',
    };
    var request = _client
        .from('customers')
        .select(_customerColumns)
        .eq('business_id', tenant)
        .eq('is_active', !archivedOnly);
    request = _applySearch(request, query);
    final response = await request
        .order(sortColumn, ascending: sortColumn == 'full_name')
        .range(start, start + pageSize - 1)
        .count(CountOption.exact);
    final rows = response.data;
    return PageResult<Customer>(
      items: rows
          .map((row) => _customer(Map<String, dynamic>.from(row)))
          .toList(growable: false),
      total: response.count ?? 0,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<Customer>> fetchAll({String query = ''}) async {
    final tenant = _tenant();
    var request = _client
        .from('customers')
        .select(_customerColumns)
        .eq('business_id', tenant)
        .eq('is_active', true);
    request = _applySearch(request, query);
    final rows = await request.order('created_at', ascending: false);
    return rows
        .map((row) => _customer(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  @override
  Future<Customer?> findById(String id) async {
    final tenant = _tenant();
    final row = await _client
        .from('customers')
        .select(_customerColumns)
        .eq('business_id', tenant)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : _customer(Map<String, dynamic>.from(row));
  }

  @override
  Future<CustomerProfile?> fetchProfile(String id) async {
    final tenant = _tenant();
    final customerRow = await _client
        .from('customers')
        .select(_customerColumns)
        .eq('business_id', tenant)
        .eq('id', id)
        .maybeSingle();
    if (customerRow == null) return null;
    final customer = _customer(Map<String, dynamic>.from(customerRow));

    final appointmentRows = await _client
        .from('appointments')
        .select(_appointmentColumns)
        .eq('business_id', tenant)
        .eq('customer_id', id)
        .order('starts_at', ascending: false);
    final appointments = appointmentRows
        .map((row) => _appointment(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    final completed = appointments
        .where((a) => a.status == AppointmentStatus.completed)
        .toList(growable: false);
    final cancelled = appointments
        .where((a) => a.status == AppointmentStatus.cancelled)
        .length;
    final noShows = appointments
        .where((a) => a.status == AppointmentStatus.noShow)
        .length;
    final lastVisit = completed.isEmpty
        ? null
        : completed.map((a) => a.startAt).reduce(
              (a, b) => a.isAfter(b) ? a : b,
            );
    final services = completed
        .expand((a) => a.serviceName.split('،'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final billed = appointmentRows.fold<num>(0, (sum, rawRow) {
      if (rawRow['status'] != 'completed') return sum;
      final gross = (rawRow['price_toman'] as num?) ?? 0;
      final discount = (rawRow['discount_toman'] as num?) ?? 0;
      return sum + (gross - discount);
    });
    final financeVisible = _canViewFinance();
    num? paid;
    num? outstanding;
    if (financeVisible) {
      final paymentRows = await _client
          .from('appointment_payments')
          .select('amount_toman,payment_type')
          .eq('business_id', tenant)
          .eq('customer_id', id);
      var receipts = 0;
      var refunds = 0;
      for (final row in paymentRows) {
        final amount = (row['amount_toman'] as num?)?.toInt() ?? 0;
        if (row['payment_type'] == 'receipt') {
          receipts += amount;
        } else if (row['payment_type'] == 'refund') {
          refunds += amount;
        }
      }
      paid = receipts - refunds;
      outstanding = (billed - paid).clamp(0, billed);
    }

    final profileCustomer = customer.copyWith(
      visitCount: completed.length,
      totalSpent: paid ?? 0,
      cancelCount: cancelled,
      noShowCount: noShows,
      lastVisitAt: lastVisit,
    );
    return CustomerProfile(
      customer: profileCustomer,
      appointments: appointments,
      services: services,
      completedVisits: completed.length,
      cancelledAppointments: cancelled,
      noShowAppointments: noShows,
      lastVisitAt: lastVisit,
      financeVisible: financeVisible,
      totalBilled: financeVisible ? billed : null,
      totalPaid: paid,
      outstanding: outstanding,
    );
  }

  @override
  Future<void> create(Customer customer) async {
    final tenant = _tenant();
    await _client.from('customers').insert({
      'business_id': tenant,
      'full_name': customer.fullName.trim(),
      'phone': customer.phone.trim(),
      'notes': customer.notes,
      'tags': customer.tags,
    }).select('id').single();
  }

  @override
  Future<void> update(Customer customer) async {
    final tenant = _tenant();
    final rows = await _client
        .from('customers')
        .update({
          'full_name': customer.fullName.trim(),
          'phone': customer.phone.trim(),
          'notes': customer.notes,
          'tags': customer.tags,
          'is_active': !customer.isArchived,
        })
        .eq('business_id', tenant)
        .eq('id', customer.id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('مشتری به‌روزرسانی نشد؛ دسترسی یا وجود رکورد را بررسی کنید.');
    }
  }

  @override
  Future<void> delete(String id) async {
    final tenant = _tenant();
    final rows = await _client
        .from('customers')
        .update({'is_active': false})
        .eq('business_id', tenant)
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('بایگانی مشتری انجام نشد؛ دسترسی یا وجود رکورد را بررسی کنید.');
    }
  }
}
