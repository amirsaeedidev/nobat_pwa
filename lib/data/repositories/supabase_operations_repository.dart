import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_log.dart';
import 'operations_repository.dart';

/// Server-side operations gateway. Undo is executed by a transaction-safe RPC;
/// the database validates permissions, current row state and one-time use.
class SupabaseOperationsRepository implements ActivityOperationsRepository {
  SupabaseOperationsRepository(this._client);

  final SupabaseClient _client;

  @override
  bool canUndoActivityLog(ActivityLog log) => log.isReversible && !log.isUndone;

  @override
  Future<bool> undoActivityEvent(String activityEventId) async {
    if (_client.auth.currentUser == null) {
      throw StateError('برای بازگردانی عملیات باید وارد حساب سرور شوید.');
    }
    final result = await _client.rpc(
      'undo_business_activity_event',
      params: {'p_event_id': activityEventId},
    );
    return result is String && result.isNotEmpty;
  }
}

/// Fail-closed implementation: never falls back to local audit history.
class UnavailableActivityOperationsRepository
    implements ActivityOperationsRepository {
  @override
  bool canUndoActivityLog(ActivityLog log) => false;

  @override
  Future<bool> undoActivityEvent(String activityEventId) =>
      Future.error(StateError('بازگردانی فقط با اتصال به سرور امکان‌پذیر است.'));
}
