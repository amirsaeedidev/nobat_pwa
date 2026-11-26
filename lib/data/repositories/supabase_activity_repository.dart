import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_log.dart';
import '../models/enums.dart';
import 'activity_repository.dart';

/// Reads the append-only audit stream written by database triggers.
/// Row visibility is enforced by RLS on business_activity_events.
class SupabaseActivityRepository extends ActivityRepository {
  SupabaseActivityRepository({
    required SupabaseClient client,
    required String? Function() businessId,
  })  : _client = client,
        _businessId = businessId;

  final SupabaseClient _client;
  final String? Function() _businessId;

  @override
  Stream<void>? get authChanges => _client.auth.onAuthStateChange.map((_) {});

  ActivityType _activityType(Map<String, dynamic> row) {
    final rawType = row['type']?.toString();
    if (rawType != null &&
        ActivityType.values.any((item) => item.key == rawType)) {
      return ActivityType.fromKey(rawType);
    }
    return switch (row['operation_type']?.toString()) {
      'appointment_create' => ActivityType.appointmentCreated,
      'appointment_update' || 'appointment_reschedule' =>
        ActivityType.appointmentUpdated,
      'appointment_cancel' || 'appointment_reject' =>
        ActivityType.appointmentCancelled,
      'appointment_complete' => ActivityType.appointmentCompleted,
      'customer_create' => ActivityType.customerRegistered,
      'service_create' || 'service_update' || 'service_delete' =>
        ActivityType.serviceModified,
      'employee_create' || 'employee_update' => ActivityType.employeeAdded,
      _ => ActivityType.settingsChanged,
    };
  }

  ActivityLog _map(Map<String, dynamic> row) {
    final eventId = row['id'].toString();
    final beforeState = row['before_state'];
    return ActivityLog(
      id: eventId,
      operationId: eventId,
      type: _activityType(row),
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      actor: row['actor_name'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
      entityName: row['entity_type'] as String? ??
          row['source_table'] as String? ??
          '',
      entityId: row['entity_id']?.toString() ?? '',
      operationType: row['operation_type'] as String?,
      isReversible: row['is_reversible'] as bool? ?? false,
      isUndone: row['undone_by_event_id'] != null,
      idempotencyKey: row['idempotency_key'] as String?,
      undoAction: row['is_reversible'] == true
          ? 'undo_business_activity_event'
          : null,
      undoData: beforeState is Map
          ? Map<String, dynamic>.from(beforeState)
          : null,
    );
  }

  Future<List<ActivityLog>> _load() async {
    if (_client.auth.currentUser == null) {
      throw StateError('برای مشاهده تاریخچه باید وارد حساب شوید.');
    }
    final tenant = _businessId();
    if (tenant == null || tenant.isEmpty) {
      throw StateError('عضویت فعال مجموعه تأیید نشده است.');
    }
    final rows = await _client
        .from('business_activity_events')
        .select(
          'id,operation_id,actor_name,source_table,entity_type,entity_id,'
          'operation_type,type,title,description,before_state,'
          'idempotency_key,is_reversible,undone_by_event_id,created_at',
        )
        .eq('business_id', tenant)
        .order('created_at', ascending: false);
    return rows
        .map((row) => _map(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  @override
  Future<List<ActivityLog>> fetchLogs({
    ActivityType? type,
    String query = '',
    int? limit,
  }) async {
    final normalized = query.trim().toLowerCase();
    final items = (await _load()).where((item) {
      if (type != null && item.type != type) return false;
      if (normalized.isEmpty) return true;
      return item.title.toLowerCase().contains(normalized) ||
          item.description.toLowerCase().contains(normalized) ||
          item.actor.toLowerCase().contains(normalized) ||
          item.entityName.toLowerCase().contains(normalized) ||
          item.entityId.toLowerCase().contains(normalized) ||
          (item.operationType?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);
    return limit == null ? items : items.take(limit).toList(growable: false);
  }

  @override
  Future<List<ActivityLog>> fetchRecent({int limit = 6}) async =>
      (await _load()).take(limit).toList(growable: false);
}
