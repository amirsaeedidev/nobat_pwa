import 'package:shared_preferences/shared_preferences.dart';

import '../mock/app_database.dart';
import '../models/appointment.dart';
import '../models/business_finance.dart';
import '../models/employee_finance.dart';
import '../models/employee_wallet.dart';
import '../models/service.dart';
import 'supabase_repository.dart';

enum GlobalSearchType {
  customer('مشتری', 'مشتریان'),
  employee('پرسنل', 'پرسنل'),
  service('خدمت', 'خدمات'),
  category('دسته‌بندی', 'دسته‌بندی خدمات'),
  appointment('نوبت', 'نوبت‌ها'),
  transaction('تراکنش مالی', 'تراکنش‌های مالی'),
  document('سند و سابقه', 'اسناد و سوابق'),
  activity('فعالیت', 'سوابق فعالیت');

  const GlobalSearchType(this.label, this.pluralLabel);
  final String label;
  final String pluralLabel;
}

class GlobalSearchResult {
  const GlobalSearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.details,
    required this.route,
    this.date,
    this.score = 0,
  });

  final String id;
  final GlobalSearchType type;
  final String title;
  final String subtitle;
  final String details;
  final String route;
  final DateTime? date;
  final int score;
}

/// جست‌وجوی مشترک؛ منبع پیش‌فرض Mock برای عملکرد کامل آفلاین است.
/// در صورت فراهم‌کردن remote و businessId، نتایج مجاز app_records نیز ادغام می‌شوند.
class GlobalSearchRepository {
  GlobalSearchRepository(
    this._database, {
    SupabaseRepository? remote,
    String? businessId,
  })  : _remote = remote,
        _businessId = businessId;

  final AppDatabase _database;
  final SupabaseRepository? _remote;
  final String? _businessId;
  String? _resolvedBusinessId;
  bool _businessResolutionAttempted = false;

  static const _historyLimit = 8;
  static const _categoryPrefix = '__category__::';

  String get _historyKey =>
      'datetime.global_search.recent.${_database.currentAccessAccount.id}';

