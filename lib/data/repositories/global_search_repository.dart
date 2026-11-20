import 'package:shared_preferences/shared_preferences.dart';

import '../mock/app_database.dart';
import '../models/appointment.dart';
import '../models/business_finance.dart';
import '../models/customer.dart';
import '../models/employee.dart';
import '../models/employee_finance.dart';
import '../models/service.dart';
import 'appointment_repository.dart';
import 'customer_repository.dart';
import 'employee_repository.dart';
import 'service_repository.dart';
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
    this.isRemote = false,
    this.accountId = '',
    this.requiredPermission,
    this.employeeId,
    this.showDetailsPage = false,
  });

  final String id;
  final GlobalSearchType type;
  final String title;
  final String subtitle;
  final String details;
  final String route;
  final DateTime? date;
  final int score;
  final bool isRemote;
  final String accountId;
  final String? requiredPermission;
  final String? employeeId;
  final bool showDetailsPage;
}

/// جست‌وجوی مشترک؛ منبع پیش‌فرض Mock برای عملکرد کامل آفلاین است.
/// در صورت فراهم‌کردن remote و businessId، نتایج مجاز app_records نیز ادغام می‌شوند.
class GlobalSearchRepository {
  GlobalSearchRepository(
    this._database, {
    CustomerRepository? customerRepository,
    EmployeeRepository? employeeRepository,
    ServiceRepository? serviceRepository,
    AppointmentRepository? appointmentRepository,
    SupabaseRepository? remote,
    String? businessId,
  })  : _customers = customerRepository ?? MockCustomerRepository(_database),
        _employees = employeeRepository ?? MockEmployeeRepository(_database),
        _services = serviceRepository ?? MockServiceRepository(_database),
        _appointments = appointmentRepository ?? MockAppointmentRepository(_database),
        _remote = remote,
        _businessId = businessId;

  final AppDatabase _database;
  final CustomerRepository _customers;
  final EmployeeRepository _employees;
  final ServiceRepository _services;
  final AppointmentRepository _appointments;
  final SupabaseRepository? _remote;
  final String? _businessId;
  String? _resolvedBusinessId;
  bool _businessResolutionAttempted = false;
  bool _remoteOwner = false;
  final Set<String> _remotePermissions = {};

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

    // Pull the primary entities through the same repositories used by their
    // feature screens. Each repository applies its own access checks.
    List<Customer> visibleCustomers = const [];
    List<Employee> visibleEmployees = const [];
    List<Service> visibleServices = const [];
    List<Appointment> visibleAppointments = const [];
    final loads = <Future<void>>[];
    if ((filterType == null || filterType == GlobalSearchType.customer) && _database.hasPermission('customers.view')) {
      loads.add(_customers.fetchAll().then<void>((value) { visibleCustomers = value; }));
    }
    if ((filterType == null || filterType == GlobalSearchType.employee) &&
        (_database.hasPermission('employees.view_list') || _database.hasPermission('employees.view_profile'))) {
      loads.add(_employees.fetchEmployees().then<void>((value) { visibleEmployees = value; }));
    }
    if ((filterType == null || filterType == GlobalSearchType.service || filterType == GlobalSearchType.category) &&
        _database.hasPermission('services.manage') && _database.canOpenRoute('/services')) {
      loads.add(_services.fetchServices().then<void>((value) { visibleServices = value; }));
    }
    if ((filterType == null || filterType == GlobalSearchType.appointment) &&
        (_database.hasPermission('appointments.view_all') || _database.hasPermission('appointments.view_self'))) {
      loads.add(_appointments.fetchAll().then<void>((value) { visibleAppointments = value; }));
    }
    await Future.wait(loads);

    void add({
      required String id,
      required GlobalSearchType type,
      required String title,
      required String subtitle,
      required String details,
      required String route,
      required Iterable<Object?> searchable,
      DateTime? date,
      bool isRemote = false,
      String? requiredPermission,
      String? employeeId,
      bool? showDetailsPage,
    }) {
      if (filterType != null && type != filterType) return;
      if (!_matches(query, [...searchable, title, subtitle, details, id])) return;
      if (!_database.canOpenRoute(route)) return;
      if (results.any((item) => item.type == type && item.id == id)) return;
      results.add(GlobalSearchResult(
        id: id,
        type: type,
        title: title,
        subtitle: subtitle,
        details: details,
        route: route,
        date: date,
        score: _score(query, title),
        isRemote: isRemote,
        accountId: _database.currentAccessAccount.id,
        requiredPermission: requiredPermission,
        employeeId: employeeId,
        showDetailsPage: showDetailsPage ?? false,
      ));
    }


