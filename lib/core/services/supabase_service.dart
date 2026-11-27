import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Supabase client lifecycle. Cloud data is required; initialization failure
/// must never silently switch the application to local/demo records.
class SupabaseService {
  SupabaseService._();

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient? get client =>
      _initialized ? Supabase.instance.client : null;

  static Future<bool> initialize() async {
    if (!SupabaseConfig.isConfigured) {
      debugPrint('[DateTime] Supabase is not configured; cloud data access is unavailable.');
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
      debugPrint('[DateTime] Supabase initialization failed; no local/demo fallback is enabled: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
