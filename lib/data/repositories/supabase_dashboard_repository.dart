import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/jalali.dart';
import '../models/appointment.dart';
import '../models/dashboard_stats.dart';
import '../models/enums.dart';
import '../models/report_analytics.dart';
import '../models/business_finance.dart';
import 'appointment_repository.dart';
import 'dashboard_repository.dart';

/// Dashboard and report aggregates computed exclusively from relational
/// appointments, payment and expense rows. Unsupported financial metrics stay
/// empty rather than being estimated or fabricated.
class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseDashboardRepository({
    required SupabaseClient client,
    required String? Function() businessId,
    required AppointmentRepository appointments,
  })  : _client = client,
        _businessId = businessId,
        _appointments = appointments;

  final SupabaseClient _client;
  final String? Function() _businessId;
  final AppointmentRepository _appointments;

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

  Future<List<Map<String, dynamic>>> _payments({DateTime? from, DateTime? to}) async {
    final tenant = _tenant();
    var request = _client.from('appointment_payments')
        .select('id,appointment_id,customer_id,amount_toman,payment_type,method,description,reverses_payment_id,idempotency_key,created_by,created_at')
        .eq('business_id', tenant);
    if (from != null) request = request.gte('created_at', from.toUtc().toIso8601String());
    if (to != null) request = request.lt('created_at', to.toUtc().toIso8601String());
    final rows = await request;
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  num _netPayments(Iterable<Map<String, dynamic>> rows) => rows.fold<num>(0, (sum, row) {
    final amount = row['amount_toman'] as num? ?? 0;
    return sum + (row['payment_type'] == 'refund' ? -amount : amount);
  });

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<int> _count(String table, {String? column, bool? value}) async {
    final tenant = _tenant();
    var request = _client.from(table).select('id').eq('business_id', tenant);
    if (column != null && value != null) request = request.eq(column, value);
    return (await request).length;
  }

  @override
  Future<DashboardStats> fetchStats({StatsPeriod period = StatsPeriod.weekly}) async {
    final all = await _appointments.fetchAll();
    final today = JalaliDate.today();
    final weekStart = today.addDays(-today.weekday);
    final monthStart = JalaliDate(today.year, today.month, 1);
    final start = switch (period) {
      StatsPeriod.daily => today,
      StatsPeriod.weekly => weekStart,
      StatsPeriod.monthly => monthStart,
    };
    final end = switch (period) {
      StatsPeriod.daily => today.addDays(1),
      StatsPeriod.weekly => weekStart.addDays(7),
      StatsPeriod.monthly => monthStart.addMonths(1),
    };
    final from = start.toDateTime();
    final to = end.toDateTime();
    final periodItems = all.where((item) =>
      !item.startAt.isBefore(from) && item.startAt.isBefore(to)).toList();
    final payments = await _payments(from: from, to: to);
    final monthPayments = await _payments(
      from: monthStart.toDateTime(),
      to: monthStart.addMonths(1).toDateTime(),
    );
    final todayItems = all.where((item) => item.jalali.sameDay(today)).toList();
    final weeklyPayments = await _payments(
      from: weekStart.toDateTime(),
      to: weekStart.addDays(7).toDateTime(),
    );
    final tenant = _tenant();
    final scheduleRows = await _client.from('employee_working_hours')
        .select('weekday,starts_at,ends_at')
        .eq('business_id', tenant)
        .eq('is_active', true);
    int toMinutes(dynamic value) {
      final parts = (value as String).split(':');
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }
    final weekly = <WeekdayPerformance>[];
    for (var i = 0; i < 7; i++) {
      final date = weekStart.addDays(i);
      final dayItems = all.where((item) => item.jalali.sameDay(date)).toList();
      final dayPayments = weeklyPayments.where((row) =>
        JalaliDate.fromDateTime(DateTime.parse(row['created_at'] as String).toLocal()).sameDay(date));
      final pgWeekday = (date.weekday + 6) % 7;
      final shifts = scheduleRows.where((row) => (row['weekday'] as num).toInt() == pgWeekday);
      final capacityMinutes = shifts.fold<int>(0, (sum, row) =>
        sum + toMinutes(row['ends_at']) - toMinutes(row['starts_at']));
      final bookedMinutes = dayItems
          .where((item) => item.status != AppointmentStatus.cancelled)
          .fold<int>(0, (sum, item) => sum + item.durationMinutes);
      final utilization = capacityMinutes == 0
          ? 0
          : (bookedMinutes * 100 / capacityMinutes).round().clamp(0, 100).toInt();
      weekly.add(WeekdayPerformance(
        label: date.short,
        percent: utilization,
        count: dayItems.length,
        revenue: _netPayments(dayPayments),
        dateIso: date.iso,
      ));
    }
    final statuses = <String, int>{
      for (final status in AppointmentStatus.values)
        status.label: periodItems.where((item) => item.status == status).length,
    };
    return DashboardStats(
      totalAppointments: periodItems.length,
      todayAppointments: todayItems.length,
      upcomingAppointments: all.where((item) => item.isUpcoming).length,
      completedAppointments: periodItems.where((item) => item.status == AppointmentStatus.completed).length,
      cancelledAppointments: periodItems.where((item) => item.status == AppointmentStatus.cancelled || item.status == AppointmentStatus.noShow).length,
      totalRevenue: _netPayments(payments),
      monthRevenue: _netPayments(monthPayments),
      totalCustomers: await _count('customers', column: 'is_active', value: true),
      activeEmployees: await _count('employees', column: 'is_active', value: true),
      weeklyTrend: weekly,
      weekdayPerformance: weekly,
      statusBreakdown: statuses,
    );
  }

  @override
  Future<List<Appointment>> fetchUpcoming({int limit = 4}) async {
    final items = await _appointments.fetchAll();
    final upcoming = items.where((item) => item.isUpcoming).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return upcoming.take(limit).toList(growable: false);
  }

  @override
  Future<List<RevenuePoint>> fetchRevenueSeries({int months = 6}) async {
    final now = JalaliDate.today();
    final first = JalaliDate(now.year, now.month, 1).addMonths(-(months - 1));
    final rows = await _payments(from: first.toDateTime(), to: now.addDays(1).toDateTime());
    final grouped = <String, num>{};
    for (final row in rows) {
      final at = DateTime.parse(row['created_at'] as String).toLocal();
      final jalali = JalaliDate.fromDateTime(at);
      final key = '${jalali.year}/${jalali.month}';
      final amount = row['amount_toman'] as num? ?? 0;
      grouped.update(key, (value) => value + (row['payment_type'] == 'refund' ? -amount : amount), ifAbsent: () => row['payment_type'] == 'refund' ? -amount : amount);
    }
    return grouped.entries.map((entry) => RevenuePoint(label: entry.key, value: entry.value)).toList(growable: false);
  }

  @override
  Future<List<RevenuePoint>> fetchServiceRevenue({int limit = 5}) async {
    final items = await _appointments.fetchAll();
    final totals = <String, num>{};
    final counts = <String, int>{};
    for (final appointment in items.where((item) => item.status == AppointmentStatus.completed)) {
      for (final snapshot in appointment.serviceSnapshots) {
        final name = snapshot['title'] as String? ?? '';
        if (name.isEmpty) continue;
        totals.update(name, (value) => value + ((snapshot['price'] as num?) ?? 0), ifAbsent: () => (snapshot['price'] as num?) ?? 0);
        counts.update(name, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((entry) => RevenuePoint(
      label: entry.key,
      value: entry.value,
      secondary: counts[entry.key] ?? 0,
    )).toList(growable: false);
  }

  @override
  Future<ReportAnalytics> fetchReportAnalytics({
    required ReportDateRange range,
    ReportAnalyticsFilter filter = const ReportAnalyticsFilter(),
  }) async {
    final appointments = (await _appointments.fetchAll()).where((item) =>
      range.contains(item.startAt) && filter.matches(item)).toList();
    final payments = await _payments(from: range.start, to: range.endExclusive);
    final tenant = _tenant();
    final expenseRows = await _client.from('business_expenses')
        .select('id,amount_toman,category,description,source_document_id,status,created_by,created_at,expense_date,payment_method,idempotency_key,related_appointment_id,related_customer_id,reversed_at,reversed_by,reversal_reason')
        .eq('business_id', tenant)
        .eq('status', 'posted')
        .gte('expense_date', _dateOnly(range.start))
        .lt('expense_date', _dateOnly(range.endExclusive));
    final expenses = expenseRows.map((row) => Map<String, dynamic>.from(row)).toList();
    final expenseTotal = expenses.fold<num>(0, (sum, row) => sum + ((row['amount_toman'] as num?) ?? 0));
    final financeRows = await _client.from('employee_finance_entries')
        .select('entry_type,commission_amount_toman,company_share_toman,created_at')
        .eq('business_id', tenant)
        .gte('created_at', range.start.toUtc().toIso8601String())
        .lt('created_at', range.endExclusive.toUtc().toIso8601String());
    num commissionCost = 0;
    num companyShare = 0;
    for (final row in financeRows) {
      final amount = (row['commission_amount_toman'] as num?) ?? 0;
      final share = (row['company_share_toman'] as num?) ?? 0;
      commissionCost += row['entry_type'] == 'refund' ? -amount : amount;
      companyShare += row['entry_type'] == 'refund' ? -share : share;
    }
    final walletRows = await _client.from('employee_wallet_transactions')
        .select('transaction_type,amount_toman,direction,status,created_at')
        .eq('business_id', tenant)
        .eq('transaction_type', 'salary')
        .eq('status', 'posted')
        .gte('created_at', range.start.toUtc().toIso8601String())
        .lt('created_at', range.endExclusive.toUtc().toIso8601String());
    final payrollCost = walletRows.fold<num>(0, (sum, row) =>
      sum + ((row['amount_toman'] as num?) ?? 0) * (row['direction'] == 'debit' ? -1 : 1));
    final completedForRange = appointments.where((item) => item.status == AppointmentStatus.completed).toList();
    final gross = completedForRange.fold<num>(0, (sum, item) =>
      sum + (item.serviceSnapshots.isEmpty
        ? item.price
        : item.serviceSnapshots.fold<num>(0, (serviceSum, snapshot) =>
            serviceSum + ((snapshot['list_price'] as num?) ?? (snapshot['price'] as num?) ?? 0))));
    final discountTotal = completedForRange.fold<num>(0, (sum, item) =>
      sum + item.serviceSnapshots.fold<num>(0, (serviceSum, snapshot) =>
        serviceSum + ((snapshot['discount'] as num?) ?? 0)));
    final allPaymentRows = completedForRange.isEmpty
      ? <Map<String, dynamic>>[]
      : (await _client.from('appointment_payments')
          .select('appointment_id,amount_toman,payment_type')
          .eq('business_id', tenant)
          .inFilter('appointment_id', completedForRange.map((item) => item.id).toList()))
          .map((row) => Map<String, dynamic>.from(row)).toList();
    final paidByAppointment = <String, num>{};
    for (final row in allPaymentRows) {
      final amount = (row['amount_toman'] as num?) ?? 0;
      paidByAppointment.update(
        row['appointment_id'] as String,
        (value) => value + (row['payment_type'] == 'refund' ? -amount : amount),
        ifAbsent: () => row['payment_type'] == 'refund' ? -amount : amount,
      );
    }
    final receivables = completedForRange.fold<num>(0, (sum, item) =>
      sum + (item.price - (paidByAppointment[item.id] ?? 0)).clamp(0, double.infinity));
    final paymentModels = payments.map((row) =>
      AppointmentPayment.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
    final expenseModels = expenses.map((row) =>
      BusinessExpense.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
    final totalCost = expenseTotal + commissionCost + payrollCost;
    final statusCounts = <String, int>{
      for (final status in AppointmentStatus.values)
        status.label: appointments.where((item) => item.status == status).length,
    };
    final paymentsByMethod = <String, num>{};
    for (final row in payments) {
      final method = switch (row['method'] as String? ?? 'other') {
        'cash' => 'نقدی',
        'pos' => 'کارت‌خوان',
        'bank_transfer' => 'انتقال بانکی',
        'wallet' => 'کیف پول',
        _ => 'سایر',
      };
      final amount = row['amount_toman'] as num? ?? 0;
      paymentsByMethod.update(method, (value) => value + (row['payment_type'] == 'refund' ? -amount : amount), ifAbsent: () => row['payment_type'] == 'refund' ? -amount : amount);
    }
    final expensesByCategory = <String, num>{};
    for (final row in expenses) {
      final category = row['category'] as String? ?? '';
      expensesByCategory.update(category, (value) => value + ((row['amount_toman'] as num?) ?? 0), ifAbsent: () => (row['amount_toman'] as num?) ?? 0);
    }
    final uniqueCustomers = appointments.map((item) => item.customerId).toSet().length;
    final recent = [...appointments]..sort((a, b) => b.startAt.compareTo(a.startAt));
    return ReportAnalytics(
      range: range,
      revenue: _netPayments(payments),
      grossRevenue: gross,
      discountTotal: discountTotal,
      collectedRevenue: _netPayments(payments),
      receivables: receivables,
      cost: totalCost,
      operatingExpense: expenseTotal,
      commissionCost: commissionCost,
      payrollCost: payrollCost,
      totalAppointments: appointments.length,
      completedAppointments: appointments.where((item) => item.status == AppointmentStatus.completed).length,
      cancelledAppointments: appointments.where((item) => item.status == AppointmentStatus.cancelled).length,
      noShowAppointments: appointments.where((item) => item.status == AppointmentStatus.noShow).length,
      uniqueCustomers: uniqueCustomers,
      statusCounts: statusCounts,
      trend: const [],
      employees: const [],
      services: const [],
      recentAppointments: recent.take(10).toList(growable: false),
      recentTransactions: const [],
      costNote: 'هزینه عملیاتی، پورسانت و حقوق فقط از اسناد مالی واقعی ثبت‌شده محاسبه شده‌اند.',
      paymentsByMethod: paymentsByMethod,
      expensesByCategory: expensesByCategory,
      paymentTransactions: paymentModels,
      businessExpenses: expenseModels,
      operationalAppointments: appointments,
      filter: filter,
      companyShare: companyShare,
      grossProfit: gross - totalCost,
      profitMarginPercent: _netPayments(payments) <= 0 ? 0 : ((_netPayments(payments) - totalCost) / _netPayments(payments)) * 100,
    );
  }
}
