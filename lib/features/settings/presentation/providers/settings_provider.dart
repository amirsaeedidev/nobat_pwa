import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/business_settings.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/settings_repository.dart';

/// تنظیمات ظاهری و اطلاعات مجموعه.
class SettingsProvider extends DbBoundProvider {
  SettingsProvider(this._repository, AppDatabase db, {SupabaseAuthStateNotifier? authStateNotifier}) : super(db, authStateNotifier: authStateNotifier) {
    load();
  }

  final SettingsRepository _repository;

  BusinessSettings? _settings;
  bool _loading = true;
  String _paletteId = 'pastel_pink';
  String _formThemeId = 'pastel_pink';
  bool _saving = false;

  BusinessSettings? get settings => _settings;
  bool get loading => _loading;
  bool get saving => _saving;
  AppPalette get palette => AppPalette.byId(_paletteId);
  AppFormTheme get formTheme => AppFormTheme.byId(_formThemeId);
  Color get formAccentColor => formTheme.accent;
  String get formThemeId => _formThemeId;
  String get paletteId => _paletteId;
  String get ownerName => authStateNotifier?.userEmail ?? 'کاربر';
  String get ownerRole => authStateNotifier?.roleLabel ?? 'بدون نقش';
  int get totalUnread => 0;

  BookingRules get rules => _settings?.bookingRules ?? const BookingRules();
  Map<int, List<Shift>> get workingHours => _settings?.workingHours ?? const {};
  List<int> get holidays => _settings?.holidays ?? const [];
  List<ScheduleException> get scheduleExceptions => _settings?.scheduleExceptions ?? const [];
  SmsProviderSettings get smsProvider => _settings?.smsProvider ?? const SmsProviderSettings();
  NotificationSettings get notifications => _settings?.notifications ?? const NotificationSettings();

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _paletteId = AppPalette.byId(prefs.getString('datetime_palette') ?? 'pastel_pink').id;
      _formThemeId = AppFormTheme.byId(prefs.getString('datetime_form_theme') ?? 'pastel_pink').id;
      _settings = await _repository.fetchSettings();
    } catch (error, stackTrace) {
      debugPrint('Settings remote load failed; no local/demo fallback is shown: $error');
      debugPrintStack(stackTrace: stackTrace);
      _settings = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onAuthenticatedTenantChanged() => unawaited(load());

  @override
  void onTenantContextCleared() {
    _settings = null;
    _loading = false;
  }

  @override
  void onDatabaseChanged() {
    unawaited(load());
  }

  Future<void> setPalette(String id) async {
    _paletteId = AppPalette.byId(id).id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('datetime_palette', _paletteId);
  }

  Future<void> setFormTheme(String id) async {
    _formThemeId = AppFormTheme.byId(id).id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('datetime_form_theme', _formThemeId);
  }

  Future<void> saveBusiness(BusinessSettings settings, {String? logTitle, String? logDescription}) async {
    _saving = true;
    notifyListeners();
    try {
      await _repository.saveSettings(settings, logTitle: logTitle, logDescription: logDescription);
      _settings = await _repository.fetchSettings();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> updateRules(BookingRules rules) async {
    final current = _settings;
    if (current == null) return;
    await _repository.saveSettings(
      current.copyWith(bookingRules: rules),
      logTitle: 'تغییر قواعد رزرو',
      logDescription: 'قواعد لغو و جابه‌جایی نوبت به‌روزرسانی شد.',
    );
    _settings = await _repository.fetchSettings();
    notifyListeners();
  }

  Future<void> updateNotifications(NotificationSettings notifications) async {
    final current = _settings;
    if (current == null) return;
    await _repository.saveSettings(
      current.copyWith(notifications: notifications),
      logTitle: 'تغییر تنظیمات اطلاع‌رسانی',
      logDescription: 'تنظیمات پیامک‌های خودکار به‌روزرسانی شد.',
    );
    _settings = await _repository.fetchSettings();
    notifyListeners();
  }

  Future<void> updateWorkingHours(Map<int, List<Shift>> hours, {List<int>? holidays}) async {
    final current = _settings;
    if (current == null) return;
    await _repository.saveSettings(
      current.copyWith(workingHours: hours, workSchedules: hours, holidays: holidays ?? current.holidays),
      logTitle: 'تغییر ساعت کاری',
      logDescription: 'شیفت‌های کاری و روزهای تعطیل به‌روزرسانی شد.',
    );
    _settings = await _repository.fetchSettings();
    notifyListeners();
  }

  Future<void> updateScheduleExceptions(List<ScheduleException> exceptions) async {
    final current = _settings;
    if (current == null) return;
    await _repository.saveSettings(current.copyWith(scheduleExceptions: List.unmodifiable(exceptions)), logTitle: 'تغییر محدودیت‌های تقویم', logDescription: 'تعطیلات و ساعات ویژه تاریخ‌دار به‌روزرسانی شد.');
    _settings = await _repository.fetchSettings();
    notifyListeners();
  }

  Future<void> updateProvider(SmsProviderSettings provider, {String? logTitle, String? logDescription}) async {
    final current = _settings;
    if (current == null) return;
    await _repository.saveSettings(
      current.copyWith(smsProvider: provider),
      logTitle: logTitle ?? 'به‌روزرسانی پنل پیامک',
      logDescription: logDescription ?? 'تنظیمات پنل پیامک ذخیره شد.',
    );
    _settings = await _repository.fetchSettings();
    notifyListeners();
  }
}
