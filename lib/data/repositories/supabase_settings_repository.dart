import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_settings.dart';
import '../models/employee.dart';
import 'settings_repository.dart';

/// Reads and writes the single business owned/managed by the signed-in
/// platform administrator. Commercial settings never fall back to local data.
class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _business() async {
    if (_client.auth.currentUser == null) {
      throw StateError('برای دریافت تنظیمات مجموعه ابتدا وارد حساب مدیر کل شوید.');
    }
    final rows = await _client
        .from('businesses')
        .select('id,name,timezone')
        .limit(2);
    if (rows.length != 1) {
      throw StateError(
        rows.isEmpty
            ? 'مجموعه‌ای برای این حساب پیدا نشد.'
            : 'بیش از یک مجموعه پیدا شد؛ انتخاب مجموعه باید پیش از ادامه مشخص شود.',
      );
    }
    return Map<String, dynamic>.from(rows.single);
  }

  Future<Map<String, dynamic>?> _settingsRow(String businessId) async {
    final row = await _client
        .from('business_settings')
        .select('settings,booking_form')
        .eq('business_id', businessId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<BusinessSettings> fetchSettings() async {
    final business = await _business();
    final row = await _settingsRow(business['id'] as String);
    final data = _asMap(row?['settings']);
    final profile = _asMap(data['profile']);
    final location = _asMap(data['location']);
    final rules = _asMap(data['booking_rules']);
    final notifications = _asMap(data['notifications']);
    final workingHours = _decodeHours(data['working_hours']);
    final exceptions = _decodeExceptions(data['schedule_exceptions']);

    return BusinessSettings(
      name: business['name'] as String? ?? '',
      slogan: _string(profile['slogan']),
      description: _string(profile['description']),
      phone: _string(profile['phone']),
      mobile: _string(profile['mobile']),
      email: _string(profile['email']),
      province: _string(location['province']),
      city: _string(location['city']),
      address: _string(location['address']),
      postalCode: _string(location['postal_code']),
      latitude: _number(location['latitude']),
      longitude: _number(location['longitude']),
      instagram: _string(profile['instagram']),
      telegram: _string(profile['telegram']),
      whatsapp: _string(profile['whatsapp']),
      website: _string(profile['website']),
      publicSlug: _string(profile['public_slug']),
      currency: _string(profile['currency'], fallback: 'تومان'),
      logoText: _string(profile['logo_text']),
      workingHours: workingHours,
      workSchedules: workingHours,
      holidays: _intList(data['weekly_holidays']),
      scheduleExceptions: exceptions,
      bookingRules: _decodeRules(rules),
      notifications: _decodeNotifications(notifications),
      // Gateway credentials are intentionally not stored in this public
      // settings row. They require a server-side secret store/Edge Function.
      smsProvider: const SmsProviderSettings(
        providerName: '',
        endpoint: '',
        credit: 0,
      ),
    );
  }

  @override
  Future<void> saveSettings(
    BusinessSettings settings, {
    String? logTitle,
    String? logDescription,
  }) async {
    final business = await _business();
    final payload = <String, dynamic>{
      'profile': {
        'slogan': settings.slogan,
        'description': settings.description,
        'phone': settings.phone,
        'mobile': settings.mobile,
        'email': settings.email,
        'instagram': settings.instagram,
        'telegram': settings.telegram,
        'whatsapp': settings.whatsapp,
        'website': settings.website,
        'public_slug': settings.publicSlug,
        'currency': settings.currency,
        'logo_text': settings.logoText,
      },
      'location': {
        'province': settings.province,
        'city': settings.city,
        'address': settings.address,
        'postal_code': settings.postalCode,
        'latitude': settings.latitude,
        'longitude': settings.longitude,
      },
      'booking_rules': _encodeRules(settings.bookingRules),
      'working_hours': _encodeHours(settings.workingHours.isNotEmpty
          ? settings.workingHours
          : settings.workSchedules),
      'weekly_holidays': settings.holidays,
      'schedule_exceptions': _encodeExceptions(settings.scheduleExceptions),
      'notifications': _encodeNotifications(settings.notifications),
    };

    await _client.rpc('save_business_settings', params: {
      'p_business_id': business['id'],
      'p_name': settings.name.trim(),
      'p_settings': payload,
    });
  }

  @override
  Future<String> fetchBookingFormTheme() async {
    final business = await _business();
    final row = await _settingsRow(business['id'] as String);
    final form = _asMap(row?['booking_form']);
    return _string(form['theme_id'], fallback: 'pastel_pink');
  }

  @override
  Future<void> saveBookingFormTheme(String themeId) async {
    final business = await _business();
    final existing = await _settingsRow(business['id'] as String);
    final form = _asMap(existing?['booking_form']);
    form['theme_id'] = themeId;
    await _client.rpc('save_business_booking_form', params: {
      'p_business_id': business['id'],
      'p_booking_form': form,
    });
  }

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _string(dynamic value, {String fallback = ''}) =>
      value is String ? value : fallback;

  static double _number(dynamic value) =>
      value is num ? value.toDouble() : 0;

  static List<int> _intList(dynamic value) => value is List
      ? value.whereType<num>().map((item) => item.toInt()).toList()
      : <int>[];

  static Map<int, List<Shift>> _decodeHours(dynamic value) {
    final map = _asMap(value);
    return map.map((key, raw) => MapEntry(
          int.tryParse(key) ?? -1,
          raw is List
              ? raw
                  .whereType<Map>()
                  .map((item) => Shift.fromJson(Map<String, dynamic>.from(item)))
                  .toList()
              : <Shift>[],
        ))..removeWhere((key, _) => key < 0 || key > 6);
  }

  static Map<String, dynamic> _encodeHours(Map<int, List<Shift>> value) =>
      value.map((day, shifts) => MapEntry(
            day.toString(),
            shifts.map((shift) => shift.toJson()).toList(),
          ));

  static List<ScheduleException> _decodeExceptions(dynamic value) {
    if (value is! List) return <ScheduleException>[];
    return value.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final shifts = item['shifts'];
      return ScheduleException(
        dateKey: _string(item['date_key']),
        title: _string(item['title']),
        isClosed: item['is_closed'] as bool? ?? true,
        shifts: shifts is List
            ? shifts.whereType<Map>().map((shift) =>
                Shift.fromJson(Map<String, dynamic>.from(shift))).toList()
            : const <Shift>[],
      );
    }).toList();
  }

  static List<Map<String, dynamic>> _encodeExceptions(
          List<ScheduleException> value) =>
      value
          .map((item) => {
                'date_key': item.dateKey,
                'title': item.title,
                'is_closed': item.isClosed,
                'shifts': item.shifts.map((shift) => shift.toJson()).toList(),
              })
          .toList();

  static BookingRules _decodeRules(Map<String, dynamic> value) =>
      BookingRules(
        allowOnlineBooking: value['allow_online_booking'] as bool? ?? true,
        allowCustomerCancel: value['allow_customer_cancel'] as bool? ?? true,
        allowReschedule: value['allow_reschedule'] as bool? ?? true,
        maxReschedules: (value['max_reschedules'] as num?)?.toInt() ?? 1,
        minHoursBeforeChange:
            (value['min_hours_before_change'] as num?)?.toInt() ?? 2,
        maxAdvanceDays: (value['max_advance_days'] as num?)?.toInt() ?? 30,
        requireConfirmation: value['require_confirmation'] as bool? ?? false,
        preventOverlap: value['prevent_overlap'] as bool? ?? true,
        slotIntervalMinutes:
            (value['slot_interval_minutes'] as num?)?.toInt() ?? 15,
        cancelPenaltyCount:
            (value['cancel_penalty_count'] as num?)?.toInt() ?? 3,
      );

  static Map<String, dynamic> _encodeRules(BookingRules value) => {
        'allow_online_booking': value.allowOnlineBooking,
        'allow_customer_cancel': value.allowCustomerCancel,
        'allow_reschedule': value.allowReschedule,
        'max_reschedules': value.maxReschedules,
        'min_hours_before_change': value.minHoursBeforeChange,
        'max_advance_days': value.maxAdvanceDays,
        'require_confirmation': value.requireConfirmation,
        'prevent_overlap': value.preventOverlap,
        'slot_interval_minutes': value.slotIntervalMinutes,
        'cancel_penalty_count': value.cancelPenaltyCount,
      };

  static NotificationSettings _decodeNotifications(
          Map<String, dynamic> value) =>
      NotificationSettings(
        confirmationEnabled: value['confirmation_enabled'] as bool? ?? true,
        reminderEnabled: value['reminder_enabled'] as bool? ?? true,
        cancellationEnabled: value['cancellation_enabled'] as bool? ?? true,
        rescheduleEnabled: value['reschedule_enabled'] as bool? ?? true,
        reminderHours: _intList(value['reminder_hours']).isEmpty
            ? const [24, 2]
            : _intList(value['reminder_hours']),
        sendToStaff: value['send_to_staff'] as bool? ?? false,
      );

  static Map<String, dynamic> _encodeNotifications(NotificationSettings value) =>
      {
        'confirmation_enabled': value.confirmationEnabled,
        'reminder_enabled': value.reminderEnabled,
        'cancellation_enabled': value.cancellationEnabled,
        'reschedule_enabled': value.rescheduleEnabled,
        'reminder_hours': value.reminderHours,
        'send_to_staff': value.sendToStaff,
      };
}
