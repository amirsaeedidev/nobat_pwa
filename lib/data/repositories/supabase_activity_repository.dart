import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_log.dart';
import '../models/enums.dart';
import 'activity_repository.dart';

/// Reads the immutable activity journal written by PostgreSQL triggers.
class SupabaseActivityRepository implements ActivityRepository {
  SupabaseActivityRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> get authChanges =>
      _client.auth.onAuthStateChange.map<void>((_) {});

  Future<String> _businessId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('برای مشاهده تاریخچه، ابتدا وارد حساب سرور شوید.');
    }

    final rows = await _client
        .from('business_memberships')
        .select('business_id')
        .eq('user_id', userId)
        .eq('is_active', true)
        .limit(2);

    if (rows.length != 1) {
      throw StateError(
        rows.isEmpty
            ? 'برای این حساب مجموعه فعالی ثبت نشده است.'
            : 'بیش از یک مجموعه فعال یافت شد؛ دامنه تاریخچه مبهم است.',
      );
    }
    return rows.single['business_id'] as String;
  }

  Future<List<ActivityLog>> _fetch({required int limit}) async {
    final businessId = await _businessId();
    final rows = await _client
        .from('business_activity_events')
        .select(
          'id,operation_id,actor_name,entity_type,entity_id,action,'
          'operation_type,type,title,description,idempotency_key,'
          'is_reversible,undo_of_event_id,undone_by_event_id,created_at',
        )
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(limit.clamp(1, 1000).toInt());

    return rows
        .map((row) => _fromRow(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  ActivityLog _fromRow(Map<String, dynamic> row) {
    final entityType = row['entity_type'] as String? ?? '';
    final isUndone =
        row['undone_by_event_id'] != null || row['undo_of_event_id'] != null;

    return ActivityLog(
      id: row['id'] as String,
      operationId: row['operation_id'] as String?,
      type: ActivityType.fromKey(
        row['type'] as String? ?? 'settingsChanged',
      ),
      title: row['title'] as String? ?? 'ثبت فعالیت',
      description: row['description'] as String? ?? '',
      actor: row['actor_name'] as String? ?? 'کاربر',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      entityName: _entityName(entityType),
      entityId: row['entity_id'] as String? ?? '',
      operationType: row['operation_type'] as String?,
      idempotencyKey: row['idempotency_key'] as String?,
      isReversible: row['is_reversible'] as bool? ?? false,
      isUndone: isUndone,
      undoAction: (row['is_reversible'] == true && !isUndone)
          ? 'restore_snapshot'
          : null,
    );
  }

  String _entityName(String type) => switch (type) {
        'appointments' => 'نوبت',
        'customers' => 'مشتری',
        'employees' => 'پرسنل',
        'services' || 'service_categories' => 'خدمت',
        'finance' => 'عملیات مالی مجموعه',
        'employee_wallets' => 'کیف پول پرسنل',
        'payroll' => 'حقوق و پورسانت',
        'settings' => 'تنظیمات مجموعه',
        'roles' => 'نقش و دسترسی',
        'business_holidays' => 'تعطیلات مجموعه',
        'employee_services' => 'تخصص پرسنل',
        _ => 'رکورد سامانه',
      };

  @override
  Future<List<ActivityLog>> fetchLogs({
    ActivityType? type,
    String query = '',
    int? limit,
  }) async {
    final logs = await _fetch(limit: limit ?? 1000);
    final q = query.trim().toLowerCase();
    final filtered = logs.where((log) {
      if (type != null && log.type != type) return false;
      if (q.isEmpty) return true;
      return log.title.toLowerCase().contains(q) ||
          log.description.toLowerCase().contains(q) ||
          log.actor.toLowerCase().contains(q) ||
          log.entityName.toLowerCase().contains(q) ||
          log.entityId.toLowerCase().contains(q) ||
          log.operationLabel.toLowerCase().contains(q) ||
          (log.operationType?.toLowerCase().contains(q) ?? false) ||
          (log.operationId?.toLowerCase().contains(q) ?? false);
    }).toList(growable: false);
    return limit == null ? filtered : filtered.take(limit).toList();
  }

  @override
  Future<List<ActivityLog>> fetchRecent({int limit = 6}) =>
      _fetch(limit: limit);
}
