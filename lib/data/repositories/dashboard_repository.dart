import '../../core/utils/jalali.dart';
import '../mock/app_database.dart';
import '../models/appointment.dart';
import '../models/customer.dart';
import '../models/dashboard_stats.dart';
import '../models/enums.dart';
import '../models/employee_finance.dart';
import '../models/employee_wallet.dart';
import '../models/report_analytics.dart';
import '../models/business_finance.dart';
import '../models/employee_payroll.dart';

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

  Future<ReportAnalytics> fetchReportAnalytics({required ReportDateRange range, ReportAnalyticsFilter filter = const ReportAnalyticsFilter()});
}

class MockDashboardRepository implements DashboardRepository {
  MockDashboardRepository(this._db);

  final AppDatabase _db;

  bool get _canViewAllFinancial =>
      _db.hasPermission('finance.income.view') &&
      (_db.hasPermission('employees.view_list') || _db.hasPermission('appointments.view_all'));

  /// منبع مشترک درآمد برای داشبورد، نمودارها و مرکز گزارش‌ها.
  List<EmployeeFinanceEntry> _visibleRevenueEntries({DateTime? from, DateTime? to}) {
    final employeeId = _db.currentAccessAccount.employeeId;
    return _db.employeeFinanceEntries.where((entry) =>
      (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund) &&
      (from == null || !entry.createdAt.isBefore(from)) &&
      (to == null || entry.createdAt.isBefore(to)) &&
      (_canViewAllFinancial || employeeId == entry.employeeId) &&
      _db.hasPermission('finance.income.view', employeeId: entry.employeeId)).toList();
  }

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

    final totalRevenue = _visibleRevenueEntries(
      from: periodStart.toDateTime(), to: periodEnd.toDateTime(),
    ).fold<int>(0, (sum, entry) => sum + entry.receivedAmount);

