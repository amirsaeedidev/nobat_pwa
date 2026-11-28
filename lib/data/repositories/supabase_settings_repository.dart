import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_settings.dart';
import 'business_settings_repository.dart';

/// Supabase persistence for business identity and contact/location profile.
/// It intentionally does not write booking rules, work schedules, or themes.
class SupabaseSettingsRepository implements BusinessSettingsRepository {
  SupabaseSettingsRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> get authChanges =>
      _client.auth.onAuthStateChange.map<void>((_) {});

  Future<Map<String, dynamic>> _activeBusiness() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('برای دریافت تنظیمات مجموعه ابتدا وارد حساب شوید.');
    }

    final memberships = await _client
        .from('business_memberships')
        .select('business_id')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .limit(2);

    if (memberships.length != 1) {
      throw StateError(
        memberships.isEmpty
            ? 'عضویت فعال برای این حساب پیدا نشد.'
            : 'این حساب به چند مجموعه فعال دسترسی دارد؛ انتخاب مجموعه لازم است.',
      );
    }

    final businessId = memberships.single['business_id'] as String?;
    if (businessId == null || businessId.isEmpty) {
      throw StateError('شناسه مجموعه در عضویت فعال معتبر نیست.');
    }

    final business = await _client
        .from('businesses')
        .select('id,name')
        .eq('id', businessId)
        .single();
    return Map<String, dynamic>.from(business);
  }

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _string(dynamic value) => value is String ? value : '';

  @override
  Future<BusinessSettings> fetchSettings() async {
    final business = await _activeBusiness();
    final businessId = business['id'] as String;
    final row = await _client
        .from('business_settings')
        .select('settings')
        .eq('business_id', businessId)
        .maybeSingle();

    final data = _asMap(row?['settings']);
    final profile = _asMap(data['profile']);
    final location = _asMap(data['location']);

    // All business identity fields come from the server. Other settings
    // categories are intentionally not loaded or defaulted from demo data.
    return BusinessSettings(
      name: _string(business['name']),
      slogan: _string(profile['slogan']),
      description: _string(profile['description']),
      phone: _string(profile['phone']),
      mobile: _string(profile['mobile']),
      email: _string(profile['email']),
      province: _string(location['province']),
      city: _string(location['city']),
      address: _string(location['address']),
      postalCode: _string(location['postal_code']),
      latitude: (location['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (location['longitude'] as num?)?.toDouble() ?? 0,
      instagram: _string(profile['instagram']),
      telegram: _string(profile['telegram']),
      whatsapp: _string(profile['whatsapp']),
      website: _string(profile['website']),
      publicSlug: _string(profile['public_slug']),
      currency: _string(profile['currency']).isEmpty
          ? 'تومان'
          : _string(profile['currency']),
      logoText: _string(profile['logo_text']),
      workingHours: const {},
      workSchedules: const {},
      holidays: const [],
      scheduleExceptions: const [],
      smsProvider: const SmsProviderSettings(
        providerName: '',
        endpoint: '',
        credit: 0,
      ),
      notifications: const NotificationSettings(),
      bookingRules: const BookingRules(),
    );
  }

  @override
  Future<void> saveSettings(BusinessSettings settings) async {
    final business = await _activeBusiness();
    await _client.rpc('save_business_profile', params: {
      'p_business_id': business['id'],
      'p_name': settings.name.trim(),
      'p_settings': {
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
      },
    });
  }
}
