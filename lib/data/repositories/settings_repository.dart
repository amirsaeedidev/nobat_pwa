import '../mock/app_database.dart';
import '../models/business_settings.dart';

abstract class SettingsRepository {
  /// Emits after Supabase authentication changes; local test adapters may omit it.
  Stream<void>? get authChanges => null;

  Future<BusinessSettings> fetchSettings();

  Future<void> saveSettings(
    BusinessSettings settings, {
    String? logTitle,
    String? logDescription,
  });

  Future<String> fetchBookingFormTheme();

  Future<void> saveBookingFormTheme(String themeId);
}

/// Local implementation retained for isolated widget/unit tests only.
class MockSettingsRepository implements SettingsRepository {
  MockSettingsRepository(this._db);

  final AppDatabase _db;
  String _formTheme = 'pastel_pink';

  @override
  Future<BusinessSettings> fetchSettings() async {
    await _db.delay(120);
    return _db.settings;
  }

  @override
  Future<void> saveSettings(
    BusinessSettings settings, {
    String? logTitle,
    String? logDescription,
  }) async {
    await _db.delay(240);
    _db.updateSettings(settings, logTitle: logTitle, logDescription: logDescription);
  }

  @override
  Future<String> fetchBookingFormTheme() async => _formTheme;

  @override
  Future<void> saveBookingFormTheme(String themeId) async {
    _formTheme = themeId;
  }
}

/// Explicit failure when the remote client is not configured. Production
/// settings must never silently switch to seeded/local business information.
class UnavailableSettingsRepository implements SettingsRepository {
  StateError _unavailable() => StateError(
        'اتصال امن به Supabase برای تنظیمات مجموعه در دسترس نیست. '
        'پس از ورود مدیر کل و برقراری اتصال دوباره تلاش کنید.',
      );

  @override
  Future<BusinessSettings> fetchSettings() async => throw _unavailable();

  @override
  Future<void> saveSettings(
    BusinessSettings settings, {
    String? logTitle,
    String? logDescription,
  }) async => throw _unavailable();

  @override
  Future<String> fetchBookingFormTheme() async => throw _unavailable();

  @override
  Future<void> saveBookingFormTheme(String themeId) async => throw _unavailable();
}
