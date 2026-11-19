import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Optional Supabase client lifecycle. The app remains usable when disabled
/// or when Supabase cannot be initialized.
class SupabaseService {
  SupabaseService._();

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient? get client =>
      _initialized ? Supabase.instance.client : null;

  static Future<bool> initialize() async {
    if (!SupabaseConfig.isConfigured) {
      debugPrint('[DateTime] Supabase disabled; using local Datamonck data.');
      return false;
    }

    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      _initialized = true;
      debugPrint('[DateTime] Supabase client initialized (network is lazy).');
      return true;
    } catch (error, stackTrace) {
      _initialized = false;
      debugPrint('[DateTime] Supabase initialization failed; offline mode stays active: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
