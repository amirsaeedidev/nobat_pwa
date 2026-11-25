import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/data/mock/app_database.dart';
import '../lib/data/repositories/settings_repository.dart';
import '../lib/features/settings/presentation/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remote settings failure does not fall back to seeded business data', () async {
    final provider = SettingsProvider(UnavailableSettingsRepository());
    await provider.load();

    expect(provider.settings, isNull);
    expect(provider.loadError, isNotNull);
  });

  test('local repository adapter persists settings for isolated tests', () async {
    final database = AppDatabase();
    final repository = MockSettingsRepository(database);
    final provider = SettingsProvider(repository);
    await provider.load();

    expect(provider.settings, isNotNull);
    final updated = provider.settings!.bookingRules.copyWith(maxAdvanceDays: 45);
    await provider.updateRules(updated);

    expect(provider.settings!.bookingRules.maxAdvanceDays, 45);
    expect(database.settings.bookingRules.maxAdvanceDays, 45);

    await provider.setFormTheme(provider.formThemeId);
    expect(await repository.fetchBookingFormTheme(), provider.formThemeId);
  });
}
