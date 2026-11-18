import '../../core/utils/jalali.dart';
import '../mock/app_database.dart';
import '../models/appointment.dart';
import '../models/dashboard_stats.dart';
import '../models/enums.dart';
import '../models/employee_finance.dart';
import '../models/employee_wallet.dart';
import '../models/report_analytics.dart';

/// بازه زمانی گزارش پیشخوان.
enum StatsPeriod {
  daily('روزانه'),
  weekly('هفتگی'),
  monthly('ماهانه');

  const StatsPeriod(this.label);
  final String label;
}

abstract class DashboardRepository {
  Future<DashboardStats> fetchStats({StatsPeriod period = StatsPeriod.weekly});

  Future<List<Appointment>> fetchUpcoming({int limit = 4});

  Future<List<RevenuePoint>> fetchRevenueSeries({int months = 6});

  Future<List<RevenuePoint>> fetchServiceRevenue({int limit = 5});

  Future<ReportAnalytics> fetchReportAnalytics({required ReportDateRange range});
}

class MockDashboardRepository implements DashboardRepository {
  MockDashboardRepository(this._db);

  final AppDatabase _db;

  @override
  Future<DashboardStats> fetchStats({StatsPeriod period = StatsPeriod.weekly}) async {
    await _db.delay(180);
    final all = _db.appointments;
    final today = JalaliDate.today();
    final now = DateTime.now();

    final weekStart = today.addDays(-today.weekday);
    final monthStart = JalaliDate(today.year, today.month, 1);
    final periodStart = switch (period) {
      StatsPeriod.daily => today,
      StatsPeriod.weekly => weekStart,
      StatsPeriod.monthly => monthStart,
    };
    final periodEnd = switch (period) {
      StatsPeriod.daily => today.addDays(1),
      StatsPeriod.weekly => weekStart.addDays(7),
      StatsPeriod.monthly => monthStart.addMonths(1),
    };
    final periodItems = all.where((a) =>
      !a.jalali.isBefore(periodStart) && a.jalali.isBefore(periodEnd)
    ).toList();

    final completed = periodItems.where((a) => a.status == AppointmentStatus.completed);
    final cancelled = periodItems.where((a) => a.status == AppointmentStatus.cancelled || a.status == AppointmentStatus.noShow);

    final totalRevenue = periodItems
        .where((a) => a.status == AppointmentStatus.completed)
        .fold<num>(0, (sum, a) => sum + a.price);

    final monthRevenue = all
        .where((a) => a.status == AppointmentStatus.completed && !a.jalali.isBefore(monthStart))
        .fold<num>(0, (sum, a) => sum + a.price);

    final activeEmployees = _db.employees.where((e) => e.isActive).length;
    final slotsPerDay = activeEmployees == 0 ? 1 : activeEmployees * 4;

    // نمودار عملکرد بر اساس بازه انتخاب‌شده؛ میله‌ها حجم نوبت و خط درآمد را نشان می‌دهند.
    final performanceDates = switch (period) {
      StatsPeriod.daily => <JalaliDate>[today],
      StatsPeriod.weekly => List.generate(7, (i) => weekStart.addDays(i)),
      StatsPeriod.monthly => List.generate(today.day, (i) => monthStart.addDays(i)),
    };
    final performance = <WeekdayPerformance>[];
    for (final date in performanceDates) {
      final dayItems = all.where((a) => a.jalali.sameDay(date) && a.status != AppointmentStatus.cancelled).toList();
      final completedDayItems = dayItems.where((a) => a.status == AppointmentStatus.completed);
      final percent = ((dayItems.length / slotsPerDay) * 100).clamp(0, 100).round();
      performance.add(WeekdayPerformance(
        label: period == StatsPeriod.daily ? 'امروز' : period == StatsPeriod.weekly ? date.weekdayName : date.day.toString(),
        percent: percent,
        count: dayItems.length,
        revenue: completedDayItems.fold<num>(0, (sum, a) => sum + a.price),
        dateIso: date.iso,
      ));
    }
    if (performance.isNotEmpty) {
      final maxCount = performance.map((p) => p.count).reduce((a, b) => a > b ? a : b);
      final maxIndex = performance.indexWhere((p) => p.count == maxCount);
      final peak = performance[maxIndex];
      performance[maxIndex] = WeekdayPerformance(
        label: peak.label, percent: peak.percent, count: peak.count,
        revenue: peak.revenue, dateIso: peak.dateIso, isPeak: true,
      );
    }

    final statusBreakdown = <String, int>{
      for (final status in AppointmentStatus.values) status.label: periodItems.where((a) => a.status == status).length,
    };

    return DashboardStats(
      totalAppointments: periodItems.length,
      todayAppointments: all.where((a) => a.isToday && a.status != AppointmentStatus.cancelled).length,
      upcomingAppointments: all.where((a) => a.status.isActive && a.startAt.isAfter(now)).length,
      completedAppointments: completed.length,
      cancelledAppointments: cancelled.length,
      totalRevenue: totalRevenue,
      monthRevenue: monthRevenue,
      totalCustomers: _db.customers.length,
      activeEmployees: activeEmployees,
      weeklyTrend: performance,
      weekdayPerformance: performance,
      statusBreakdown: statusBreakdown,
    );
  }