  static String normalize(String value) {
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const latinDigits = '0123456789';
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final faIndex = persianDigits.indexOf(char);
      final arIndex = arabicDigits.indexOf(char);
      if (faIndex >= 0) {
        buffer.write(latinDigits[faIndex]);
      } else if (arIndex >= 0) {
        buffer.write(latinDigits[arIndex]);
      } else {
        buffer.write(char);
      }
    }
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ۀ', 'ه')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[أإٱ]'), 'ا')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('\u200c', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matches(String query, Iterable<Object?> values) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) return false;
    final haystack = normalize(values.where((value) => value != null).join(' '));
    return normalizedQuery.split(' ').where((part) => part.isNotEmpty).every(haystack.contains);
  }

  int _score(String query, String title) {
    final q = normalize(query);
    final t = normalize(title);
    if (t == q) return 100;
    if (t.startsWith(q)) return 60;
    if (t.contains(q)) return 35;
    return 10;
  }

  Future<List<GlobalSearchResult>> search(
    String query, {
    GlobalSearchType? type,
    int limit = 60,
  }) async {
    if (normalize(query).isEmpty) return const [];
    final results = <GlobalSearchResult>[];
    final filterType = type;

    void add({
      required String id,
      required GlobalSearchType type,
      required String title,
      required String subtitle,
      required String details,
      required String route,
      required Iterable<Object?> searchable,
      DateTime? date,
    }) {
      if (filterType != null && type != filterType) return;
      if (!_matches(query, [...searchable, title, subtitle, details, id])) return;
      if (!_database.canOpenRoute(route)) return;
      results.add(GlobalSearchResult(
        id: id,
        type: type,
        title: title,
        subtitle: subtitle,
        details: details,
        route: route,
        date: date,
        score: _score(query, title),
      ));
    }


    if (_database.hasPermission('customers.view')) {
      for (final customer in _database.customers) {
        final canViewHistory = _database.hasPermission('customers.history');
        add(
          id: customer.id,
          type: GlobalSearchType.customer,
          title: customer.fullName,
          subtitle: customer.phone,
          details: canViewHistory
              ? [
                  if (customer.tags.isNotEmpty) customer.tags.join('، '),
                  if (customer.visitCount > 0) '${customer.visitCount} مراجعه',
                  if (customer.notes.isNotEmpty) customer.notes,
                ].join(' • ')
              : '',
          route: canViewHistory ? '/customers/${customer.id}' : '/customers',
          searchable: [
            customer.fullName,
            customer.phone,
            if (canViewHistory) ...[customer.notes, customer.tags, customer.id],
          ],
          date: customer.lastVisitAt ?? customer.createdAt,
        );
      }
    }

    final canListEmployees = _database.hasPermission('employees.view_list');
    final canViewOwnProfile = _database.hasPermission('employees.view_profile');
    if (canListEmployees || canViewOwnProfile) {
      for (final employee in _database.employees) {
        if (!_database.canViewEmployee(employee.id)) continue;
        if (!canListEmployees && _database.currentAccessAccount.employeeId != employee.id) continue;
        final canViewProfile = _database.canOpenRoute('/employees/${employee.id}');
        final route = canViewProfile ? '/employees/${employee.id}' : '/employees';
        add(
          id: employee.id,
          type: GlobalSearchType.employee,
          title: employee.fullName,
          subtitle: employee.title.isEmpty ? employee.phone : '${employee.title} • ${employee.phone}',
          details: canViewProfile
              ? [employee.email, employee.specialties.join('، '), employee.notes].where((v) => v.isNotEmpty).join(' • ')
              : '',
          route: route,
          searchable: [
            employee.fullName,
            employee.phone,
            if (canViewProfile) ...[employee.email, employee.title, employee.specialties, employee.notes, employee.id],
          ],
        );
      }
    }

    if (_database.hasPermission('services.manage') && _database.canOpenRoute('/services')) {
      for (final service in _database.services) {
        add(
          id: service.id,
          type: GlobalSearchType.service,
          title: service.title,
          subtitle: service.category,
          details: '${service.price} تومان • ${service.durationMinutes} دقیقه • ${service.isActive ? 'فعال' : 'غیرفعال'} • ${service.description}',
          route: '/services/${service.id}',
          searchable: [service.title, service.description, service.category, service.price, service.durationMinutes, service.id],
        );
      }
      for (final category in _database.serviceCategories) {
        add(
          id: category,
          type: GlobalSearchType.category,
          title: category,
          subtitle: 'دسته‌بندی خدمات',
          details: '${_database.services.where((service) => service.category == category).length} خدمت',
          route: '/services',
          searchable: [category],
        );
      }
    }

    final canViewAllAppointments = _database.hasPermission('appointments.view_all');
    final canViewOwnAppointments = _database.hasPermission('appointments.view_self');
    if (canViewAllAppointments || canViewOwnAppointments) {
      for (final appointment in _database.appointments) {
        final route = '/appointments/${appointment.id}';
        if (!_database.canOpenRoute(route)) continue;
        add(
          id: appointment.id,
          type: GlobalSearchType.appointment,
          title: '${appointment.customerName} • ${appointment.reference}',
          subtitle: '${appointment.serviceName} • ${appointment.employeeName}',
          details: '${appointment.customerPhone} • ${appointment.status.key} • ${appointment.startAt.toLocal()} • ${appointment.price} تومان • ${appointment.note}',
          route: route,
          searchable: [
            appointment.reference,
            appointment.customerName,
            appointment.customerPhone,
            appointment.serviceName,
            appointment.employeeName,
            appointment.status.key,
            appointment.note,
            appointment.price,
            appointment.startAt.toIso8601String(),
            appointment.id,
          ],
          date: appointment.startAt,
        );
      }
    }

    final canViewBusinessFinance = _database.hasPermission('finance.income.view');
    if (canViewBusinessFinance) {
      for (final payment in _database.appointmentPayments) {
        final appointment = _database.appointmentById(payment.appointmentId);
        final route = appointment != null && _database.canOpenRoute('/appointments/${appointment.id}')
            ? '/appointments/${appointment.id}'
            : '/reports';
        add(
          id: payment.id,
          type: GlobalSearchType.transaction,
          title: payment.type == BusinessPaymentType.receipt ? 'دریافت وجه' : 'بازپرداخت وجه',
          subtitle: '${payment.amount} تومان • ${payment.method.label}',
          details: '${payment.description} • کد نوبت: ${appointment?.reference ?? payment.appointmentId}',
          route: route,
          searchable: [payment.id, payment.appointmentId, payment.customerId, payment.description, payment.amount, payment.method.label, payment.type.name],
          date: payment.createdAt,
        );
      }
      for (final expense in _database.businessExpenses) {
        add(
          id: expense.id,
          type: GlobalSearchType.transaction,
          title: 'هزینه ${expense.category.label}',
          subtitle: '${expense.amount} تومان • ${expense.status.name}',
          details: '${expense.description} • سند: ${expense.sourceDocumentId} • ثبت‌کننده: ${expense.createdBy}',
          route: '/reports',
          searchable: [expense.id, expense.description, expense.category.label, expense.sourceDocumentId, expense.createdBy, expense.amount, expense.status.name],
          date: expense.createdAt,
        );
      }
    }

    for (final employee in _database.employees) {
      if (!_database.canViewEmployee(employee.id)) continue;
      final canViewProfile = _database.canOpenRoute('/employees/${employee.id}');
      if (canViewProfile && _database.hasPermission('employees.view_profile')) {
        for (final document in _database.documentsFor(employee.id)) {
          add(
            id: document.id,
            type: GlobalSearchType.document,
            title: document.title,
            subtitle: '${employee.fullName} • ${document.fileName}',
            details: '${document.type.name} • ${document.note} • ${document.expiresAt ?? ''}',
            route: '/employees/${employee.id}',
            searchable: [document.id, document.title, document.fileName, document.note, document.type.name, employee.fullName, document.expiresAt],
            date: document.addedAt,
          );
        }
      }

      if (_database.canViewEmployeeIncome(employee.id)) {
        final canViewCommission = _database.hasPermission('finance.commission.view', employeeId: employee.id);
        final canViewSalary = _database.hasPermission('finance.salary.view', employeeId: employee.id);
        final canViewSettlement = _database.hasPermission('finance.settlement.view', employeeId: employee.id);
        if (canViewCommission) {
          for (final entry in _database.employeeFinanceEntries.where((item) => item.employeeId == employee.id)) {
            final route = canViewSalary ? '/employees/${employee.id}/finance' : '/employees/${employee.id}/analytics';
            add(
              id: entry.id,
              type: GlobalSearchType.transaction,
              title: entry.type == FinanceEntryType.refund ? 'برگشت پورسانت' : 'پورسانت خدمت',
              subtitle: '${entry.commissionAmount} تومان • ${employee.fullName}',
              details: 'نوبت: ${entry.appointmentId} • خدمت: ${entry.serviceId} • سهم مجموعه: ${entry.companyShare} تومان',
              route: route,
              searchable: [entry.id, entry.appointmentId, entry.serviceId, entry.type.name, entry.commissionAmount, entry.companyShare, entry.receivedAmount, employee.fullName],
              date: entry.createdAt,
            );
          }
        }
        if (canViewSalary || canViewSettlement) {
          for (final entry in _database.employeeWalletTransactions.where((item) => item.employeeId == employee.id)) {
            final route = canViewSalary ? '/employees/${employee.id}/wallet' : '/employees/${employee.id}/analytics';
            add(
              id: entry.id,
              type: GlobalSearchType.transaction,
              title: entry.type.label,
              subtitle: '${entry.amount} تومان • ${employee.fullName}',
              details: '${entry.description} • ${entry.status.name}',
              route: route,
              searchable: [entry.id, entry.type.label, entry.description, entry.amount, entry.status.name, employee.fullName, entry.settlementId],
              date: entry.createdAt,
            );
          }
        }
      }
    }

    if (_database.canOpenRoute('/activity')) {
      for (final log in _database.activityLogs) {
        final route = '/activity';
        add(
          id: log.id,
          type: GlobalSearchType.activity,
          title: log.title,
          subtitle: '${log.entityName} • ${log.actor}',
          details: log.description,
          route: route,
          searchable: [log.id, log.title, log.description, log.entityName, log.entityId, log.actor, log.type.key],
          date: log.createdAt,
        );
      }
    }

    if (_remote != null) {
      try {
        final businessId = await _resolveBusinessId();
        if (businessId != null) {
          await _appendRemoteResults(query, type, results, add, businessId);
        }
      } catch (_) {
        // Remote search is optional; retain local/offline results when unavailable.
      }
    }

    results.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970));
    });
    return results.take(limit).toList(growable: false);
  }

  Future<String?> _resolveBusinessId() async {
    if (_businessId != null && _businessId!.trim().isNotEmpty) return _businessId;
    if (_businessResolutionAttempted) return _resolvedBusinessId;
    _businessResolutionAttempted = true;
    final businesses = await _remote!.fetchMyBusinesses();
    // Never guess between multiple tenant memberships. A selected business
    // must be supplied explicitly before searching across them.
    if (businesses.length != 1) return null;
    _resolvedBusinessId = businesses.single['business_id']?.toString();
    return _resolvedBusinessId;
  }

  Future<void> _appendRemoteResults(
    String query,
    GlobalSearchType? type,
    List<GlobalSearchResult> results,
    void Function({
      required String id,
      required GlobalSearchType type,
      required String title,
      required String subtitle,
      required String details,
      required String route,
      required Iterable<Object?> searchable,
      DateTime? date,
    }) add,
    String businessId,
  ) async {
    final remote = _remote!;
    Future<List<Map<String, dynamic>>> fetch(String entity) =>
        remote.fetchRecords(businessId: businessId, entityType: entity);

    if (_database.hasPermission('customers.view') && (type == null || type == GlobalSearchType.customer)) {
      for (final row in await fetch('customers')) {
        final id = row['id'] as String? ?? '';
        final canViewHistory = _database.hasPermission('customers.history');
        add(id: id, type: GlobalSearchType.customer,
          title: row['full_name'] as String? ?? '', subtitle: row['phone'] as String? ?? '',
          details: canViewHistory ? row['notes'] as String? ?? '' : '',
          route: canViewHistory ? '/customers/$id' : '/customers',
          searchable: canViewHistory ? row.values : [row['full_name'], row['phone']],
          date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
      }
    }
    if ((_database.hasPermission('employees.view_list') || _database.hasPermission('employees.view_profile')) &&
        (type == null || type == GlobalSearchType.employee)) {
      for (final row in await fetch('employees')) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty || !_database.canViewEmployee(id)) continue;
        final canViewProfile = _database.canOpenRoute('/employees/$id');
        add(id: id, type: GlobalSearchType.employee, title: row['full_name']?.toString() ?? '',
          subtitle: row['title']?.toString() ?? row['phone']?.toString() ?? '',
          details: canViewProfile ? row['email']?.toString() ?? '' : '',
          route: canViewProfile ? '/employees/$id' : '/employees',
          searchable: canViewProfile ? row.values : [row['full_name'], row['phone']]);
      }
    }
    if (_database.hasPermission('services.manage') && (type == null || type == GlobalSearchType.service || type == GlobalSearchType.category)) {
      for (final row in await fetch('services')) {
        final id = row['id']?.toString() ?? '';
        if (id.startsWith(_categoryPrefix)) {
          add(id: id, type: GlobalSearchType.category, title: row['name']?.toString() ?? '',
            subtitle: 'دسته‌بندی خدمات', details: '', route: '/services', searchable: row.values);
        } else {
          add(id: id, type: GlobalSearchType.service, title: row['title']?.toString() ?? '',
            subtitle: row['category']?.toString() ?? '', details: row['description']?.toString() ?? '',
            route: '/services/$id', searchable: row.values);
        }
      }
    }
    if ((_database.hasPermission('appointments.view_all') || _database.hasPermission('appointments.view_self')) &&
        (type == null || type == GlobalSearchType.appointment)) {
      for (final row in await fetch('appointments')) {
        final id = row['id']?.toString() ?? '';
        final employeeId = row['employee_id']?.toString() ?? '';
        if (id.isEmpty || (!_database.hasPermission('appointments.view_all') &&
            _database.currentAccessAccount.employeeId != employeeId)) continue;
        add(id: id, type: GlobalSearchType.appointment,
          title: '${row['customer_name'] ?? 'نوبت'} • ${row['reference'] ?? id}',
          subtitle: '${row['service_name'] ?? ''} • ${row['employee_name'] ?? ''}',
          details: '${row['customer_phone'] ?? ''} • ${row['status'] ?? ''}',
          route: '/appointments/$id', searchable: row.values,
          date: DateTime.tryParse(row['start_at']?.toString() ?? ''));
      }
    }
    if (type == null || type == GlobalSearchType.transaction) {
      if (_database.hasPermission('finance.commission.view')) {
        for (final row in await fetch('finance')) {
          final employeeId = row['employee_id']?.toString();
          if (employeeId == null || !_database.hasPermission('finance.commission.view', employeeId: employeeId)) continue;
          final route = _database.hasPermission('finance.salary.view', employeeId: employeeId)
              ? '/employees/$employeeId/finance'
              : '/employees/$employeeId/analytics';
          add(id: row['id']?.toString() ?? '', type: GlobalSearchType.transaction,
            title: row['description']?.toString() ?? row['type']?.toString() ?? 'تراکنش پورسانت',
            subtitle: '${row['commission_amount'] ?? ''} تومان',
            details: row['appointment_id']?.toString() ?? '', route: route,
            searchable: row.values, date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
        }
      }
      if (_database.hasPermission('finance.salary.view') || _database.hasPermission('finance.settlement.view')) {
        for (final row in await fetch('employee_wallets')) {
          final employeeId = row['employee_id']?.toString() ?? '';
          final canViewSalary = _database.hasPermission('finance.salary.view', employeeId: employeeId);
          final canViewSettlement = _database.hasPermission('finance.settlement.view', employeeId: employeeId);
          if (!_database.canViewEmployeeIncome(employeeId) || (!canViewSalary && !canViewSettlement)) continue;
          final route = canViewSalary
              ? '/employees/$employeeId/wallet'
              : '/employees/$employeeId/analytics';
          add(id: row['id']?.toString() ?? '', type: GlobalSearchType.transaction,
            title: row['description']?.toString() ?? row['type']?.toString() ?? 'تراکنش کیف پول',
            subtitle: '${row['amount'] ?? ''} تومان', details: row['status']?.toString() ?? '',
            route: route, searchable: row.values,
            date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
        }
      }
      if (_database.hasPermission('finance.income.view')) {
        for (final entity in ['appointment_payments', 'business_expenses']) {
          for (final row in await fetch(entity)) {
            final id = row['id']?.toString() ?? '';
            add(id: id, type: GlobalSearchType.transaction,
              title: row['description']?.toString() ?? row['category']?.toString() ?? 'تراکنش مالی',
              subtitle: '${row['amount'] ?? ''} تومان',
              details: row['appointment_id']?.toString() ?? row['source_document_id']?.toString() ?? '',
              route: '/reports', searchable: row.values,
              date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
          }
        }
      }
    }
    if (_database.hasPermission('settings.view') && (type == null || type == GlobalSearchType.activity)) {
      for (final row in await fetch('activity_logs')) {
        add(id: row['id']?.toString() ?? '', type: GlobalSearchType.activity,
          title: row['title']?.toString() ?? '', subtitle: row['entity_name']?.toString() ?? '',
          details: row['description']?.toString() ?? '', route: '/activity', searchable: row.values,
          date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
      }
    }
    if (_database.hasPermission('employees.view_profile') && (type == null || type == GlobalSearchType.document)) {
      for (final row in await fetch('employee_documents')) {
        final employeeId = row['employee_id']?.toString() ?? '';
        if (!_database.canViewEmployee(employeeId)) continue;
        add(id: row['id']?.toString() ?? '', type: GlobalSearchType.document,
          title: row['title']?.toString() ?? '', subtitle: row['file_name']?.toString() ?? '',
          details: row['note']?.toString() ?? '', route: '/employees/$employeeId',
          searchable: row.values);
      }
    }
  }

  Future<List<String>> recentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? const [];
  }

  Future<void> rememberSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_historyKey) ?? <String>[];
    recent.removeWhere((item) => normalize(item) == normalize(normalized));
    recent.insert(0, normalized);
    await prefs.setStringList(_historyKey, recent.take(_historyLimit).toList());
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
