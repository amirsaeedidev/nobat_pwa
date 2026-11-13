import 'package:flutter/foundation.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/providers/db_bound_provider.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/business_settings.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/settings_repository.dart';

/// تنظیمات ظاهری و اطلاعات مجموعه.
class SettingsProvider extends DbBoundProvider {
  SettingsProvider(this._repository, AppDatabase db) : super(db) {
    load();
  }

  final SettingsRepository _repository;

  BusinessSettings? _settings;
  bool _loading = true;
  String _paletteId = 'navy';
  bool _saving = false;

  BusinessSettings? get settings => _settings;
  bool get loading => _loading;
  bool get saving => _saving;
  AppPalette get palette => AppPalette.byId(_paletteId);
  String get paletteId => _paletteId;
  String get ownerName => 'فاطمه رضایی';
  String get ownerRole => 'مدیر مجموعه';
  int get totalUnread => 3;

  BookingRules get rules => _settings?.bookingRules ?? const BookingRules();
  Map<int, List<Shift>> get workingHours => _settings?.workingHours ?? const {};
  List<int> get holidays => _settings?.holidays ?? const [];
  SmsProviderSettings get smsProvider => _settings?.smsProvider ?? const SmsProviderSettings();
  NotificationSettings get notifications => _settings?.notifications ?? const NotificationSettings();

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _settings = await _repository.fetchSettings();
    } catch (error, stackTrace) {
      debugPrint('Settings mock load failed; using seeded data: $error');
      debugPrintStack(stackTrace: stackTrace);
      _settings = db.settings;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onDatabaseChanged() {
    _settings = db.settings;
    notifyListeners();
  }

  Future<void> setPalette(String id) async {
    _paletteId = id;
    notifyListeners();
  }

  Future<void> saveBusiness(BusinessSettings settings, {String? logTitle, String? logDescription}) async {
    _saving = true;
    notifyListeners();
    try {
      await _repository.saveSettings(settings, logTitle: logTitle, logDescription: logDescription);
      _settings = db.settings;
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
    _settings = db.settings;
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
    _settings = db.settings;
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
    _settings = db.settings;
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
    _settings = db.settings;
    notifyListeners();
  }
}
