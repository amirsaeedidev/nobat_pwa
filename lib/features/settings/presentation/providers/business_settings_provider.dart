import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/models/business_settings.dart';
import '../../../../data/repositories/business_settings_repository.dart';

/// Remote-only state for the business identity/contact settings screen.
class BusinessSettingsProvider extends ChangeNotifier {
  BusinessSettingsProvider(this._repository) {
    _authSubscription = _repository.authChanges.listen((_) => load());
    load();
  }

  final BusinessSettingsRepository _repository;
  StreamSubscription<void>? _authSubscription;

  BusinessSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  int _generation = 0;

  BusinessSettings? get settings => _settings;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get loadError => _loadError;

  Future<void> load() async {
    final generation = ++_generation;
    _loading = true;
    _settings = null; // Never expose a previous tenant while another session is loading.
    _loadError = null;
    notifyListeners();
    try {
      final result = await _repository.fetchSettings();
      if (generation != _generation) return;
      _settings = result;
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _settings = null;
      _loadError = error.toString();
      debugPrint('[DateTime][BusinessSettings] Remote load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveBusiness(BusinessSettings settings) async {
    _saving = true;
    _loadError = null;
    notifyListeners();
    try {
      await _repository.saveSettings(settings);
      _settings = await _repository.fetchSettings();
    } catch (error, stackTrace) {
      _loadError = error.toString();
      debugPrint('[DateTime][BusinessSettings] Remote save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
