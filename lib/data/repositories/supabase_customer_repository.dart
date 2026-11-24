import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/page_result.dart';
import '../models/customer.dart';
import 'customer_repository.dart';

/// Relational customer repository. Every query is tenant-scoped and still
/// passes through Supabase RLS; the business id is read from the verified
/// membership at call time rather than captured during application startup.
class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository({
    required SupabaseClient client,
    required String? Function() businessId,
  })  : _client = client,
        _businessId = businessId;

  final SupabaseClient _client;
  final String? Function() _businessId;

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

  Map<String, dynamic> _toModel(Map<String, dynamic> row) => {
        'id': row['id'],
        'full_name': row['full_name'],
        'phone': row['phone'],
        'notes': row['notes'],
        'tags': row['tags'],
        'created_at': row['created_at'],
        'is_archived': row['is_active'] == false,
      };

  @override
  Future<PageResult<Customer>> fetchCustomers({
    String query = '',
    int page = 1,
    int pageSize = 8,
    String sortBy = 'createdAt',
  }) async {
    final tenant = _tenant();
    final start = (page - 1) * pageSize;
    final normalized = query.trim();
    var request = _client
        .from('customers')
        .select('id,full_name,phone,notes,tags,is_active,created_at')
        .eq('business_id', tenant)
        .eq('is_active', true);

    if (normalized.isNotEmpty) {
      final safe = normalized.replaceAll(',', '').replaceAll('%', r'\%').replaceAll('_', r'\_');
      request = request.or('full_name.ilike.%$safe%,phone.ilike.%$safe%');
    }

    final countQuery = await _client
        .from('customers')
        .select('id')
        .eq('business_id', tenant)
        .eq('is_active', true);
    final total = normalized.isEmpty
        ? countQuery.length
        : (await request).length;

    final rows = await request
        .order('created_at', ascending: false)
        .range(start, start + pageSize - 1);

    return PageResult<Customer>(
      items: rows.map((row) => Customer.fromJson(_toModel(Map<String, dynamic>.from(row)))).toList(growable: false),
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<Customer>> fetchAll({String query = ''}) async {
    final tenant = _tenant();
    var request = _client
        .from('customers')
        .select('id,full_name,phone,notes,tags,is_active,created_at')
        .eq('business_id', tenant)
        .eq('is_active', true);
    final normalized = query.trim();
    if (normalized.isNotEmpty) {
      final safe = normalized.replaceAll(',', '').replaceAll('%', r'\%').replaceAll('_', r'\_');
      request = request.or('full_name.ilike.%$safe%,phone.ilike.%$safe%');
    }
    final rows = await request.order('created_at', ascending: false);
    return rows.map((row) => Customer.fromJson(_toModel(Map<String, dynamic>.from(row)))).toList(growable: false);
  }

  @override
  Future<Customer?> findById(String id) async {
    final tenant = _tenant();
    final row = await _client
        .from('customers')
        .select('id,full_name,phone,notes,tags,is_active,created_at')
        .eq('business_id', tenant)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Customer.fromJson(_toModel(Map<String, dynamic>.from(row)));
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
    });
  }

  @override
  Future<void> update(Customer customer) async {
    final tenant = _tenant();
    await _client
        .from('customers')
        .update({
          'full_name': customer.fullName.trim(),
          'phone': customer.phone.trim(),
          'notes': customer.notes,
          'tags': customer.tags,
          'is_active': !customer.isArchived,
        })
        .eq('business_id', tenant)
        .eq('id', customer.id);
  }

  @override
  Future<void> delete(String id) async {
    final tenant = _tenant();
    await _client
        .from('customers')
        .delete()
        .eq('business_id', tenant)
        .eq('id', id);
  }
}
