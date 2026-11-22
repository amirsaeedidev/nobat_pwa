import '../../../../core/providers/db_bound_provider.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/activity_log.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/repositories/activity_repository.dart';
import '../../../../data/repositories/operations_repository.dart';

/// گزارش فعالیت‌ها با فیلتر نوع و جست‌وجو.
class ActivityProvider extends DbBoundProvider {
  ActivityProvider(this._repository, AppDatabase db)
      : _operations = OperationsRepository(db), super(db) {
    load();
  }

  final ActivityRepository _repository;
  final OperationsRepository _operations;

  List<ActivityLog> _logs = const [];
  List<ActivityLog> _recent = const [];
  ActivityType? _type;
  String _query = '';
  bool _loading = true;
  int _loadGeneration = 0;
  bool _undoing = false;

  List<ActivityLog> get logs => _logs;
  List<ActivityLog> get recent => _recent;
  ActivityType? get type => _type;
  String get query => _query;
  bool get loading => _loading;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    notifyListeners();
    try {
      final logs = await _repository.fetchLogs(type: _type, query: _query);
      final recent = await _repository.fetchRecent(limit: 6);
      if (generation != _loadGeneration) return;
      _logs = logs;
      _recent = recent;
    } catch (_) {
      if (generation != _loadGeneration) return;
      _logs = db.activityLogs.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _recent = _logs.take(6).toList();
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void onDatabaseChanged() {
    // Undo already performs one awaited reload below. Suppress the database
    // listener's parallel reload to avoid racing generations during the
    // confirmation flow.
    if (!_undoing) _refresh();
  }

  Future<void> _refresh() async => load();

  void filterType(ActivityType? type) {
    _type = type;
    load();
  }

  bool canUndo(ActivityLog log) => _operations.canUndo(log.id);
  Future<bool> undo(ActivityLog log) async {
    _undoing = true;
    try {
      final result = _operations.undo(log.id);
      if (result) await load();
      return result;
    } finally {
      _undoing = false;
    }
  }
  void search(String query) {
    _query = query;
    load();
  }
}
