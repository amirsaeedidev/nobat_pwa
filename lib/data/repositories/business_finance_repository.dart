import '../models/business_finance.dart';

abstract class BusinessFinanceRepository {
  Future<List<AppointmentPayment>> fetchPayments({
    DateTime? from,
    DateTime? to,
    String? appointmentId,
  });

  Future<List<BusinessExpense>> fetchExpenses({
    DateTime? from,
    DateTime? to,
    bool postedOnly = false,
  });

  Future<List<BusinessFinanceDocument>> fetchDocuments({
    String? appointmentId,
    String? customerId,
    String? expenseId,
    String? paymentId,
    bool activeOnly = true,
  });

  Future<String> recordAppointmentPayment({
    required String appointmentId,
    required int amount,
    required BusinessPaymentMethod method,
    required String description,
    required String idempotencyKey,
    BusinessPaymentType type = BusinessPaymentType.receipt,
    String? reversesPaymentId,
  });

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
  });

  Future<void> reverseBusinessExpense({
    required String expenseId,
    required String reason,
  });

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
  });

  Future<void> voidDocument({
    required String documentId,
    required String reason,
  });

  Future<String> createDocumentDownloadUrl(String storagePath, {Duration expiresIn = const Duration(minutes: 5)});
}
