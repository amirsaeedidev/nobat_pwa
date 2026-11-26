import '../models/activity_log.dart';
import '../models/enums.dart';
import 'activity_repository.dart';
import 'supabase_repository.dart';

/// Activity history reads only persisted tenant records. It does not expose
/// the in-memory Undo journal as if it were a server audit log.
class SupabaseActivityRepository implements ActivityRepository {
  SupabaseActivityRepository({
    required SupabaseRepository records,
    required String? Function() businessId,
  })  : _records = records,
        _businessId = businessId;

  final SupabaseRepository _records;
  final String? Function() _businessId;

  @override
  Stream<void>? get authChanges => null;

  Future<List<ActivityLog>> _load() async {
    final tenant = _businessId();
    if (tenant == null || tenant.isEmpty) {
      throw StateError('عضویت فعال مجموعه تأیید نشده است.');
    }
    final rows = await _records.fetchRecords(
      businessId: tenant,
      entityType: 'activity_logs',
    );
    final items = rows.map(ActivityLog.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<List<ActivityLog>> fetchLogs({ActivityType? type, String query = '', int? limit}) async {
    final normalized = query.trim();
    final items = (await _load()).where((item) {
      if (type != null && item.type != type) return false;
      if (normalized.isEmpty) return true;
      return item.title.contains(normalized) ||
          item.description.contains(normalized) ||
          item.actor.contains(normalized) ||
          item.entityName.contains(normalized) ||
          item.entityId.contains(normalized) ||
          (item.operationType?.contains(normalized) ?? false);
    }).toList();
    return limit == null ? items : items.take(limit).toList(growable: false);
  }

  @override
  Future<List<ActivityLog>> fetchRecent({int limit = 6}) async =>
      (await _load()).take(limit).toList(growable: false);
}
