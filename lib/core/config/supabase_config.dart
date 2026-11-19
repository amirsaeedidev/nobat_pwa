/// Compile-time configuration for the optional Supabase backend.
///
/// Supply values with: flutter run --dart-define-from-file=.env
class SupabaseConfig {
  SupabaseConfig._();

  static const bool enabled = bool.fromEnvironment(
    'SUPABASE_ENABLED',
    defaultValue: false,
  );
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured {
    final parsedUrl = Uri.tryParse(url);
    return enabled &&
        parsedUrl != null &&
        parsedUrl.scheme == 'https' &&
        parsedUrl.host.isNotEmpty &&
        publishableKey.startsWith('sb_publishable_');
  }
}
