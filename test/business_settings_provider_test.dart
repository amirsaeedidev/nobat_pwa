import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:datetime/data/models/business_settings.dart';
import 'package:datetime/data/repositories/business_settings_repository.dart';
import 'package:datetime/features/settings/presentation/providers/business_settings_provider.dart';

class _FakeBusinessSettingsRepository implements BusinessSettingsRepository {
  final StreamController<void> events = StreamController<void>.broadcast();
  BusinessSettings value = const BusinessSettings(
    name: 'DateTime',
    slogan: '',
    description: '',
    phone: '',
    mobile: '',
    email: '',
    province: '',
    city: '',
    address: '',
    postalCode: '',
    latitude: 0,
    longitude: 0,
    instagram: '',
    telegram: '',
    whatsapp: '',
    website: '',
    publicSlug: '',
    logoText: '',
    workingHours: {},
    workSchedules: {},
    holidays: [],
    scheduleExceptions: [],
    smsProvider: SmsProviderSettings(providerName: '', endpoint: '', credit: 0),
  );
  bool fail = false;
  int reads = 0;
  int writes = 0;

  @override
  Stream<void> get authChanges => events.stream;

  @override
  Future<BusinessSettings> fetchSettings() async {
    reads++;
    if (fail) throw StateError('remote unavailable');
    return value;
  }

  @override
  Future<void> saveSettings(BusinessSettings settings) async {
    writes++;
    if (fail) throw StateError('remote unavailable');
    value = settings;
  }

  Future<void> dispose() => events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBusinessSettingsRepository repository;
  late BusinessSettingsProvider provider;

  setUp(() {
    repository = _FakeBusinessSettingsRepository();
    provider = BusinessSettingsProvider(repository);
  });

  tearDown(() async {
    provider.dispose();
    await repository.dispose();
  });

  test('loads business profile from repository without local database', () async {
    await provider.load();

    expect(provider.settings?.name, 'DateTime');
    expect(provider.loadError, isNull);
    expect(repository.reads, greaterThanOrEqualTo(1));
  });

  test('saves edited profile and re-reads persisted values', () async {
    await provider.load();
    await provider.saveBusiness(provider.settings!.copyWith(
      name: 'DateTime Studio',
      phone: '02112345678',
      city: 'تهران',
    ));

    expect(repository.writes, 1);
    expect(provider.settings?.name, 'DateTime Studio');
    expect(provider.settings?.phone, '02112345678');
    expect(provider.settings?.city, 'تهران');
  });

  test('does not replace a failed remote read with seeded settings', () async {
    repository.fail = true;
    await provider.load();

    expect(provider.settings, isNull);
    expect(provider.loadError, contains('remote unavailable'));
  });

  test('reloads the business profile after an auth change', () async {
    await provider.load();
    final previousReads = repository.reads;

    repository.value = repository.value.copyWith(name: 'Changed after login');
    repository.events.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(repository.reads, greaterThan(previousReads));
    expect(provider.settings?.name, 'Changed after login');
  });
}