    if ((filterType == null || filterType == GlobalSearchType.customer) && _database.hasPermission('customers.view')) {
      for (final customer in visibleCustomers) {
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
          requiredPermission: canViewHistory ? 'customers.history' : 'customers.view',
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
    if ((filterType == null || filterType == GlobalSearchType.employee) && (canListEmployees || canViewOwnProfile)) {
      for (final employee in visibleEmployees) {
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
          requiredPermission: canViewProfile ? 'employees.view_profile' : 'employees.view_list',
          employeeId: employee.id,
          searchable: [
            employee.fullName,
            employee.phone,
            if (canViewProfile) ...[employee.email, employee.title, employee.specialties, employee.notes, employee.id],
          ],
        );
      }
    }

    if ((filterType == null || filterType == GlobalSearchType.service || filterType == GlobalSearchType.category) &&
        _database.hasPermission('services.manage') && _database.canOpenRoute('/services')) {
      for (final service in visibleServices) {
        add(
          id: service.id,
          type: GlobalSearchType.service,
          title: service.title,
          subtitle: service.category,
          details: '${service.price} تومان • ${service.durationMinutes} دقیقه • ${service.isActive ? 'فعال' : 'غیرفعال'} • ${service.description}',
          route: '/services/${service.id}',
          requiredPermission: 'services.manage',
          searchable: [service.title, service.description, service.category, service.price, service.durationMinutes, service.id],
        );
      }
      for (final category in await _services.fetchCategories()) {
        add(
          id: category,
          type: GlobalSearchType.category,
          title: category,
          subtitle: 'دسته‌بندی خدمات',
          details: '${_database.services.where((service) => service.category == category).length} خدمت',
          route: '/services',
          requiredPermission: 'services.manage',
          showDetailsPage: true,
          searchable: [category],
        );
      }
    }

    final canViewAllAppointments = _database.hasPermission('appointments.view_all');
    final canViewOwnAppointments = _database.hasPermission('appointments.view_self');
    if ((filterType == null || filterType == GlobalSearchType.appointment) && (canViewAllAppointments || canViewOwnAppointments)) {
      for (final appointment in visibleAppointments) {
        final route = '/appointments/${appointment.id}';
        if (!_database.canOpenRoute(route)) continue;
        add(
          id: appointment.id,
          type: GlobalSearchType.appointment,
          title: '${appointment.customerName} • ${appointment.reference}',
          subtitle: '${appointment.serviceName} • ${appointment.employeeName}',
          details: '${appointment.customerPhone} • ${appointment.status.key} • ${appointment.startAt.toLocal()} • ${appointment.price} تومان • ${appointment.note}',
          route: route,
          requiredPermission: canViewAllAppointments ? 'appointments.view_all' : 'appointments.view_self',
          employeeId: appointment.employeeId,
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
    if ((filterType == null || filterType == GlobalSearchType.transaction) && canViewBusinessFinance) {
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
          requiredPermission: 'finance.income.view',
          showDetailsPage: true,
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
          requiredPermission: 'finance.income.view',
          showDetailsPage: true,
          searchable: [expense.id, expense.description, expense.category.label, expense.sourceDocumentId, expense.createdBy, expense.amount, expense.status.name],
          date: expense.createdAt,
        );
      }
    }

    if (filterType == null || filterType == GlobalSearchType.document || filterType == GlobalSearchType.transaction) {
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
            requiredPermission: 'employees.view_profile',
            employeeId: employee.id,
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
              requiredPermission: 'finance.commission.view',
              employeeId: employee.id,
              showDetailsPage: true,
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
              requiredPermission: canViewSalary ? 'finance.salary.view' : 'finance.settlement.view',
              employeeId: employee.id,
              showDetailsPage: true,
              searchable: [entry.id, entry.type.label, entry.description, entry.amount, entry.status.name, employee.fullName, entry.settlementId],
              date: entry.createdAt,
            );
          }
        }
      }
    }

    if ((filterType == null || filterType == GlobalSearchType.activity) && _database.canOpenRoute('/activity')) {
      for (final log in _database.activityLogs) {
        final route = '/activity';
        add(
          id: log.id,
          type: GlobalSearchType.activity,
          title: log.title,
          subtitle: '${log.entityName} • ${log.actor}',
          details: log.description,
          route: route,
          requiredPermission: 'settings.view',
          showDetailsPage: true,
          searchable: [log.id, log.title, log.description, log.entityName, log.entityId, log.actor, log.type.key],
          date: log.createdAt,
        );
      }
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
    if (_businessId != null && _businessId.trim().isNotEmpty) return _businessId;
    if (_businessResolutionAttempted) return _resolvedBusinessId;
    _businessResolutionAttempted = true;
    final businesses = await _remote!.fetchMyBusinesses();
    // Never guess between multiple tenant memberships. A selected business
    // must be supplied explicitly before searching across them.
    if (businesses.length != 1) return null;
    final membership = businesses.single;
    _resolvedBusinessId = membership['business_id']?.toString();
    _remoteOwner = membership['role']?.toString() == 'owner';
    final rawPermissions = membership['permissions'];
    if (rawPermissions is Map) {
      for (final entry in rawPermissions.entries) {
        if (entry.value == true) _remotePermissions.add(entry.key.toString());
      }
    } else if (rawPermissions is List) {
      _remotePermissions.addAll(rawPermissions.map((value) => value.toString()));
    }
    return _resolvedBusinessId;
  }

  bool _hasRemotePermission(
    String permissionId, {
    String? employeeId,
    String? remotePermissionId,
  }) {
    if (!_database.hasPermission(permissionId, employeeId: employeeId)) return false;
    return _remoteOwner || _remotePermissions.contains(remotePermissionId ?? permissionId);
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
      required bool isRemote,
      String? requiredPermission,
      String? employeeId,
      bool? showDetailsPage,
    }) add,
    String businessId,
  ) async {
    final remote = _remote!;
    Future<List<Map<String, dynamic>>> fetch(String entity) =>
        remote.searchRecords(
          businessId: businessId,
          entityType: entity,
          query: query,
          limit: 60,
        );

    if (_hasRemotePermission('customers.view') && (type == null || type == GlobalSearchType.customer)) {
      for (final row in await fetch('customers')) {
        final id = row['id'] as String? ?? '';
        final canViewHistory = _hasRemotePermission('customers.history');
        add(id: id, type: GlobalSearchType.customer,
          title: row['full_name'] as String? ?? '', subtitle: row['phone'] as String? ?? '',
          details: canViewHistory ? row['notes'] as String? ?? '' : '',
          route: '/search/result',
          searchable: canViewHistory ? row.values : [row['full_name'], row['phone']],
          isRemote: true, requiredPermission: canViewHistory ? 'customers.history' : 'customers.view',
          date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
      }
    }
    if ((_hasRemotePermission('employees.view_list') || _hasRemotePermission('employees.view_profile')) &&
        (type == null || type == GlobalSearchType.employee)) {
      for (final row in await fetch('employees')) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty || !_database.canViewEmployee(id)) continue;
        final canViewProfile = _database.canOpenRoute('/employees/$id');
        add(id: id, type: GlobalSearchType.employee, title: row['full_name']?.toString() ?? '',
          subtitle: row['title']?.toString() ?? row['phone']?.toString() ?? '',
          details: canViewProfile ? row['email']?.toString() ?? '' : '',
          route: '/search/result',
          searchable: canViewProfile ? row.values : [row['full_name'], row['phone']],
          isRemote: true, requiredPermission: canViewProfile ? 'employees.view_profile' : 'employees.view_list', employeeId: id);
      }
    }
    if (_hasRemotePermission('services.manage', remotePermissionId: 'services.view') && (type == null || type == GlobalSearchType.service || type == GlobalSearchType.category)) {
      for (final row in await fetch('services')) {
        final id = row['id']?.toString() ?? '';
        if (id.startsWith(_categoryPrefix)) {
          add(id: id, type: GlobalSearchType.category, title: row['name']?.toString() ?? '',
            subtitle: 'دسته‌بندی خدمات', details: '', route: '/search/result', searchable: row.values, isRemote: true, requiredPermission: 'services.manage');
        } else {
          add(id: id, type: GlobalSearchType.service, title: row['title']?.toString() ?? '',
            subtitle: row['category']?.toString() ?? '', details: row['description']?.toString() ?? '',
            route: '/search/result', searchable: row.values, isRemote: true, requiredPermission: 'services.manage');
        }
      }
    }
    if ((_hasRemotePermission('appointments.view_all', remotePermissionId: 'appointments.view') ||
        _hasRemotePermission('appointments.view_self', remotePermissionId: 'appointments.view')) &&
        (type == null || type == GlobalSearchType.appointment)) {
      for (final row in await fetch('appointments')) {
        final id = row['id']?.toString() ?? '';
        final employeeId = row['employee_id']?.toString() ?? '';
        if (id.isEmpty || (!_hasRemotePermission('appointments.view_all', remotePermissionId: 'appointments.view') &&
            _database.currentAccessAccount.employeeId != employeeId)) continue;
        add(id: id, type: GlobalSearchType.appointment,
          title: '${row['customer_name'] ?? 'نوبت'} • ${row['reference'] ?? id}',
          subtitle: '${row['service_name'] ?? ''} • ${row['employee_name'] ?? ''}',
          details: '${row['customer_phone'] ?? ''} • ${row['status'] ?? ''}',
          route: '/search/result', searchable: row.values, isRemote: true,
          requiredPermission: _database.hasPermission('appointments.view_all') ? 'appointments.view_all' : 'appointments.view_self',
          employeeId: employeeId,
          date: DateTime.tryParse(row['start_at']?.toString() ?? ''));
      }
    }
    if (type == null || type == GlobalSearchType.transaction || type == GlobalSearchType.document) {
      final canReadFinance = _hasRemotePermission('finance.income.view', remotePermissionId: 'finance.view') ||
          _hasRemotePermission('finance.commission.view', remotePermissionId: 'finance.view') ||
          _hasRemotePermission('finance.salary.view', remotePermissionId: 'finance.view');
      if (canReadFinance) {
        for (final row in await fetch('finance')) {
          final employeeId = row['employee_id']?.toString();
          var canViewCommission = false;
          var canViewSalary = false;
          if (employeeId == null) {
            if (!_hasRemotePermission('finance.income.view', remotePermissionId: 'finance.view')) continue;
          } else {
            canViewCommission = _hasRemotePermission('finance.commission.view',
                employeeId: employeeId, remotePermissionId: 'finance.view');
            canViewSalary = _hasRemotePermission('finance.salary.view',
                employeeId: employeeId, remotePermissionId: 'finance.view');
            if (!canViewCommission && !canViewSalary) continue;
          }
          final isDocument = row['record_kind']?.toString() == 'document';
          if (isDocument && type != null && type != GlobalSearchType.document &&
              type != GlobalSearchType.transaction) continue;
          add(id: row['id']?.toString() ?? '',
            type: isDocument ? GlobalSearchType.document : GlobalSearchType.transaction,
            title: row['description']?.toString() ?? row['title']?.toString() ??
                row['type']?.toString() ?? 'تراکنش مالی',
            subtitle: row['amount'] == null
                ? (row['commission_amount']?.toString() ?? '')
                : '${row['amount']} تومان',
            details: row['appointment_id']?.toString() ??
                row['source_document_id']?.toString() ?? '',
            route: '/search/result', searchable: row.values, isRemote: true,
            requiredPermission: employeeId == null ? 'finance.income.view' : (canViewCommission ? 'finance.commission.view' : 'finance.salary.view'),
            employeeId: employeeId,
            date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
        }
      }
      final canReadWallet = _hasRemotePermission('finance.salary.view',
              remotePermissionId: 'finance.employee_wallet.view') ||
          _hasRemotePermission('finance.settlement.view',
              remotePermissionId: 'finance.employee_wallet.view');
      if (canReadWallet) {
        for (final row in await fetch('employee_wallets')) {
          final employeeId = row['employee_id']?.toString() ?? '';
          final canViewSalary = _hasRemotePermission('finance.salary.view',
              employeeId: employeeId, remotePermissionId: 'finance.employee_wallet.view');
          final canViewSettlement = _hasRemotePermission('finance.settlement.view',
              employeeId: employeeId, remotePermissionId: 'finance.employee_wallet.view');
          if (!_database.canViewEmployeeIncome(employeeId) ||
              (!canViewSalary && !canViewSettlement)) continue;
          add(id: row['id']?.toString() ?? '', type: GlobalSearchType.transaction,
            title: row['description']?.toString() ?? row['type']?.toString() ?? 'تراکنش کیف پول',
            subtitle: '${row['amount'] ?? ''} تومان',
            details: row['status']?.toString() ?? '', route: '/search/result',
            searchable: row.values, isRemote: true,
            requiredPermission: canViewSalary ? 'finance.salary.view' : 'finance.settlement.view', employeeId: employeeId,
            date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
        }
      }
    }
    if (_hasRemotePermission('settings.view', remotePermissionId: 'activity.view') && (type == null || type == GlobalSearchType.activity)) {
      for (final row in await fetch('activity_logs')) {
        add(id: row['id']?.toString() ?? '', type: GlobalSearchType.activity,
          title: row['title']?.toString() ?? '', subtitle: row['entity_name']?.toString() ?? '',
          details: row['description']?.toString() ?? '', route: '/search/result', searchable: row.values, isRemote: true,
          requiredPermission: 'settings.view',
          date: DateTime.tryParse(row['created_at']?.toString() ?? ''));
      }
    }
    // Some deployments embed personnel document metadata in the employee record.
    if (_hasRemotePermission('employees.view_profile', remotePermissionId: 'employees.view_list') &&
        (type == null || type == GlobalSearchType.document || type == GlobalSearchType.employee)) {
      for (final row in await fetch('employees')) {
        final employeeId = row['id']?.toString() ?? '';
        if (employeeId.isEmpty || !_database.canViewEmployee(employeeId)) continue;
        final documents = row['documents'];
        if (documents is! List) continue;
        for (final item in documents.whereType<Map>()) {
          final document = Map<String, dynamic>.from(item);
          add(id: document['id']?.toString() ?? '${employeeId}-document',
            type: GlobalSearchType.document,
            title: document['title']?.toString() ?? document['file_name']?.toString() ?? 'سند پرسنل',
            subtitle: row['full_name']?.toString() ?? '',
            details: document['note']?.toString() ?? '',
            route: '/search/result',
            searchable: [...document.values, row['full_name']], isRemote: true,
            requiredPermission: 'employees.view_profile', employeeId: employeeId,
            date: DateTime.tryParse(document['created_at']?.toString() ?? ''));
        }
      }
    }
  }

  Future<List<String>> recentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_historyKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> rememberSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = prefs.getStringList(_historyKey) ?? <String>[];
      recent.removeWhere((item) => normalize(item) == normalize(normalized));
      recent.insert(0, normalized);
      await prefs.setStringList(_historyKey, recent.take(_historyLimit).toList());
    } catch (_) {
      // Search itself must remain available even when browser storage is blocked.
    }
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (_) {}
  }
}


/// Re-check access immediately before opening or displaying a cached result.
bool canOpenGlobalSearchResult(AppDatabase database, GlobalSearchResult result) {
  if (result.accountId.isNotEmpty &&
      result.accountId != database.currentAccessAccount.id) {
    return false;
  }
  final employeeId = result.employeeId;
  if (employeeId != null && !database.canViewEmployee(employeeId)) return false;
  final permission = result.requiredPermission;
  if (permission != null &&
      !database.hasPermission(permission, employeeId: employeeId)) {
    return false;
  }
  if (result.type == GlobalSearchType.appointment &&
      result.isRemote &&
      !database.hasPermission('appointments.view_all') &&
      database.currentAccessAccount.employeeId != employeeId) {
    return false;
  }
  return (result.isRemote || result.showDetailsPage)
      ? database.canOpenRoute('/search/result')
      : database.canOpenRoute(result.route);
}
