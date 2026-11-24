import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_settings.dart';
import '../models/employee.dart';
import 'settings_repository.dart';

/// Business settings persisted in tenant-scoped app_records. API credentials
/// are deliberately never returned to or stored by this public Flutter client.
class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository({
    required SupabaseClient client,
    required String? Function() businessId,
  })  : _client = client,
        _businessId = businessId;

  final SupabaseClient _client;
  final String? Function() _businessId;

  String _tenant() {
    if (_client.auth.currentUser == null) {
      throw StateError('نشست Supabase منقضی شده است؛ دوباره وارد شوید.');
    }
    final id = _businessId();
    if (id == null || id.isEmpty) {
      throw StateError('عضویت فعال مجموعه تأیید نشده است.');
    }
    return id;
  }

  static const _emptySms = SmsProviderSettings(
    providerName: '',
    endpoint: '',
    credit: 0,
  );
  static const _disabledNotifications = NotificationSettings(
    confirmationEnabled: false,
    reminderEnabled: false,
    cancellationEnabled: false,
    rescheduleEnabled: false,
    reminderHours: [],
    sendToStaff: false,
  );
  static const _unconfiguredRules = BookingRules(
    allowCustomerCancel: false,
    allowReschedule: false,
    maxReschedules: 0,
    minHoursBeforeChange: 0,
    maxAdvanceDays: 0,
    requireConfirmation: false,
    preventOverlap: false,
    slotIntervalMinutes: 0,
    cancelPenaltyCount: 0,
  );

  Map<String, dynamic> _shiftMap(Map<int, List<Shift>> value) => {
        for (final entry in value.entries)
          entry.key.toString(): entry.value.map((shift) => shift.toJson()).toList(),
      };

  Map<int, List<Shift>> _parseShiftMap(dynamic value) {
    if (value is! Map) return const {};
    return value.map((key, raw) => MapEntry(
      int.tryParse(key.toString()) ?? 0,
      raw is List
          ? raw.whereType<Map>().map((item) => Shift.fromJson(Map<String, dynamic>.from(item))).toList()
          : <Shift>[],
    ));
  }

  BusinessSettings _fromPayload(Map<String, dynamic> json, {required String businessName}) {
    final rawRules = json['booking_rules'] is Map
        ? Map<String, dynamic>.from(json['booking_rules'] as Map)
        : <String, dynamic>{};
    final rawNotifications = json['notifications'] is Map
        ? Map<String, dynamic>.from(json['notifications'] as Map)
        : <String, dynamic>{};
    final rawSms = json['sms_provider'] is Map
        ? Map<String, dynamic>.from(json['sms_provider'] as Map)
        : <String, dynamic>{};
    final rawExceptions = (json['schedule_exceptions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map((item) => ScheduleException(
          dateKey: item['date_key'] as String? ?? '',
          title: item['title'] as String? ?? '',
          isClosed: item['is_closed'] as bool? ?? true,
          shifts: (item['shifts'] as List? ?? const [])
              .whereType<Map>()
              .map((shift) => Shift.fromJson(Map<String, dynamic>.from(shift)))
              .toList(growable: false),
        )).toList(growable: false);

    return BusinessSettings(
      name: businessName,
      slogan: json['slogan'] as String? ?? '',
      description: json['description'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      mobile: json['mobile'] as String? ?? '',
      email: json['email'] as String? ?? '',
      province: json['province'] as String? ?? '',
      city: json['city'] as String? ?? '',
      address: json['address'] as String? ?? '',
      postalCode: json['postal_code'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      mapApps: (json['map_apps'] as List? ?? const []).whereType<String>().toList(),
      instagram: json['instagram'] as String? ?? '',
      telegram: json['telegram'] as String? ?? '',
      whatsapp: json['whatsapp'] as String? ?? '',
      website: json['website'] as String? ?? '',
      currency: json['currency'] as String? ?? '',
      logoText: json['logo_text'] as String? ?? '',
      workingHours: _parseShiftMap(json['working_hours']),
      workSchedules: _parseShiftMap(json['work_schedules']),
      holidays: (json['holidays'] as List? ?? const []).whereType<num>().map((v) => v.toInt()).toList(),
      scheduleExceptions: rawExceptions,
      smsProvider: SmsProviderSettings(
        providerName: rawSms['provider_name'] as String? ?? '',
        apiKey: '',
        username: '',
        password: '',
        senderNumber: rawSms['sender_number'] as String? ?? '',
        endpoint: rawSms['endpoint'] as String? ?? '',
        isEnabled: rawSms['is_enabled'] as bool? ?? false,
        status: SmsConnectionStatus.notConfigured,
        credit: 0,
      ),
      notifications: NotificationSettings(
        confirmationEnabled: rawNotifications['confirmation_enabled'] as bool? ?? false,
        reminderEnabled: rawNotifications['reminder_enabled'] as bool? ?? false,
        cancellationEnabled: rawNotifications['cancellation_enabled'] as bool? ?? false,
        rescheduleEnabled: rawNotifications['reschedule_enabled'] as bool? ?? false,
        reminderHours: (rawNotifications['reminder_hours'] as List? ?? const []).whereType<num>().map((v) => v.toInt()).toList(),
        sendToStaff: rawNotifications['send_to_staff'] as bool? ?? false,
      ),
      bookingRules: BookingRules(
        allowCustomerCancel: rawRules['allow_customer_cancel'] as bool? ?? false,
        allowReschedule: rawRules['allow_reschedule'] as bool? ?? false,
        maxReschedules: (rawRules['max_reschedules'] as num?)?.toInt() ?? 0,
        minHoursBeforeChange: (rawRules['min_hours_before_change'] as num?)?.toInt() ?? 0,
        maxAdvanceDays: (rawRules['max_advance_days'] as num?)?.toInt() ?? 0,
        requireConfirmation: rawRules['require_confirmation'] as bool? ?? false,
        preventOverlap: rawRules['prevent_overlap'] as bool? ?? false,
        slotIntervalMinutes: (rawRules['slot_interval_minutes'] as num?)?.toInt() ?? 0,
        cancelPenaltyCount: (rawRules['cancel_penalty_count'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Map<String, dynamic> _toPayload(BusinessSettings settings) => {
        'slogan': settings.slogan,
        'description': settings.description,
        'phone': settings.phone,
        'mobile': settings.mobile,
        'email': settings.email,
        'province': settings.province,
        'city': settings.city,
        'address': settings.address,
        'postal_code': settings.postalCode,
        'latitude': settings.latitude,
        'longitude': settings.longitude,
        'map_apps': settings.mapApps,
        'instagram': settings.instagram,
        'telegram': settings.telegram,
        'whatsapp': settings.whatsapp,
        'website': settings.website,
        'currency': settings.currency,
        'logo_text': settings.logoText,
        'working_hours': _shiftMap(settings.workingHours),
        'work_schedules': _shiftMap(settings.workSchedules),
        'holidays': settings.holidays,
        'schedule_exceptions': settings.scheduleExceptions.map((item) => {
          'date_key': item.dateKey,
          'title': item.title,
          'is_closed': item.isClosed,
          'shifts': item.shifts.map((shift) => shift.toJson()).toList(),
        }).toList(),
        'booking_rules': {
          'allow_customer_cancel': settings.bookingRules.allowCustomerCancel,
          'allow_reschedule': settings.bookingRules.allowReschedule,
          'max_reschedules': settings.bookingRules.maxReschedules,
          'min_hours_before_change': settings.bookingRules.minHoursBeforeChange,
          'max_advance_days': settings.bookingRules.maxAdvanceDays,
          'require_confirmation': settings.bookingRules.requireConfirmation,
          'prevent_overlap': settings.bookingRules.preventOverlap,
          'slot_interval_minutes': settings.bookingRules.slotIntervalMinutes,
          'cancel_penalty_count': settings.bookingRules.cancelPenaltyCount,
        },
        'notifications': {
          'confirmation_enabled': settings.notifications.confirmationEnabled,
          'reminder_enabled': settings.notifications.reminderEnabled,
          'cancellation_enabled': settings.notifications.cancellationEnabled,
          'reschedule_enabled': settings.notifications.rescheduleEnabled,
          'reminder_hours': settings.notifications.reminderHours,
          'send_to_staff': settings.notifications.sendToStaff,
        },
        // Never persist provider API keys/passwords in a client-writable JSON record.
        'sms_provider': {
          'provider_name': settings.smsProvider.providerName,
          'sender_number': settings.smsProvider.senderNumber,
          'endpoint': settings.smsProvider.endpoint,
          'is_enabled': false,
        },
      };

  @override
  Future<BusinessSettings> fetchSettings() async {
    final tenant = _tenant();
    final business = await _client.from('businesses').select('name')
        .eq('id', tenant).single();
    final row = await _client.from('app_records')
        .select('payload')
        .eq('business_id', tenant)
        .eq('entity_type', 'settings')
        .eq('record_id', 'business_settings')
        .maybeSingle();
    final payload = row?['payload'] is Map
        ? Map<String, dynamic>.from(row!['payload'] as Map)
        : <String, dynamic>{};
    return _fromPayload(payload, businessName: business['name'] as String? ?? '');
  }

  @override
  Future<void> saveSettings(BusinessSettings settings, {String? logTitle, String? logDescription}) async {
    final tenant = _tenant();
    final userId = _client.auth.currentUser!.id;
    await _client.from('businesses').update({'name': settings.name.trim()})
        .eq('id', tenant);
    await _client.from('app_records').upsert({
      'business_id': tenant,
      'entity_type': 'settings',
      'record_id': 'business_settings',
      'payload': _toPayload(settings),
      'created_by': userId,
      'updated_by': userId,
    }, onConflict: 'business_id,entity_type,record_id');
  }
}