  @override
  Future<List<Appointment>> fetchUpcoming({int limit = 4}) async {
    await _db.delay(120);
    final now = DateTime.now();
    final list = _db.appointments
        .where((a) => a.status.isActive && a.startAt.isAfter(now.subtract(const Duration(hours: 1))))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return list.take(limit).toList();
  }

  @override
  Future<List<RevenuePoint>> fetchRevenueSeries({int months = 6}) async {
    await _db.delay(140);
    final today = JalaliDate.today();
    final result = <RevenuePoint>[];
    for (var i = months - 1; i >= 0; i--) {
      final monthDate = JalaliDate(today.year, today.month, 1).addMonths(-i);
      final nextMonth = monthDate.addMonths(1);
      final items = _db.appointments.where((a) {
        final j = a.jalali;
        return !j.isBefore(monthDate) && j.isBefore(nextMonth);
      }).toList();
      final revenue = items
          .where((a) => a.status == AppointmentStatus.completed)
          .fold<num>(0, (sum, a) => sum + a.price);
      result.add(
        RevenuePoint(
          label: monthDate.monthName,
          value: revenue,
          secondary: items.length,
        ),
      );
    }

    return result;
  }

  @override
  Future<List<RevenuePoint>> fetchServiceRevenue({int limit = 5}) async {
    await _db.delay(120);
    final totals = <String, num>{};
    for (final a in _db.appointments.where((a) => a.status == AppointmentStatus.completed)) {
      totals[a.serviceName] = (totals[a.serviceName] ?? 0) + a.price;
    }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) RevenuePoint(label: e.key, value: e.value)];
  }
  @override
  Future<ReportAnalytics> fetchReportAnalytics({required ReportDateRange range}) async {
    await _db.delay(120);
    _db.requirePermission('finance.income.view');
    final canViewAll = _db.hasPermission('appointments.view_all');
    final canViewSelf = _db.hasPermission('appointments.view_self');
    if (!canViewAll && !canViewSelf) _db.requirePermission('appointments.view_all');
    final employeeId = _db.currentAccessAccount.employeeId;
    final appointments = _db.appointments.where((item) =>
      (canViewAll || (canViewSelf && employeeId != null && item.employeeId == employeeId)) &&
      range.contains(item.startAt)).toList();
    final completed = appointments.where((item) => item.status == AppointmentStatus.completed).toList();
    final revenue = completed.fold<num>(0, (sum, item) => sum + item.price);
    final statusCounts = <String, int>{
      for (final status in AppointmentStatus.values)
        status.label: appointments.where((item) => item.status == status).length,
    };
    final customers = appointments.map((item) => item.customerId).where((id) => id.isNotEmpty).toSet();

    final canViewCommission = _db.hasPermission('finance.commission.view');
    final canViewSalary = _db.hasPermission('finance.salary.view');
    final financeEntries = canViewCommission
        ? _db.employeeFinanceEntries.where((entry) =>
            range.contains(entry.createdAt) &&
            (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund) &&
            (canViewAll || employeeId == entry.employeeId)).toList()
        : <EmployeeFinanceEntry>[];
    final commissionByEmployee = <String, int>{};
    var commissionCost = 0;
    for (final entry in financeEntries) {
      final amount = entry.type == FinanceEntryType.refund ? -entry.commissionAmount.abs() : entry.commissionAmount;
      commissionCost += amount;
      commissionByEmployee[entry.employeeId] = (commissionByEmployee[entry.employeeId] ?? 0) + amount;
    }

    final walletEntries = canViewSalary
        ? _db.employeeWalletTransactions.where((entry) =>
            range.contains(entry.createdAt) &&
            entry.status == EmployeeWalletTransactionStatus.posted &&
            (canViewAll || employeeId == entry.employeeId)).toList()
        : <EmployeeWalletTransaction>[];
    int walletCostFor(Iterable<EmployeeWalletTransaction> entries) {
      var total = 0;
      for (final entry in entries) {
        switch (entry.type) {
          case EmployeeWalletTransactionType.fixedSalary:
          case EmployeeWalletTransactionType.bonus:
          case EmployeeWalletTransactionType.penalty:
          case EmployeeWalletTransactionType.deduction:
          case EmployeeWalletTransactionType.adjustment:
            total += entry.amount;
            break;
          case EmployeeWalletTransactionType.commission:
          case EmployeeWalletTransactionType.salaryPayment:
          case EmployeeWalletTransactionType.advance:
          case EmployeeWalletTransactionType.refund:
            break;
        }
      }
      return total;
    }
    final payrollCost = walletCostFor(walletEntries);
    final cost = commissionCost + payrollCost;

    final employeeRevenue = <String, num>{};
    final employeeNames = <String, String>{};
    for (final appointment in completed) {
      employeeRevenue[appointment.employeeId] = (employeeRevenue[appointment.employeeId] ?? 0) + appointment.price;
      employeeNames[appointment.employeeId] = appointment.employeeName;
    }
    final employeeIds = <String>{...employeeRevenue.keys, ...commissionByEmployee.keys};
    final employeeMetrics = employeeIds.map((id) {
      final storedName = _db.employees.where((item) => item.id == id).map((item) => item.fullName).toList();
      return ReportEmployeeMetric(
        employeeId: id,
        name: employeeNames[id] ?? (storedName.isEmpty ? 'پرسنل' : storedName.first),
        revenue: employeeRevenue[id] ?? 0,
        commission: commissionByEmployee[id] ?? 0,
      );
    }).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

    final serviceTotals = <String, num>{};
    final serviceCounts = <String, int>{};
    for (final appointment in completed) {
      if (appointment.serviceIds.isEmpty) {
        final name = appointment.serviceName.trim().isEmpty ? 'خدمت ثبت‌نشده' : appointment.serviceName;
        serviceTotals[name] = (serviceTotals[name] ?? 0) + appointment.price;
        serviceCounts[name] = (serviceCounts[name] ?? 0) + 1;
        continue;
      }

      final parts = <({String name, num weight})>[];
      for (final serviceId in appointment.serviceIds) {
        final snapshots = appointment.serviceSnapshots.where((item) => item['service_id'] == serviceId).toList();
        final snapshot = snapshots.isEmpty ? null : snapshots.first;
        final savedPrice = snapshot?['price'] as num?;
        final serviceMatches = _db.services.where((item) => item.id == serviceId).toList();
        final serviceName = serviceMatches.isEmpty
            ? (snapshot?['service_name'] as String? ?? serviceId)
            : serviceMatches.first.name;
        parts.add((name: serviceName, weight: savedPrice ?? 1));
      }
      final weightTotal = parts.fold<num>(0, (sum, item) => sum + item.weight);
      var allocated = 0.0;
      for (var index = 0; index < parts.length; index++) {
        final part = parts[index];
        final amount = index == parts.length - 1
            ? appointment.price - allocated
            : (weightTotal == 0 ? appointment.price / parts.length : appointment.price * part.weight / weightTotal);
        allocated += amount;
        serviceTotals[part.name] = (serviceTotals[part.name] ?? 0) + amount;
        serviceCounts[part.name] = (serviceCounts[part.name] ?? 0) + 1;
      }
    }
    final serviceMetrics = serviceTotals.entries.map((entry) => ReportServiceMetric(
      name: entry.key, revenue: entry.value, count: serviceCounts[entry.key] ?? 0,
    )).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

    int costBetween(DateTime from, DateTime to) {
      final commission = financeEntries.where((item) =>
        !item.createdAt.isBefore(from) && item.createdAt.isBefore(to)).fold<int>(0, (sum, item) =>
          sum + (item.type == FinanceEntryType.refund ? -item.commissionAmount.abs() : item.commissionAmount));
      final payroll = walletCostFor(walletEntries.where((item) =>
        !item.createdAt.isBefore(from) && item.createdAt.isBefore(to)));
      return commission + payroll;
    }

    final trend = <ReportTrendPoint>[];
    final days = range.endExclusive.difference(range.start).inDays;
    if (days <= 31) {
      var cursor = DateTime(range.start.year, range.start.month, range.start.day);
      while (cursor.isBefore(range.endExclusive)) {
        final next = cursor.add(const Duration(days: 1));
        final items = appointments.where((item) => !item.startAt.isBefore(cursor) && item.startAt.isBefore(next)).toList();
        trend.add(ReportTrendPoint(
          label: JalaliDate.fromDateTime(cursor).short,
          start: cursor,
          revenue: items.where((item) => item.status == AppointmentStatus.completed).fold<num>(0, (sum, item) => sum + item.price),
          cost: costBetween(cursor, next),
          appointments: items.length,
        ));
        cursor = next;
      }
    } else {
      var cursor = DateTime(range.start.year, range.start.month, 1);
      while (cursor.isBefore(range.endExclusive)) {
        final next = DateTime(cursor.year, cursor.month + 1, 1);
        final from = cursor.isBefore(range.start) ? range.start : cursor;
        final to = next.isAfter(range.endExclusive) ? range.endExclusive : next;
        final items = appointments.where((item) => !item.startAt.isBefore(from) && item.startAt.isBefore(to)).toList();
        trend.add(ReportTrendPoint(
          label: JalaliDate.fromDateTime(cursor).monthName,
          start: from,
          revenue: items.where((item) => item.status == AppointmentStatus.completed).fold<num>(0, (sum, item) => sum + item.price),
          cost: costBetween(from, to),
          appointments: items.length,
        ));
        cursor = next;
      }
    }

    final recentAppointments = appointments.toList()
      ..sort((a, b) => (b.createdAt ?? b.startAt).compareTo(a.createdAt ?? a.startAt));
    final recentTransactions = walletEntries.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ReportAnalytics(
      range: range,
      revenue: revenue,
      cost: cost,
      commissionCost: commissionCost,
      payrollCost: payrollCost,
      totalAppointments: appointments.length,
      completedAppointments: completed.length,
      cancelledAppointments: statusCounts[AppointmentStatus.cancelled.label] ?? 0,
      noShowAppointments: statusCounts[AppointmentStatus.noShow.label] ?? 0,
      uniqueCustomers: customers.length,
      statusCounts: statusCounts,
      trend: trend,
      employees: employeeMetrics,
      services: serviceMetrics.take(5).toList(),
      recentAppointments: recentAppointments.take(5).toList(),
      recentTransactions: recentTransactions.take(5).toList(),
      costNote: 'هزینه شامل پورسانت و اقلام حقوقی ثبت‌شده و قابل مشاهده است؛ هزینه‌های عمومی کسب‌وکار هنوز در مدل مالی ثبت نمی‌شوند. پرداخت حقوق و مساعده دوباره‌شماری نشده‌اند.',
    );
  }

}
