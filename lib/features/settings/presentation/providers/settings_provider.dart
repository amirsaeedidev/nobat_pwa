import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../data/models/business_settings.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/settings_repository.dart';

/// Commercial settings are remote; only the application palette is local.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._repository) {
    load();
  }

  final SettingsRepository _repository;

  BusinessSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String _paletteId = 'pastel_pink';
  String _formThemeId = 'pastel_pink';

  BusinessSettings? get settings => _settings;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get loadError => _loadError;
  AppPalette get palette => AppPalette.byId(_paletteId);
  AppFormTheme get formTheme => AppFormTheme.byId(_formThemeId);
  Color get formAccentColor => formTheme.accent;
  String get formThemeId => _formThemeId;
  String get paletteId => _paletteId;
  String get ownerName => 'مدیر کل';
  String get ownerRole => 'مدیر کل';
  int get totalUnread => 0;

  BookingRules get rules => _settings?.bookingRules ?? const BookingRules();
  Map<int, List<Shift>> get workingHours => _settings?.workingHours ?? const {};
  List<int> get holidays => _settings?.holidays ?? const [];
  List<ScheduleException> get scheduleExceptions =>
      _settings?.scheduleExceptions ?? const [];
  SmsProviderSettings get smsProvider =>
      _settings?.smsProvider ?? const SmsProviderSettings(
        providerName: '',
        endpoint: '',
        credit: 0,
      );
  NotificationSettings get notifications =>
      _settings?.notifications ?? const NotificationSettings();

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _paletteId =
          AppPalette.byId(prefs.getString('datetime_palette') ?? 'pastel_pink').id;
    } catch (error) {
      // Local appearance preferences must not block commercial settings.
      debugPrint('Could not load local app palette preference: $error');
    }

    try {
      _settings = await _repository.fetchSettings();
      _formThemeId = AppFormTheme.byId(
        await _repository.fetchBookingFormTheme(),
      ).id;
      _loadError = null;
    } catch (error, stackTrace) {
      _settings = null;
      _loadError = error.toString();
      debugPrint('Remote settings load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setPalette(String id) async {
    _paletteId = AppPalette.byId(id).id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('datetime_palette', _paletteId);
  }

  /// The booking-form theme belongs to the business and is shared by clients.
  Future<void> setFormTheme(String id) async {
    final nextId = AppFormTheme.byId(id).id;
    await _repository.saveBookingFormTheme(nextId);
    _formThemeId = nextId;
    notifyListeners();
  }

  Future<void> _persist(
    BusinessSettings updated, {
    String? logTitle,
    String? logDescription,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      await _repository.saveSettings(
        updated,
        logTitle: logTitle,
        logDescription: logDescription,
      );
      _settings = await _repository.fetchSettings();
      _loadError = null;
    } catch (error) {
      _loadError = error.toString();
      rethrow;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> saveBusiness(
    BusinessSettings settings, {
    String? logTitle,
    String? logDescription,
  }) =>
      _persist(
        settings,
        logTitle: logTitle,
        logDescription: logDescription,
      );

  Future<void> updateRules(BookingRules rules) async {
    final current = _settings;
    if (current == null) throw StateError(_loadError ?? 'تنظیمات مجموعه بارگذاری نشده است.');
    await _persist(
      current.copyWith(bookingRules: rules),
      logTitle: 'تغییر قواعد رزرو',
      logDescription: 'قواعد رزرو، لغو و جابه‌جایی در سرور به‌روزرسانی شد.',
    );
  }

  Future<void> updateNotifications(NotificationSettings notifications) async {
    final current = _settings;
    if (current == null) throw StateError(_loadError ?? 'تنظیمات مجموعه بارگذاری نشده است.');
    await _persist(
      current.copyWith(notifications: notifications),
      logTitle: 'تغییر تنظیمات اطلاع‌رسانی',
      logDescription: 'تنظیمات اطلاع‌رسانی در سرور به‌روزرسانی شد.',
    );
  }

  Future<void> updateWorkingHours(
    Map<int, List<Shift>> hours, {
    List<int>? holidays,
  }) async {
    final current = _settings;
    if (current == null) throw StateError(_loadError ?? 'تنظیمات مجموعه بارگذاری نشده است.');
    await _persist(
      current.copyWith(
        workingHours: hours,
        workSchedules: hours,
        holidays: holidays ?? current.holidays,
      ),
      logTitle: 'تغییر ساعت کاری',
      logDescription: 'ساعات کاری و تعطیلات هفتگی در سرور به‌روزرسانی شد.',
    );
  }

  Future<void> updateScheduleExceptions(
    List<ScheduleException> exceptions,
  ) async {
    final current = _settings;
    if (current == null) throw StateError(_loadError ?? 'تنظیمات مجموعه بارگذاری نشده است.');
    await _persist(
      current.copyWith(scheduleExceptions: List.unmodifiable(exceptions)),
      logTitle: 'تغییر محدودیت‌های تقویم',
      logDescription: 'تعطیلات و ساعات ویژه تاریخ‌دار در سرور به‌روزرسانی شد.',
    );
  }

  /// SMS gateway credentials must be stored in a server-side secret store,
  /// never in the client-readable business settings JSON.
  Future<void> updateProvider(
    SmsProviderSettings provider, {
    String? logTitle,
    String? logDescription,
  }) async {
    throw UnsupportedError(
      'ذخیره اطلاعات محرمانه پنل پیامک باید از طریق Secret/Edge Function انجام شود.',
    );
  }
}
