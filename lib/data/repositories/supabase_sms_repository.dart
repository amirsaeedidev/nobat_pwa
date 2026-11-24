import '../../core/models/page_result.dart';
import '../models/business_settings.dart';
import '../models/enums.dart';
import '../models/sms_message.dart';
import 'sms_repository.dart';

/// No SMS gateway/table is configured in Supabase yet. Reads are honestly
/// empty and every write/send operation fails explicitly instead of creating
/// fabricated delivered messages or provider balances.
class SupabaseSmsRepository implements SmsRepository {
  const SupabaseSmsRepository();

  static const _emptyProvider = SmsProviderSettings(
    providerName: '',
    endpoint: '',
    status: SmsConnectionStatus.notConfigured,
    credit: 0,
  );

  @override
  Future<PageResult<SmsMessage>> fetchMessages({
    String query = '',
    SmsStatus? status,
    int page = 1,
    int pageSize = 8,
  }) async => PageResult.empty(pageSize: pageSize);

  @override
  Future<SmsStats> fetchStats() async => const SmsStats(
    total: 0, delivered: 0, sent: 0, pending: 0, failed: 0, credit: 0,
  );

  @override
  Future<List<SmsTemplate>> fetchTemplates() async => const [];

  @override
  Future<SmsProviderSettings> fetchProviderSettings() async => _emptyProvider;

  StateError _notConfigured() =>
      StateError('درگاه پیامک هنوز به سرویس واقعی متصل نشده است؛ هیچ پیامکی ارسال نشد.');

  @override
  Future<void> updateTemplate(SmsTemplate template) async => throw _notConfigured();

  @override
  Future<void> updateProviderSettings(SmsProviderSettings settings) async => throw _notConfigured();

  @override
  Future<SmsMessage> sendMock({
    required String recipientName,
    required String phone,
    required String templateKey,
    required String templateLabel,
    required String content,
  }) async => throw _notConfigured();

  @override
  Future<SmsConnectionStatus> testConnection(SmsProviderSettings settings) async =>
      throw _notConfigured();

  @override
  Future<void> updateNotifications(NotificationSettings notifications) async =>
      throw StateError('ذخیره تنظیمات پیامک تا زمان اتصال سرویس واقعی در دسترس نیست.');
}