    final monthRevenue = _visibleRevenueEntries(
      from: monthStart.toDateTime(), to: monthStart.addMonths(1).toDateTime(),
    ).fold<int>(0, (sum, entry) => sum + entry.receivedAmount);

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
      final dayRevenue = _visibleRevenueEntries(
        from: date.toDateTime(), to: date.addDays(1).toDateTime(),
      ).fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      final percent = ((dayItems.length / slotsPerDay) * 100).clamp(0, 100).round();
      performance.add(WeekdayPerformance(
        label: period == StatsPeriod.daily ? 'امروز' : period == StatsPeriod.weekly ? date.weekdayName : date.day.toString(),
        percent: percent,
        count: dayItems.length,
        revenue: dayRevenue,
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
      final revenue = _visibleRevenueEntries(
        from: monthDate.toDateTime(), to: nextMonth.toDateTime(),
      ).fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
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
    for (final entry in _visibleRevenueEntries()) {
      final service = _db.services.where((item) => item.id == entry.serviceId).toList();
      final appointment = _db.appointmentById(entry.appointmentId);
      final label = service.isNotEmpty ? service.first.title : (appointment?.serviceName ?? 'خدمت');
      totals[label] = (totals[label] ?? 0) + entry.receivedAmount;
    }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) RevenuePoint(label: e.key, value: e.value)];
  }
  @override
  Future<ReportAnalytics> fetchReportAnalytics({required ReportDateRange range, ReportAnalyticsFilter filter = const ReportAnalyticsFilter()}) async {
    await _db.delay(120);
    _db.requirePermission('finance.income.view');
    final canViewAll = _db.hasPermission('appointments.view_all');
    final canViewSelf = _db.hasPermission('appointments.view_self');
    final employeeId = _db.currentAccessAccount.employeeId;
    final canViewAppointments = canViewAll || (canViewSelf && employeeId != null);
    // Finance roles such as accountant may see financial ledgers without
    // receiving permission to browse appointment/customer records.
    final canViewAllFinancial = _canViewAllFinancial;
    final canSeeAppointment = (Appointment item) =>
        canViewAll || (canViewSelf && employeeId != null && item.employeeId == employeeId);
    final appointments = canViewAppointments
      ? _db.appointments.where((item) => canSeeAppointment(item) && range.contains(item.startAt)).toList()
      : <Appointment>[];
    Set<String> serviceCategoriesFor(Appointment item) {
      final categories = <String>{};
      for (final serviceId in item.serviceIds) {
        final snapshot = item.serviceSnapshots.where((value) => value['service_id'] == serviceId).toList();
        final snapshotCategory = snapshot.isEmpty ? null : snapshot.first['category'] as String?;
        if (snapshotCategory != null && snapshotCategory.trim().isNotEmpty) {
          categories.add(snapshotCategory);
          continue;
        }
        for (final service in _db.services.where((value) => value.id == serviceId)) {
          categories.add(service.category);
        }
      }
      return categories;
    }
    bool matchesReportAppointment(Appointment item, {DateTime? paymentFrom, DateTime? paymentTo}) {
      if (canViewAppointments) {
        if (!filter.matches(item, serviceCategories: serviceCategoriesFor(item))) return false;
      } else if (filter.employeeId != null && filter.employeeId != item.employeeId) {
        return false;
      }
      if (filter.paymentMethod == null) return true;
      final from = paymentFrom ?? range.start;
      final to = paymentTo ?? range.endExclusive;
      return _db.appointmentPayments.any((payment) =>
        payment.appointmentId == item.id &&
        payment.method.name == filter.paymentMethod &&
        !payment.createdAt.isBefore(from) &&
        payment.createdAt.isBefore(to));
    }
    final operationalAppointments = appointments.where(matchesReportAppointment).toList();
    final operationalCompleted = operationalAppointments.where((item) => item.status == AppointmentStatus.completed).toList();
    final completed = operationalCompleted;
    final operationalStatusCounts = <String, int>{
      for (final status in AppointmentStatus.values)
        status.label: operationalAppointments.where((item) => item.status == status).length,
    };
    final canViewCommission = _db.hasPermission('finance.commission.view');
    final canViewSalary = _db.hasPermission('finance.salary.view');
    final hasFullIncomeScope = _db.employees.every((item) =>
      _db.hasPermission('finance.income.view', employeeId: item.id));
    final hasFullCommissionScope = _db.employees.every((item) =>
      _db.hasPermission('finance.commission.view', employeeId: item.id));
    final hasFullSalaryScope = _db.employees.every((item) =>
      _db.hasPermission('finance.salary.view', employeeId: item.id));
    final revenueEntries = _visibleRevenueEntries(from: range.start, to: range.endExclusive)
      .where((entry) {
        final appointment = _db.appointmentById(entry.appointmentId);
        return appointment != null && matchesReportAppointment(appointment);
      }).toList();
    final revenueByAppointmentInRange = <String, int>{};
    for (final entry in revenueEntries) {
      revenueByAppointmentInRange[entry.appointmentId] =
          (revenueByAppointmentInRange[entry.appointmentId] ?? 0) + entry.receivedAmount;
    }
    final financeEntries = revenueEntries.where((entry) =>
      canViewCommission && _db.hasPermission('finance.commission.view', employeeId: entry.employeeId)).toList();
    final allVisibleFinanceEntries = _visibleRevenueEntries().where((entry) {
      final appointment = _db.appointmentById(entry.appointmentId);
      return appointment != null && matchesReportAppointment(appointment);
    }).toList();

    final commissionByEmployee = <String, int>{};
    var commissionCost = 0;
    var grossRevenue = 0;
    var revenue = 0;
    for (final entry in revenueEntries) {
      grossRevenue += entry.grossAmount;
      revenue += entry.receivedAmount;
    }
    for (final entry in financeEntries) {
      final signedCommission = entry.type == FinanceEntryType.refund
          ? -entry.commissionAmount.abs()
          : entry.commissionAmount;
      commissionCost += signedCommission;
      commissionByEmployee[entry.employeeId] = (commissionByEmployee[entry.employeeId] ?? 0) + signedCommission;
    }

    final walletEntries = _db.employeeWalletTransactions.where((entry) {
      if (!range.contains(entry.createdAt) || entry.status != EmployeeWalletTransactionStatus.posted) return false;
      if (!(canViewAllFinancial || canViewAll || employeeId == entry.employeeId)) return false;
      if (filter.employeeId != null && filter.employeeId != entry.employeeId) return false;
      final commissionLedger = entry.type == EmployeeWalletTransactionType.commission ||
        entry.type == EmployeeWalletTransactionType.refund || entry.sourceFinanceEntryId != null;
      return commissionLedger
        ? _db.hasPermission('finance.commission.view', employeeId: entry.employeeId)
        : _db.hasPermission('finance.salary.view', employeeId: entry.employeeId);
    }).toList();
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
    final businessExpenses = _db.businessExpenses.where((item) =>
      range.contains(item.createdAt) && item.status == BusinessExpenseStatus.posted).toList();
    final operatingExpense = businessExpenses.fold<int>(0, (sum, item) => sum + item.amount);
    final cost = commissionCost + payrollCost + operatingExpense;

    final allVisiblePayments = _db.appointmentPayments.where((item) {
      final appointment = _db.appointmentById(item.appointmentId);
      return appointment != null &&
        (canViewAllFinancial || canViewAll || employeeId == appointment.employeeId) &&
        _db.hasPermission('finance.income.view', employeeId: appointment.employeeId) &&
        matchesReportAppointment(appointment);
    }).toList();
    final payments = allVisiblePayments.where((item) => range.contains(item.createdAt) &&
      (filter.paymentMethod == null || item.method.name == filter.paymentMethod)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final collectedRevenue = payments.fold<int>(0, (sum, item) => sum + item.signedAmount);
    final paymentsByMethod = <String, num>{
      for (final method in BusinessPaymentMethod.values)
        method.label: payments.where((item) => item.method == method)
            .fold<int>(0, (sum, item) => sum + item.signedAmount),
    };
    final expensesByCategory = <String, num>{
      'کمیسیون پرسنل': commissionCost,
      'حقوق و مزایا': payrollCost,
      for (final category in BusinessExpenseCategory.values)
        category.label: businessExpenses.where((item) => item.category == category)
            .fold<int>(0, (sum, item) => sum + item.amount),
    };

    final recognizedByAppointment = <String, int>{};
    for (final entry in allVisibleFinanceEntries) {
      recognizedByAppointment[entry.appointmentId] =
          (recognizedByAppointment[entry.appointmentId] ?? 0) + entry.receivedAmount;
    }
    final paidByAppointment = <String, int>{};
    for (final payment in allVisiblePayments) {
      paidByAppointment[payment.appointmentId] =
          (paidByAppointment[payment.appointmentId] ?? 0) + payment.signedAmount;
    }
    final financeCompletedAppointments = canViewAppointments
      ? completed
      : _db.appointments.where((item) =>
          range.contains(item.startAt) &&
          item.status == AppointmentStatus.completed &&
          (canViewAllFinancial || employeeId == item.employeeId) &&
          _db.hasPermission('finance.income.view', employeeId: item.employeeId) &&
          matchesReportAppointment(item)).toList();
    final canViewCustomerDetails = canViewAppointments && _db.hasPermission('customers.view');
    final debtByCustomer = <String, int>{};
    final debtNameByCustomer = <String, String>{};
    final debtAppointments = <String, int>{};
    final partialPayments = <AppointmentPayment>[];
    var receivables = 0;
    for (final appointment in financeCompletedAppointments.where((item) =>
      _db.hasPermission('finance.income.view', employeeId: item.employeeId))) {
      final due = (recognizedByAppointment[appointment.id] ?? appointment.price.round()) -
          (paidByAppointment[appointment.id] ?? 0);
      if (due > 0) {
        receivables += due;
        if (canViewCustomerDetails) {
          debtByCustomer[appointment.customerId] = (debtByCustomer[appointment.customerId] ?? 0) + due;
          debtNameByCustomer[appointment.customerId] = appointment.customerName;
          debtAppointments[appointment.customerId] = (debtAppointments[appointment.customerId] ?? 0) + 1;
          if ((paidByAppointment[appointment.id] ?? 0) > 0) {
            partialPayments.addAll(allVisiblePayments.where((payment) =>
              payment.appointmentId == appointment.id && payment.type == BusinessPaymentType.receipt));
          }
        }
      }
    }
    final customerDebts = canViewCustomerDetails
      ? debtByCustomer.entries.map((entry) => ReportCustomerDebt(
          customerId: entry.key,
          customerName: debtNameByCustomer[entry.key] ?? 'مشتری',
          amount: entry.value,
          appointmentCount: debtAppointments[entry.key] ?? 0,
        )).toList()..sort((a, b) => b.amount.compareTo(a.amount))
      : <ReportCustomerDebt>[];

    final employeeRevenue = <String, num>{};
    final employeeNames = <String, String>{};
    for (final entry in revenueEntries) {
      employeeRevenue[entry.employeeId] = (employeeRevenue[entry.employeeId] ?? 0) + entry.receivedAmount;
      final employee = _db.employees.where((item) => item.id == entry.employeeId).toList();
      employeeNames[entry.employeeId] = employee.isEmpty ? 'پرسنل' : employee.first.fullName;
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

    final serviceStats = <String, ({
      String name, num revenue, int count, num priceTotal,
      num directCostTotal, int costKnownCount, Map<String, int> employeeCounts,
      Map<DateTime, num> trendRevenue, Map<DateTime, int> trendCounts,
    })>{};
    for (final appointment in operationalCompleted) {
      final ids = appointment.serviceIds.isEmpty ? <String>[''] : appointment.serviceIds;
      final parts = <({String id, String name, num price, num? directCost})>[];
      for (final serviceId in ids) {
        final snapshots = appointment.serviceSnapshots.where((item) => item['service_id'] == serviceId).toList();
        final snapshot = snapshots.isEmpty ? null : snapshots.first;
        final serviceMatches = _db.services.where((item) => item.id == serviceId).toList();
        final service = serviceMatches.isEmpty ? null : serviceMatches.first;
        final name = (snapshot?['title'] as String?) ??
          (snapshot?['service_name'] as String?) ?? service?.title ??
          (appointment.serviceName.trim().isEmpty ? 'خدمت ثبت‌نشده' : appointment.serviceName);
        final savedPrice = snapshot?['price'] as num?;
        final price = savedPrice ?? (ids.length == 1 ? appointment.price : appointment.price / ids.length);
        final directCost = snapshot != null && snapshot['direct_cost'] is num
          ? snapshot['direct_cost'] as num : null;
        parts.add((id: serviceId, name: name, price: price, directCost: directCost));
      }
      final weightTotal = parts.fold<num>(0, (sum, item) => sum + item.price);
      final appointmentRevenue = revenueByAppointmentInRange[appointment.id] ?? 0;
      var allocatedRevenue = 0.0;
      for (var index = 0; index < parts.length; index++) {
        final part = parts[index];
        final amount = index == parts.length - 1
          ? appointmentRevenue - allocatedRevenue
          : (weightTotal == 0 ? appointmentRevenue / parts.length : appointmentRevenue * part.price / weightTotal);
        allocatedRevenue += amount;
        final key = part.id.isEmpty ? 'legacy:${part.name}' : part.id;
        final current = serviceStats[key];
        final employeeCounts = current?.employeeCounts ?? <String, int>{};
        if (_db.canViewEmployee(appointment.employeeId)) {
          employeeCounts[appointment.employeeName] = (employeeCounts[appointment.employeeName] ?? 0) + 1;
        }
        final trendRevenue = current?.trendRevenue ?? <DateTime, num>{};
        final trendCounts = current?.trendCounts ?? <DateTime, int>{};
        final serviceRangeDays = range.endExclusive.difference(range.start).inDays;
        final serviceDate = appointment.startAt;
        final trendBucket = serviceRangeDays <= 31
          ? DateTime(serviceDate.year, serviceDate.month, serviceDate.day)
          : JalaliDate(JalaliDate.fromDateTime(serviceDate).year, JalaliDate.fromDateTime(serviceDate).month, 1).toDateTime();
        trendRevenue[trendBucket] = (trendRevenue[trendBucket] ?? 0) + amount;
        trendCounts[trendBucket] = (trendCounts[trendBucket] ?? 0) + 1;
        serviceStats[key] = (
          name: part.name,
          revenue: (current?.revenue ?? 0) + amount,
          count: (current?.count ?? 0) + 1,
          priceTotal: (current?.priceTotal ?? 0) + part.price,
          directCostTotal: (current?.directCostTotal ?? 0) + (part.directCost ?? 0),
          costKnownCount: (current?.costKnownCount ?? 0) + (part.directCost != null ? 1 : 0),
          employeeCounts: employeeCounts,
          trendRevenue: trendRevenue,
          trendCounts: trendCounts,
        );
      }
    }
    final serviceMetrics = serviceStats.entries.map((entry) {
      final item = entry.value;
      final hasCompleteCost = item.count > 0 && item.costKnownCount == item.count;
      final directCost = hasCompleteCost ? item.directCostTotal : null;
      final profit = directCost == null ? null : item.revenue - directCost;
      final trendEntries = item.trendRevenue.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      return ReportServiceMetric(
        serviceId: entry.key.startsWith('legacy:') ? '' : entry.key,
        name: item.name,
        revenue: item.revenue,
        count: item.count,
        averagePrice: item.count == 0 ? 0 : item.priceTotal / item.count,
        directCost: directCost,
        profit: profit,
        marginPercent: profit == null || item.revenue == 0 ? null : profit * 100 / item.revenue,
        employeeCounts: Map.unmodifiable(item.employeeCounts),
        trend: [for (final point in trendEntries) ReportTrendPoint(
          label: range.endExclusive.difference(range.start).inDays <= 31
            ? JalaliDate.fromDateTime(point.key).short
            : JalaliDate.fromDateTime(point.key).monthName,
          start: point.key, revenue: point.value, cost: 0,
          appointments: item.trendCounts[point.key] ?? 0,
        )],
      );
    }).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

    final now = DateTime.now();
    final restrictCustomerScope = !canViewAll ||
      filter.serviceId != null || filter.employeeId != null ||
      filter.customerId != null || filter.status != null ||
      filter.category != null || filter.paymentMethod != null;
    final candidateCustomers = !canViewCustomerDetails
      ? <Customer>[]
      : restrictCustomerScope
        ? _db.customers.where((customer) => operationalAppointments.any((item) => item.customerId == customer.id))
        : _db.customers.where((customer) => filter.customerId == null || customer.id == filter.customerId);
    final customerMetrics = candidateCustomers.map((customer) {
      final lifetimeVisits = _db.appointments.where((item) =>
        canSeeAppointment(item) && item.customerId == customer.id && item.status == AppointmentStatus.completed).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      final periodVisits = operationalCompleted.where((item) => item.customerId == customer.id).toList();
      final firstVisit = lifetimeVisits.isEmpty ? null : lifetimeVisits.first.startAt;
      final lastVisit = lifetimeVisits.isEmpty ? (canViewAll ? customer.lastVisitAt : null) : lifetimeVisits.last.startAt;
      final daysSinceVisit = lastVisit == null ? (customer.createdAt == null ? 99999 : now.difference(customer.createdAt!).inDays) : now.difference(lastVisit).inDays;
      var totalGapDays = 0;
      for (var i = 1; i < lifetimeVisits.length; i++) {
        totalGapDays += lifetimeVisits[i].startAt.difference(lifetimeVisits[i - 1].startAt).inDays.abs();
      }
      final lifetimeAppointmentIds = lifetimeVisits.map((item) => item.id).toSet();
      final customerIncomeEntries = _db.employeeFinanceEntries.where((entry) =>
        lifetimeAppointmentIds.contains(entry.appointmentId) &&
        (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund) &&
        (canViewAllFinancial || canViewAll || employeeId == entry.employeeId) &&
        _db.hasPermission('finance.income.view', employeeId: entry.employeeId)).toList();
      final totalSpent = customerIncomeEntries.isEmpty
        ? lifetimeVisits.fold<num>(0, (sum, item) => sum + item.price)
        : customerIncomeEntries.fold<num>(0, (sum, item) => sum + item.receivedAmount);
      final isNew = firstVisit != null
        ? range.contains(firstVisit)
        : customer.createdAt != null && range.contains(customer.createdAt!);
      return ReportCustomerMetric(
        customerId: customer.id,
        name: customer.fullName,
        visits: periodVisits.length,
        lifetimeVisits: lifetimeVisits.length,
        repeatVisits: lifetimeVisits.length > 1 ? lifetimeVisits.length - 1 : 0,
        totalSpent: totalSpent,
        averageSpend: lifetimeVisits.isEmpty ? 0 : totalSpent / lifetimeVisits.length,
        firstVisitAt: firstVisit ?? customer.createdAt,
        lastVisitAt: lastVisit,
        averageGapDays: lifetimeVisits.length < 2 ? null : totalGapDays / (lifetimeVisits.length - 1),
        isNew: isNew,
        isLoyal: lifetimeVisits.length >= 4,
        isInactive: lastVisit != null && daysSinceVisit >= 90 || (lastVisit == null && customer.createdAt != null && daysSinceVisit >= 90),
        isAtRisk: (lastVisit != null || customer.createdAt != null) && daysSinceVisit >= 60 && daysSinceVisit < 90,
      );
    }).toList()..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

    final activePeriodCustomers = customerMetrics.where((item) => item.visits > 0).toList();
    final repeatPeriodCustomers = activePeriodCustomers.where((item) => item.visits >= 2).length;
    final repeatCustomerRate = activePeriodCustomers.isEmpty ? 0.0 : repeatPeriodCustomers * 100 / activePeriodCustomers.length;
    final newCustomers = customerMetrics.where((item) => item.isNew).length;
    final oldCustomers = activePeriodCustomers.where((item) => !item.isNew).length;
    final loyalCustomers = customerMetrics.where((item) => item.isLoyal).length;
    final inactiveCustomers = customerMetrics.where((item) => item.isInactive).length;
    final atRiskCustomers = customerMetrics.where((item) => item.isAtRisk).length;
    final newCustomerBuckets = <DateTime, int>{};
    final rangeDaysForAcquisition = range.endExclusive.difference(range.start).inDays;
    for (final customer in customerMetrics.where((item) => item.isNew)) {
      final date = customer.firstVisitAt;
      if (date == null || !range.contains(date)) continue;
      final bucket = rangeDaysForAcquisition <= 31
        ? DateTime(date.year, date.month, date.day)
        : JalaliDate(JalaliDate.fromDateTime(date).year, JalaliDate.fromDateTime(date).month, 1).toDateTime();
      newCustomerBuckets[bucket] = (newCustomerBuckets[bucket] ?? 0) + 1;
    }
    final newCustomerTrend = newCustomerBuckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final hourlyCounts = <int, int>{};
    final hourlyScheduled = <int, int>{};
    final hourlyBooked = <int, int>{};
    final weekdayCounts = <int, int>{for (var weekday = 1; weekday <= 7; weekday++) weekday: 0};
    final daysInRange = range.endExclusive.difference(range.start).inDays;
    var capacityMinutes = 0;
    var bookedCapacityMinutes = 0;
    if (canViewAppointments && daysInRange > 0 && daysInRange <= 366) {
      final capacityEmployeeId = canViewAll ? filter.employeeId : employeeId;
      final activeEmployees = _db.employees.where((item) =>
        item.isActive && (capacityEmployeeId == null || item.id == capacityEmployeeId)).toList();
      for (var dayIndex = 0; dayIndex < daysInRange; dayIndex++) {
        final day = DateTime(range.start.year, range.start.month, range.start.day + dayIndex);
        for (final employee in activeEmployees) {
          for (final shift in _db.employeeShiftsForDate(employee.id, day)) {
            final shiftStart = shift.startMinutes;
            final shiftEnd = shift.endMinutes;
            capacityMinutes += (shiftEnd - shiftStart).clamp(0, 1440).toInt();
            for (var hour = shiftStart ~/ 60; hour <= (shiftEnd - 1) ~/ 60; hour++) {
              final overlap = (shiftEnd < (hour + 1) * 60 ? shiftEnd : (hour + 1) * 60) -
                (shiftStart > hour * 60 ? shiftStart : hour * 60);
              if (overlap > 0) hourlyScheduled[hour] = (hourlyScheduled[hour] ?? 0) + overlap;
            }
          }
        }
      }
      for (final appointment in operationalAppointments.where((item) =>
        item.status != AppointmentStatus.cancelled && item.status != AppointmentStatus.noShow)) {
        hourlyCounts[appointment.startAt.hour] = (hourlyCounts[appointment.startAt.hour] ?? 0) + 1;
        final weekday = appointment.startAt.weekday;
        weekdayCounts[weekday] = (weekdayCounts[weekday] ?? 0) + 1;
        bookedCapacityMinutes += appointment.durationMinutes;
        var cursor = appointment.startAt;
        var remaining = appointment.durationMinutes;
        while (remaining > 0) {
          final hour = cursor.hour;
          final available = 60 - cursor.minute;
          final booked = remaining < available ? remaining : available;
          hourlyBooked[hour] = (hourlyBooked[hour] ?? 0) + booked;
          remaining -= booked;
          cursor = cursor.add(Duration(minutes: booked));
        }
      }
    } else {
      for (final appointment in operationalAppointments.where((item) =>
        item.status != AppointmentStatus.cancelled && item.status != AppointmentStatus.noShow)) {
        hourlyCounts[appointment.startAt.hour] = (hourlyCounts[appointment.startAt.hour] ?? 0) + 1;
        weekdayCounts[appointment.startAt.weekday] = (weekdayCounts[appointment.startAt.weekday] ?? 0) + 1;
        bookedCapacityMinutes += appointment.durationMinutes;
      }
    }
    final hourKeys = <int>{...hourlyScheduled.keys, ...hourlyCounts.keys, ...hourlyBooked.keys}.toList()..sort();
    final hourlyDemand = [for (final hour in hourKeys)
      ReportHourMetric(hour: hour, appointments: hourlyCounts[hour] ?? 0,
        scheduledMinutes: hourlyScheduled[hour] ?? 0, bookedMinutes: hourlyBooked[hour] ?? 0)];
    final weekdayDemand = weekdayCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final weekdayMetrics = [for (final item in weekdayDemand)
      ReportWeekdayMetric(weekday: item.key,
        label: JalaliDate.fromDateTime(DateTime(2024, 1, 1).add(Duration(days: item.key - 1))).weekdayName,
        appointments: item.value)];
    final directCostCount = serviceStats.values.fold<int>(0, (sum, item) => sum + item.costKnownCount);
    final serviceCount = serviceStats.values.fold<int>(0, (sum, item) => sum + item.count);
    final directCostCoveragePercent = serviceCount == 0 ? 0.0 : directCostCount * 100 / serviceCount;

    int costBetween(DateTime from, DateTime to) {
      final commission = (canViewCommission ? allVisibleFinanceEntries : <EmployeeFinanceEntry>[]).where((item) =>
        !item.createdAt.isBefore(from) && item.createdAt.isBefore(to) &&
        _db.hasPermission('finance.commission.view', employeeId: item.employeeId)).fold<int>(0, (sum, item) =>
          sum + (item.type == FinanceEntryType.refund ? -item.commissionAmount.abs() : item.commissionAmount));
      final payroll = walletCostFor(walletEntries.where((item) =>
        !item.createdAt.isBefore(from) && item.createdAt.isBefore(to)));
      final operations = _db.businessExpenses.where((item) =>
        item.status == BusinessExpenseStatus.posted &&
        !item.createdAt.isBefore(from) && item.createdAt.isBefore(to))
        .fold<int>(0, (sum, item) => sum + item.amount);
      return commission + payroll + operations;
    }

    final trend = <ReportTrendPoint>[];
    final days = range.endExclusive.difference(range.start).inDays;
    if (days <= 31) {
      var cursor = DateTime(range.start.year, range.start.month, range.start.day);
      while (cursor.isBefore(range.endExclusive)) {
        final next = cursor.add(const Duration(days: 1));
        final items = operationalAppointments.where((item) => !item.startAt.isBefore(cursor) && item.startAt.isBefore(next)).toList();
        trend.add(ReportTrendPoint(
          label: JalaliDate.fromDateTime(cursor).short,
          start: cursor,
          revenue: revenueEntries.where((entry) => !entry.createdAt.isBefore(cursor) && entry.createdAt.isBefore(next))
              .fold<int>(0, (sum, entry) => sum + entry.receivedAmount),
          cost: costBetween(cursor, next),
          appointments: items.length,
        ));
        cursor = next;
      }
    } else {
      var cursorJalali = JalaliDate(range.jalaliStart.year, range.jalaliStart.month, 1);
      while (cursorJalali.toDateTime().isBefore(range.endExclusive)) {
        final nextJalali = cursorJalali.addMonths(1);
        final monthStart = cursorJalali.toDateTime();
        final nextMonthStart = nextJalali.toDateTime();
        final from = monthStart.isBefore(range.start) ? range.start : monthStart;
        final to = nextMonthStart.isAfter(range.endExclusive) ? range.endExclusive : nextMonthStart;
        final items = operationalAppointments.where((item) => !item.startAt.isBefore(from) && item.startAt.isBefore(to)).toList();
        trend.add(ReportTrendPoint(
          label: cursorJalali.monthName,
          start: from,
          revenue: revenueEntries.where((entry) => !entry.createdAt.isBefore(from) && entry.createdAt.isBefore(to))
              .fold<int>(0, (sum, entry) => sum + entry.receivedAmount),
          cost: costBetween(from, to),
          appointments: items.length,
        ));
        cursorJalali = nextJalali;
      }
    }

    final previousDuration = range.endExclusive.difference(range.start);
    late DateTime previousStart;
    late DateTime previousEnd;
    switch (range.period) {
      case ReportPeriod.today:
      case ReportPeriod.yesterday:
        previousStart = range.start.subtract(const Duration(days: 1));
        previousEnd = range.start;
        break;
      case ReportPeriod.thisWeek:
      case ReportPeriod.lastWeek:
        previousStart = range.start.subtract(const Duration(days: 7));
        previousEnd = range.start;
        break;
      case ReportPeriod.thisMonth:
      case ReportPeriod.lastMonth:
        final monthStart = JalaliDate(range.jalaliStart.year, range.jalaliStart.month, 1);
        previousStart = monthStart.addMonths(-1).toDateTime();
        previousEnd = monthStart.toDateTime();
        break;
      case ReportPeriod.thisYear:
        previousStart = JalaliDate(range.jalaliStart.year - 1, 1, 1).toDateTime();
        previousEnd = JalaliDate(range.jalaliStart.year, 1, 1).toDateTime();
        break;
      case ReportPeriod.custom:
        previousStart = range.start.subtract(previousDuration);
        previousEnd = range.start;
        break;
    }
    final previousPeriodAppointments = _db.appointments.where((item) =>
      canSeeAppointment(item) && !item.startAt.isBefore(previousStart) &&
      item.startAt.isBefore(previousEnd) &&
      matchesReportAppointment(item, paymentFrom: previousStart, paymentTo: previousEnd)).length;
    final previousEntries = _visibleRevenueEntries(from: previousStart, to: previousEnd).where((entry) {
      final appointment = _db.appointmentById(entry.appointmentId);
      return appointment != null &&
        matchesReportAppointment(appointment, paymentFrom: previousStart, paymentTo: previousEnd);
    });
    final previousRevenue = previousEntries.fold<int>(0, (sum, item) => sum + item.receivedAmount);
    final previousCommission = canViewCommission ? previousEntries.where((item) =>
      _db.hasPermission('finance.commission.view', employeeId: item.employeeId)).fold<int>(0, (sum, item) =>
      sum + (item.type == FinanceEntryType.refund ? -item.commissionAmount.abs() : item.commissionAmount)) : 0;
    final previousPayroll = canViewSalary ? walletCostFor(_db.employeeWalletTransactions.where((item) =>
      item.status == EmployeeWalletTransactionStatus.posted &&
      !item.createdAt.isBefore(previousStart) && item.createdAt.isBefore(previousEnd) &&
      (canViewAllFinancial || canViewAll || employeeId == item.employeeId) &&
      _db.hasPermission('finance.salary.view', employeeId: item.employeeId) &&
      (filter.employeeId == null || filter.employeeId == item.employeeId))) : 0;
    final previousOperations = _db.businessExpenses.where((item) =>
      item.status == BusinessExpenseStatus.posted &&
      !item.createdAt.isBefore(previousStart) && item.createdAt.isBefore(previousEnd))
      .fold<int>(0, (sum, item) => sum + item.amount);
    final previousCost = previousCommission + previousPayroll + previousOperations;

    final periodWalletSummary = EmployeeWalletSummary.fromTransactions(walletEntries);
    final staffPaid = periodWalletSummary.paid;
    final staffWallets = canViewSalary
        ? _db.employees.where((item) =>
            (canViewAllFinancial || canViewAll || employeeId == item.id) &&
            (filter.employeeId == null || filter.employeeId == item.id) &&
            _db.hasPermission('finance.salary.view', employeeId: item.id)).map((employee) {
              final entries = _db.walletTransactionsFor(
                employee.id,
                to: range.endExclusive.subtract(const Duration(microseconds: 1)),
              );
              return EmployeeWallet.fromTransactions(
                employee.id, entries, calculatedAt: range.endExclusive,
              );
            }).toList()
        : <EmployeeWallet>[];
    final staffPayable = staffWallets.fold<int>(0, (sum, wallet) => sum + wallet.payableBalance);
    final staffDebt = staffWallets.fold<int>(0, (sum, wallet) => sum + wallet.debt);
    final advancesOutstanding = _db.payrollAdvances.where((item) =>
      item.status == AdvanceStatus.paid &&
      (canViewAllFinancial || canViewAll || employeeId == item.employeeId) &&
      _db.hasPermission('finance.salary.view', employeeId: item.employeeId) &&
      (filter.employeeId == null || filter.employeeId == item.employeeId) &&
      item.requestedAt.isBefore(range.endExclusive))
      .fold<int>(0, (sum, item) => sum + item.outstanding);
    final settlements = _db.employeeWalletSettlements.where((item) =>
      range.contains(item.createdAt) && (canViewAllFinancial || canViewAll || employeeId == item.employeeId) &&
      _db.hasPermission('finance.settlement.view', employeeId: item.employeeId) &&
      (filter.employeeId == null || filter.employeeId == item.employeeId) &&
      (filter.settlementStatus == null || item.status == filter.settlementStatus)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final recentAppointments = operationalAppointments.toList()
      ..sort((a, b) => (b.createdAt ?? b.startAt).compareTo(a.createdAt ?? a.startAt));
    final recentTransactions = walletEntries.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final margin = revenue == 0 ? 0.0 : ((revenue - cost) / revenue) * 100;
    final companyShare = revenueEntries.fold<int>(0, (sum, entry) => sum +
      (entry.type == FinanceEntryType.refund ? -entry.companyShare.abs() : entry.companyShare));

    return ReportAnalytics(
      range: range,
      revenue: revenue,
      cost: cost,
      commissionCost: commissionCost,
      payrollCost: payrollCost,
      totalAppointments: operationalAppointments.length,
      completedAppointments: operationalCompleted.length,
      cancelledAppointments: operationalStatusCounts[AppointmentStatus.cancelled.label] ?? 0,
      noShowAppointments: operationalStatusCounts[AppointmentStatus.noShow.label] ?? 0,
      uniqueCustomers: operationalAppointments.map((item) => item.customerId).where((id) => id.isNotEmpty).toSet().length,
      statusCounts: operationalStatusCounts,
      trend: trend,
      employees: employeeMetrics,
      services: serviceMetrics,
      operationalAppointments: operationalAppointments,
      customerMetrics: customerMetrics,
      hourlyDemand: hourlyDemand,
      weekdayDemand: weekdayMetrics,
      repeatCustomerRate: repeatCustomerRate,
      newCustomers: newCustomers,
      oldCustomers: oldCustomers,
      loyalCustomers: loyalCustomers,
      inactiveCustomers: inactiveCustomers,
      atRiskCustomers: atRiskCustomers,
      rejectedAppointments: 0,
      capacityMinutes: capacityMinutes,
      bookedCapacityMinutes: bookedCapacityMinutes,
      directCostCoveragePercent: directCostCoveragePercent,
      filter: filter,
      companyShare: companyShare,
      operationalStatusCounts: operationalStatusCounts,
      newCustomerTrend: [for (final item in newCustomerTrend) ReportTrendPoint(
        label: rangeDaysForAcquisition <= 31 ? JalaliDate.fromDateTime(item.key).short : JalaliDate.fromDateTime(item.key).monthName,
        start: item.key, revenue: 0, cost: 0, appointments: item.value,
      )],
      recentAppointments: recentAppointments.take(5).toList(),
      recentTransactions: recentTransactions.take(5).toList(),
      costNote: 'درآمد از اسناد خدمات تکمیل‌شده، وصول از رسیدها، و هزینه از دفتر حقوق/کمیسیون و اسناد هزینه ثبت‌شده محاسبه می‌شود. پرداخت حقوق و مساعده دوباره‌شماری نشده‌اند. فیلتر پرسنل، خدمت، دسته‌بندی، مشتری و وضعیت بر اسناد مرتبط اعمال می‌شود؛ هزینه‌های عمومی مجموعه به‌دلیل نداشتن انتساب به این ابعاد در جمع هزینه عملیاتی کل بازه باقی می‌مانند.' + (!hasFullIncomeScope ? ' بخشی از درآمد به‌دلیل محدودیت دسترسی پرسنلی در گزارش لحاظ نشده است.' : '')
        + (!hasFullCommissionScope || !hasFullSalaryScope ? ' بخشی از اقلام هزینه به‌دلیل محدودیت مجوز شما در دسترس نیست؛ سود نمایش‌داده‌شده کامل نیست.' : ''),
      grossRevenue: grossRevenue,
      collectedRevenue: collectedRevenue,
      receivables: receivables,
      operatingExpense: operatingExpense,
      staffPayable: staffPayable,
      staffDebt: staffDebt,
      staffPaid: staffPaid,
      advancesOutstanding: advancesOutstanding,
      profitMarginPercent: margin,
      grossProfit: null,
      previousPeriodRevenue: previousRevenue,
      previousPeriodCost: previousCost,
      previousPeriodAppointments: previousPeriodAppointments,
      paymentsByMethod: paymentsByMethod,
      expensesByCategory: expensesByCategory,
      customerDebts: customerDebts,
      partialPayments: partialPayments,
      paymentTransactions: payments,
      businessExpenses: businessExpenses,
      settlements: settlements,
      walletTransactions: walletEntries,
      averageAppointmentMinutes: operationalCompleted.isEmpty ? 0 :
        operationalCompleted.fold<int>(0, (sum, item) => sum + item.durationMinutes) / operationalCompleted.length,
    );
  }
}
