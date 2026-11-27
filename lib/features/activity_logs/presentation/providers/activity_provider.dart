import 'dart:async';
import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/activity_log.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/repositories/activity_repository.dart';
import '../../../../data/repositories/operations_repository.dart';

/// گزارش فعالیت‌ها با فیلتر نوع و جست‌وجو.
class ActivityProvider extends DbBoundProvider {
  ActivityProvider(this._repository, AppDatabase? db, {ActivityOperationsRepository? operationsRepository, SupabaseAuthStateNotifier? authStateNotifier})
      : _operations = operationsRepository ?? UnavailableActivityOperationsRepository(), super(authStateNotifier: authStateNotifier) {
    load();
  }

  final ActivityRepository _repository;
  final ActivityOperationsRepository _operations;

  List<ActivityLog> _logs = const [];
  List<ActivityLog> _recent = const [];
  ActivityType? _type;
  String _query = '';
  bool _loading = true;
  int _loadGeneration = 0;
  String? _error;

  List<ActivityLog> get logs => _logs;
  List<ActivityLog> get recent => _recent;
  ActivityType? get type => _type;
  String get query => _query;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    notifyListeners();
    try {
      _error = null;
      final logs = await _repository.fetchLogs(type: _type, query: _query);
      final recent = await _repository.fetchRecent(limit: 6);
      if (generation != _loadGeneration) return;
      _logs = logs;
      _recent = recent;
    } catch (error) {
      if (generation != _loadGeneration) return;
      _error = error.toString();
      _logs = const [];
      _recent = const [];
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void onAuthenticatedTenantChanged() => unawaited(load());

  @override
  void onTenantContextCleared() {
    _loadGeneration++;
    _logs = const [];
    _recent = const [];
    _loading = false;
  }

  void filterType(ActivityType? type) {
    _type = type;
    load();
  }

  bool canUndo(ActivityLog log) => _operations.canUndoActivityLog(log);
  Future<bool> undo(ActivityLog log) async {
    try {
      final result = await _operations.undoActivityEvent(log.operationId ?? log.id);
      if (result) await load();
      return result;
    }
  }
  void search(String query) {
    _query = query;
    load();
  }
}
