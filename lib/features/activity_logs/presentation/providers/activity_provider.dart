import 'package:flutter/foundation.dart';

import '../../../../data/mock/app_database.dart';
import '../../../../data/models/activity_log.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/repositories/activity_repository.dart';
import '../../../../data/repositories/operations_repository.dart';

/// Activity history is server-authoritative in production; local constructor
/// remains available only for isolated legacy unit tests.
class ActivityProvider extends ChangeNotifier {
  ActivityProvider(this._repository, AppDatabase db)
      : _operations = OperationsRepository(db) {
    load();
  }

  ActivityProvider.remote(this._repository, this._operations) {
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
    _error = null;
    notifyListeners();
    try {
      final logs = await _repository.fetchLogs(type: _type, query: _query);
      final recent = await _repository.fetchRecent(limit: 6);
      if (generation != _loadGeneration) return;
      _logs = logs;
      _recent = recent;
    } catch (error) {
      if (generation != _loadGeneration) return;
      // Fail closed: an unavailable server must never be replaced by local
      // mock activity records or stale cached history.
      _logs = const [];
      _recent = const [];
      _error = error.toString();
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void filterType(ActivityType? type) {
    _type = type;
    load();
  }

  bool canUndo(ActivityLog log) => _operations.canUndoActivityLog(log);

  Future<bool> undo(ActivityLog log) async {
    try {
      final result = await _operations.undoActivityEvent(log.id);
      if (result) await load();
      return result;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  void search(String query) {
    _query = query;
    load();
  }
}
