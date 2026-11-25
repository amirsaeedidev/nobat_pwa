import 'dart:async';

import '../mock/app_database.dart';
import '../models/activity_log.dart';
import '../models/enums.dart';

abstract class ActivityRepository {
  Stream<void>? get authChanges => null;

  Future<List<ActivityLog>> fetchLogs({ActivityType? type, String query = '', int? limit});

  Future<List<ActivityLog>> fetchRecent({int limit = 6});
}

class MockActivityRepository implements ActivityRepository {
  MockActivityRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<void>? get authChanges => null;

  @override
  Future<List<ActivityLog>> fetchLogs({ActivityType? type, String query = '', int? limit}) async {
    await _db.delay(140);
    final q = query.trim();
    final matches = _db.activityLogs
        .where((l) {
          if (type != null && l.type != type) return false;
          if (q.isEmpty) return true;
          return l.title.contains(q) || l.description.contains(q) || l.actor.contains(q) || l.entityName.contains(q) || l.entityId.contains(q) || l.operationLabel.contains(q) || (l.operationType?.contains(q) ?? false);
        })
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return limit == null ? matches : matches.take(limit).toList();
  }

  @override
  Future<List<ActivityLog>> fetchRecent({int limit = 6}) async {
    await _db.delay(80);
    final logs = _db.activityLogs.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return logs.take(limit).toList();
  }
}

/// مسیر بدون نشست سرور؛ عمداً هیچ داده محلی یا ساختگی برنمی‌گرداند.
class UnavailableActivityRepository implements ActivityRepository {
  @override
  Stream<void>? get authChanges => null;

  @override
  Future<List<ActivityLog>> fetchLogs({ActivityType? type, String query = '', int? limit}) =>
      Future.error(StateError('برای مشاهده تاریخچه فعالیت‌ها باید به حساب سرور وارد شوید.'));

  @override
  Future<List<ActivityLog>> fetchRecent({int limit = 6}) =>
      Future.error(StateError('برای مشاهده تاریخچه فعالیت‌ها باید به حساب سرور وارد شوید.'));
}
