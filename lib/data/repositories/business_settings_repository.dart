import 'dart:async';

import '../models/business_settings.dart';

/// Persistence boundary for the business identity/contact profile only.
/// Booking rules, schedules, and visual themes deliberately use separate flows.
abstract class BusinessSettingsRepository {
  Stream<void> get authChanges;

  Future<BusinessSettings> fetchSettings();

  Future<void> saveSettings(BusinessSettings settings);
}

class UnavailableBusinessSettingsRepository implements BusinessSettingsRepository {
  StateError _unavailable() => StateError(
        'برای مشاهده یا ویرایش اطلاعات مجموعه، اتصال Supabase و نشست معتبر لازم است.',
      );

  @override
  Stream<void> get authChanges => const Stream<void>.empty();

  @override
  Future<BusinessSettings> fetchSettings() async => throw _unavailable();

  @override
  Future<void> saveSettings(BusinessSettings settings) async => throw _unavailable();
}
