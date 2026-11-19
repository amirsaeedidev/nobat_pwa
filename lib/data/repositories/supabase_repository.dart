import 'package:supabase_flutter/supabase_flutter.dart';

/// Tenant-scoped repository for records stored in public.app_records.
///
/// The existing Mock repositories remain the default UI data source. This
/// repository is the authenticated remote data layer used when a feature is
/// explicitly migrated to Supabase.
class SupabaseRepository {
  SupabaseRepository(this._client);

  final SupabaseClient _client;

  static const Set<String> supportedEntityTypes = {
    'appointments',
    'customers',
    'employees',
    'services',
    'finance',
    'employee_wallets',
    'reports',
    'settings',
    'activity_logs',
    'payroll',
    'leave_requests',
    'employee_services',
    'roles',
  };

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('برای دسترسی به اطلاعات Supabase ابتدا وارد حساب شوید.');
    }
    return userId;
  }

  void _validateEntityType(String entityType) {
    if (!supportedEntityTypes.contains(entityType)) {
      throw ArgumentError.value(entityType, 'entityType', 'Unsupported entity type.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchRecords({
    required String businessId,
    required String entityType,
  }) async {
    _requireUserId();
    _validateBusinessId(businessId);
    _validateEntityType(entityType);

    final rows = await _client
        .from('app_records')
        .select('record_id,payload,updated_at')
        .eq('business_id', businessId)
        .eq('entity_type', entityType)
        .order('updated_at', ascending: false);

    return rows.map((row) {
      final value = Map<String, dynamic>.from(row);
      return {
        'id': value['record_id'],
        ...Map<String, dynamic>.from(value['payload'] as Map),
        'updated_at': value['updated_at'],
      };
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>?> fetchRecord({
    required String businessId,
    required String entityType,
    required String recordId,
  }) async {
    _requireUserId();
    _validateBusinessId(businessId);
    _validateEntityType(entityType);
    _validateRecordId(recordId);

    final row = await _client
        .from('app_records')
        .select('record_id,payload,updated_at')
        .eq('business_id', businessId)
        .eq('entity_type', entityType)
        .eq('record_id', recordId)
        .maybeSingle();

    if (row == null) return null;
    final value = Map<String, dynamic>.from(row);
    return {
      'id': value['record_id'],
      ...Map<String, dynamic>.from(value['payload'] as Map),
      'updated_at': value['updated_at'],
    };
  }

  Future<void> upsertRecord({
    required String businessId,
    required String entityType,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    final userId = _requireUserId();
    _validateBusinessId(businessId);
    _validateEntityType(entityType);
    _validateRecordId(recordId);
    if (payload.isEmpty) {
      throw ArgumentError.value(payload, 'payload', 'Record payload cannot be empty.');
    }

    await _client.from('app_records').upsert(
      {
        'business_id': businessId,
        'entity_type': entityType,
        'record_id': recordId,
        'payload': payload,
        'created_by': userId,
        'updated_by': userId,
      },
      onConflict: 'business_id,entity_type,record_id',
    );
  }

  Future<void> deleteRecord({
    required String businessId,
    required String entityType,
    required String recordId,
  }) async {
    final userId = _requireUserId();
    _validateBusinessId(businessId);
    _validateEntityType(entityType);
    _validateRecordId(recordId);

    await _client
        .from('app_records')
        .delete()
        .eq('business_id', businessId)
        .eq('entity_type', entityType)
        .eq('record_id', recordId)
        .eq('updated_by', userId);
  }

  Future<List<Map<String, dynamic>>> fetchMyBusinesses() async {
    final userId = _requireUserId();
    final rows = await _client
        .from('business_memberships')
        .select('business_id,role,permissions,is_active,businesses(id,name)')
        .eq('user_id', userId)
        .eq('is_active', true);

    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  void _validateBusinessId(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'businessId', 'Business ID is required.');
    }
  }

  void _validateRecordId(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'recordId', 'Record ID is required.');
    }
  }
}
