import 'package:flutter_test/flutter_test.dart';

import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/activity_log.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/repositories/activity_repository.dart';
import 'package:datetime/features/activity_logs/presentation/providers/activity_provider.dart';

class _FailingActivityRepository implements ActivityRepository {
  @override
  Future<List<ActivityLog>> fetchLogs({
    ActivityType? type,
    String query = '',
    int? limit,
  }) =>
      Future.error(StateError('Supabase is unavailable'));

  @override
  Future<List<ActivityLog>> fetchRecent({int limit = 6}) =>
      Future.error(StateError('Supabase is unavailable'));
}

void main() {
  test('activity provider never falls back to local records on server failure', () async {
    final db = AppDatabase()
      ..log(
        ActivityType.settingsChanged,
        'رویداد محلی آزمایشی',
        'نباید نمایش داده شود',
        entity: 'تنظیمات',
        entityId: 'local-only',
      );

    final provider = ActivityProvider(_FailingActivityRepository(), db);
    addTearDown(provider.dispose);
    await provider.load();

    expect(provider.logs, isEmpty);
    expect(provider.recent, isEmpty);
    expect(provider.error, contains('Supabase is unavailable'));
  });

  test('activity model preserves operation identity and consumed undo state', () {
    final log = ActivityLog.fromJson({
      'id': 'event-1',
      'operation_id': 'operation-1',
      'type': 'settingsChanged',
      'title': 'ویرایش تنظیمات',
      'description': 'تغییر تنظیمات مجموعه',
      'actor': 'مدیر کل',
      'created_at': '2026-11-25T10:00:00.000Z',
      'entity_name': 'تنظیمات',
      'entity_id': 'business-1',
      'operation_type': 'settings_update',
      'is_reversible': true,
      'undone_by_event_id': 'event-2',
      'undo_of_event_id': null,
    });

    expect(log.operationId, 'operation-1');
    expect(log.isReversible, isTrue);
    expect(log.isUndone, isTrue);
  });
}
