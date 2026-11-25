import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_finance.dart';
import 'business_finance_repository.dart';

/// Tenant-scoped finance records. Mutations are delegated to validated SQL RPCs;
/// direct table writes are intentionally unavailable to the Flutter client.
class SupabaseBusinessFinanceRepository implements BusinessFinanceRepository {
  SupabaseBusinessFinanceRepository({
    required SupabaseClient client,
    required String? Function() businessId,
  }) : _client = client, _businessId = businessId;

  static const _bucket = 'business-finance-documents';
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

  String _methodKey(BusinessPaymentMethod value) => switch (value) {
    BusinessPaymentMethod.cash => 'cash',
    BusinessPaymentMethod.pos => 'pos',
    BusinessPaymentMethod.bankTransfer => 'bank_transfer',
    BusinessPaymentMethod.wallet => 'wallet',
    BusinessPaymentMethod.other => 'other',
  };

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Future<List<AppointmentPayment>> fetchPayments({
    DateTime? from,
    DateTime? to,
    String? appointmentId,
  }) async {
    final tenant = _tenant();
    var query = _client.from('appointment_payments')
        .select('id,business_id,appointment_id,customer_id,amount_toman,method,payment_type,description,reverses_payment_id,idempotency_key,created_by,created_at')
        .eq('business_id', tenant);
    if (from != null) query = query.gte('created_at', from.toUtc().toIso8601String());
    if (to != null) query = query.lt('created_at', to.toUtc().toIso8601String());
    if (appointmentId != null) query = query.eq('appointment_id', appointmentId);
    final rows = await query.order('created_at', ascending: false);
    return rows.map((row) => AppointmentPayment.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  @override
  Future<List<BusinessExpense>> fetchExpenses({
    DateTime? from,
    DateTime? to,
    bool postedOnly = false,
  }) async {
    final tenant = _tenant();
    var query = _client.from('business_expenses')
        .select('id,business_id,amount_toman,category,description,source_document_id,status,created_by,created_at,updated_at,expense_date,payment_method,idempotency_key,related_appointment_id,related_customer_id,reversed_at,reversed_by,reversal_reason')
        .eq('business_id', tenant);
    if (from != null) query = query.gte('expense_date', _dateOnly(from));
    if (to != null) query = query.lt('expense_date', _dateOnly(to));
    if (postedOnly) query = query.eq('status', 'posted');
    final rows = await query.order('expense_date', ascending: false).order('created_at', ascending: false);
    return rows.map((row) => BusinessExpense.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  @override
  Future<List<BusinessFinanceDocument>> fetchDocuments({
    String? appointmentId,
    String? customerId,
    String? expenseId,
    String? paymentId,
    bool activeOnly = true,
  }) async {
    final tenant = _tenant();
    var query = _client.from('business_finance_documents')
        .select('id,business_id,document_type,document_number,appointment_id,customer_id,expense_id,payment_id,amount_toman,storage_path,file_name,mime_type,file_size_bytes,notes,idempotency_key,status,created_by,created_at,voided_by,voided_at')
        .eq('business_id', tenant);
    if (appointmentId != null) query = query.eq('appointment_id', appointmentId);
    if (customerId != null) query = query.eq('customer_id', customerId);
    if (expenseId != null) query = query.eq('expense_id', expenseId);
    if (paymentId != null) query = query.eq('payment_id', paymentId);
    if (activeOnly) query = query.eq('status', 'active');
    final rows = await query.order('created_at', ascending: false);
    return rows.map((row) => BusinessFinanceDocument.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  @override
  Future<String> recordAppointmentPayment({
    required String appointmentId,
    required int amount,
    required BusinessPaymentMethod method,
    required String description,
    required String idempotencyKey,
    BusinessPaymentType type = BusinessPaymentType.receipt,
    String? reversesPaymentId,
  }) async {
    final result = await _client.rpc('record_appointment_payment', params: {
      'p_business_id': _tenant(),
      'p_appointment_id': appointmentId,
      'p_amount_toman': amount,
      'p_method': _methodKey(method),
      'p_payment_type': type.name,
      'p_description': description.trim(),
      'p_idempotency_key': idempotencyKey,
      'p_reverses_payment_id': reversesPaymentId,
    });
    return result as String;
  }

  @override
  Future<String> recordBusinessExpense({
    required int amount,
    required BusinessExpenseCategory category,
    required String description,
    required DateTime expenseDate,
    required String idempotencyKey,
    BusinessPaymentMethod? paymentMethod,
    String? sourceDocumentId,
    String? relatedAppointmentId,
    String? relatedCustomerId,
  }) async {
    final result = await _client.rpc('record_business_expense', params: {
      'p_business_id': _tenant(),
      'p_amount_toman': amount,
      'p_category': category.name,
      'p_description': description.trim(),
      'p_expense_date': _dateOnly(expenseDate),
      'p_payment_method': paymentMethod == null ? null : _methodKey(paymentMethod),
      'p_source_document_id': sourceDocumentId,
      'p_related_appointment_id': relatedAppointmentId,
      'p_related_customer_id': relatedCustomerId,
      'p_idempotency_key': idempotencyKey,
    });
    return result as String;
  }

  @override
  Future<String> replaceBusinessExpense({
    required String expenseId,
    required int amount,
    required BusinessExpenseCategory category,
    required String description,
    required DateTime expenseDate,
    required String idempotencyKey,
    required String reason,
    BusinessPaymentMethod? paymentMethod,
    String? sourceDocumentId,
    String? relatedAppointmentId,
    String? relatedCustomerId,
  }) async {
    final result = await _client.rpc('replace_business_expense', params: {
      'p_business_id': _tenant(),
      'p_expense_id': expenseId,
      'p_amount_toman': amount,
      'p_category': category.name,
      'p_description': description.trim(),
      'p_expense_date': _dateOnly(expenseDate),
      'p_payment_method': paymentMethod == null ? null : _methodKey(paymentMethod),
      'p_source_document_id': sourceDocumentId,
      'p_related_appointment_id': relatedAppointmentId,
      'p_related_customer_id': relatedCustomerId,
      'p_idempotency_key': idempotencyKey,
      'p_reason': reason.trim(),
    });
    return result as String;
  }

  @override
  Future<void> reverseBusinessExpense({
    required String expenseId,
    required String reason,
  }) async {
    await _client.rpc('reverse_business_expense', params: {
      'p_business_id': _tenant(),
      'p_expense_id': expenseId,
      'p_reason': reason.trim(),
    });
  }

  @override
  Future<String> createDocument({
    required String documentType,
    String? documentNumber,
    String? appointmentId,
    String? customerId,
    String? expenseId,
    String? paymentId,
    int? amount,
    String? storagePath,
    String? fileName,
    String? mimeType,
    int? fileSizeBytes,
    String notes = '',
    String? idempotencyKey,
  }) async {
    final result = await _client.rpc('create_business_finance_document', params: {
      'p_business_id': _tenant(),
      'p_document_type': documentType,
      'p_document_number': documentNumber,
      'p_appointment_id': appointmentId,
      'p_customer_id': customerId,
      'p_expense_id': expenseId,
      'p_payment_id': paymentId,
      'p_amount_toman': amount,
      'p_storage_path': storagePath,
      'p_file_name': fileName,
      'p_mime_type': mimeType,
      'p_file_size_bytes': fileSizeBytes,
      'p_notes': notes.trim(),
      'p_idempotency_key': idempotencyKey,
    });
    return result as String;
  }

  @override
  Future<void> voidDocument({
    required String documentId,
    required String reason,
  }) async {
    await _client.rpc('void_business_finance_document', params: {
      'p_business_id': _tenant(),
      'p_document_id': documentId,
      'p_reason': reason.trim(),
    });
  }

  @override
  Future<String> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String documentType,
    required String idempotencyKey,
    String? documentNumber,
    String? appointmentId,
    String? customerId,
    String? expenseId,
    String? paymentId,
    int? amount,
    String notes = '',
  }) async {
    final tenant = _tenant();
    const allowedMimeTypes = {'application/pdf','image/jpeg','image/png','image/webp'};
    if (bytes.isEmpty || bytes.length > 26214400) {
      throw ArgumentError('حجم فایل باید بین ۱ بایت تا ۲۵ مگابایت باشد.');
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      throw ArgumentError('نوع فایل سند مالی پشتیبانی نمی‌شود.');
    }
    final safeKey = idempotencyKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeName = fileName.split('/').last.split(String.fromCharCode(92)).last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safeKey.length < 8 || safeName.isEmpty) {
      throw ArgumentError('شناسه یکتا و نام فایل معتبر نیست.');
    }
    final path = '$tenant/$safeKey/$safeName';
    final documentId = await createDocument(
      documentType: documentType,
      documentNumber: documentNumber,
      appointmentId: appointmentId,
      customerId: customerId,
      expenseId: expenseId,
      paymentId: paymentId,
      amount: amount,
      storagePath: path,
      fileName: safeName,
      mimeType: mimeType,
      fileSizeBytes: bytes.length,
      notes: notes,
      idempotencyKey: idempotencyKey,
    );
    try {
      await _client.storage.from(_bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mimeType, upsert: false),
      );
    } catch (error) {
      // An already-uploaded object on an idempotent retry is a successful prior result.
      try {
        await _client.storage.from(_bucket).createSignedUrl(path, 60);
      } catch (_) {
        try {
          await voidDocument(
            documentId: documentId,
            reason: 'بارگذاری فایل سند ناموفق بود: $error',
          );
        } catch (_) {}
        rethrow;
      }
    }
    return documentId;
  }

  @override
  Future<String> createDocumentDownloadUrl(
    String storagePath, {
    Duration expiresIn = const Duration(minutes: 5),
  }) async {
    final tenant = _tenant();
    if (!storagePath.startsWith('$tenant/')) {
      throw StateError('مسیر سند متعلق به این مجموعه نیست.');
    }
    return _client.storage.from(_bucket).createSignedUrl(storagePath, expiresIn.inSeconds);
  }
}
