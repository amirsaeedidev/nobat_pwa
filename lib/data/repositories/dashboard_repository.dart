import '../../core/utils/jalali.dart';
import '../mock/app_database.dart';
import '../models/appointment.dart';
import '../models/dashboard_stats.dart';
import '../models/enums.dart';
import '../models/employee_finance.dart';
import '../models/employee_wallet.dart';
import '../models/report_analytics.dart';
import '../models/business_finance.dart';

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

  @override
  Future<ReportAnalytics> fetchReportAnalytics({required ReportDateRange range}) async {
    await _db.delay(120);
    _db.requirePermission('finance.income.view');
    final canViewAll = _db.hasPermission('appointments.view_all');
    final canViewSelf = _db.hasPermission('appointments.view_self');
    if (!canViewAll && !canViewSelf) _db.requirePermission('appointments.view_all');
    final employeeId = _db.currentAccessAccount.employeeId;
    final canSeeAppointment = (Appointment item) =>
        canViewAll || (canViewSelf && employeeId != null && item.employeeId == employeeId);
    final appointments = _db.appointments.where((item) =>
      canSeeAppointment(item) && range.contains(item.startAt)).toList();
    final completed = appointments.where((item) => item.status == AppointmentStatus.completed).toList();
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
    final allVisibleFinanceEntries = canViewCommission
        ? _db.employeeFinanceEntries.where((entry) =>
            (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund) &&
            (canViewAll || employeeId == entry.employeeId)).toList()
        : <EmployeeFinanceEntry>[];

    final commissionByEmployee = <String, int>{};
    var commissionCost = 0;
    var grossRevenue = 0;
    var revenue = 0;
    for (final entry in financeEntries) {
      final signedCommission = entry.type == FinanceEntryType.refund
          ? -entry.commissionAmount.abs()
          : entry.commissionAmount;
      commissionCost += signedCommission;
      commissionByEmployee[entry.employeeId] = (commissionByEmployee[entry.employeeId] ?? 0) + signedCommission;
      grossRevenue += entry.grossAmount;
      revenue += entry.receivedAmount;
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
    final businessExpenses = _db.businessExpenses.where((item) =>
      range.contains(item.createdAt) && item.status == BusinessExpenseStatus.posted).toList();
    final operatingExpense = businessExpenses.fold<int>(0, (sum, item) => sum + item.amount);
    final cost = commissionCost + payrollCost + operatingExpense;

    final payments = _db.appointmentPayments.where((item) => range.contains(item.createdAt)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final paymentTransactions = _db.appointmentPayments.where((item) =>
      range.contains(item.createdAt) &&
      appointments.any((appointment) => appointment.id == item.appointmentId)).toList()
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
    for (final payment in _db.appointmentPayments) {
      paidByAppointment[payment.appointmentId] =
          (paidByAppointment[payment.appointmentId] ?? 0) + payment.signedAmount;
    }
    final debtByCustomer = <String, int>{};
    final debtNameByCustomer = <String, String>{};
    final debtAppointments = <String, int>{};
    final partialPayments = <AppointmentPayment>[];
    var receivables = 0;
    for (final appointment in completed) {
      final due = (recognizedByAppointment[appointment.id] ?? appointment.price.round()) -
          (paidByAppointment[appointment.id] ?? 0);
      if (due > 0) {
        receivables += due;
        debtByCustomer[appointment.customerId] = (debtByCustomer[appointment.customerId] ?? 0) + due;
        debtNameByCustomer[appointment.customerId] = appointment.customerName;
        debtAppointments[appointment.customerId] = (debtAppointments[appointment.customerId] ?? 0) + 1;
        if ((paidByAppointment[appointment.id] ?? 0) > 0) {
          partialPayments.addAll(_db.appointmentPayments.where((payment) =>
            payment.appointmentId == appointment.id && payment.type == BusinessPaymentType.receipt));
        }
      }
    }
    final customerDebts = debtByCustomer.entries.map((entry) => ReportCustomerDebt(
      customerId: entry.key,
      customerName: debtNameByCustomer[entry.key] ?? 'مشتری',
      amount: entry.value,
      appointmentCount: debtAppointments[entry.key] ?? 0,
    )).toList()..sort((a, b) => b.amount.compareTo(a.amount));

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
            : serviceMatches.first.title;
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
      final commission = allVisibleFinanceEntries.where((item) =>
        !item.createdAt.isBefore(from) && item.createdAt.isBefore(to)).fold<int>(0, (sum, item) =>
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
        final items = appointments.where((item) => !item.startAt.isBefore(cursor) && item.startAt.isBefore(next)).toList();
        trend.add(ReportTrendPoint(
          label: JalaliDate.fromDateTime(cursor).short,
          start: cursor,
          revenue: items.where((item) => item.status == AppointmentStatus.completed)
              .fold<num>(0, (sum, item) => sum + (recognizedByAppointment[item.id] ?? item.price)),
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
          revenue: items.where((item) => item.status == AppointmentStatus.completed)
              .fold<num>(0, (sum, item) => sum + (recognizedByAppointment[item.id] ?? item.price)),
          cost: costBetween(from, to),
          appointments: items.length,
        ));
        cursor = next;
      }
    }

    final previousDuration = range.endExclusive.difference(range.start);
    final previousStart = range.start.subtract(previousDuration);
    final previousEntries = allVisibleFinanceEntries.where((item) =>
      !item.createdAt.isBefore(previousStart) && item.createdAt.isBefore(range.start));
    final previousRevenue = previousEntries.fold<int>(0, (sum, item) => sum + item.receivedAmount);
    final previousCommission = previousEntries.fold<int>(0, (sum, item) =>
      sum + (item.type == FinanceEntryType.refund ? -item.commissionAmount.abs() : item.commissionAmount));
    final previousPayroll = canViewSalary ? walletCostFor(_db.employeeWalletTransactions.where((item) =>
      item.status == EmployeeWalletTransactionStatus.posted &&
      !item.createdAt.isBefore(previousStart) && item.createdAt.isBefore(range.start) &&
      (canViewAll || employeeId == item.employeeId))) : 0;
    final previousOperations = _db.businessExpenses.where((item) =>
      item.status == BusinessExpenseStatus.posted &&
      !item.createdAt.isBefore(previousStart) && item.createdAt.isBefore(range.start))
      .fold<int>(0, (sum, item) => sum + item.amount);
    final previousCost = previousCommission + previousPayroll + previousOperations;

    final staffPaid = walletEntries.where((item) => item.type == EmployeeWalletTransactionType.salaryPayment)
        .fold<int>(0, (sum, item) => sum + item.amount.abs());
    final staffPayable = walletEntries.where((item) => item.type != EmployeeWalletTransactionType.salaryPayment)
        .fold<int>(0, (sum, item) => sum + item.amount);
    final advancesOutstanding = _db.payrollAdvances.where((item) =>
      item.status == AdvanceStatus.paid &&
      (canViewAll || employeeId == item.employeeId) &&
      !item.requestedAt.isBefore(range.start) && item.requestedAt.isBefore(range.endExclusive))
      .fold<int>(0, (sum, item) => sum + item.outstanding);
    final settlements = _db.employeeWalletSettlements.where((item) =>
      range.contains(item.createdAt) && (canViewAll || employeeId == item.employeeId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final recentAppointments = appointments.toList()
      ..sort((a, b) => (b.createdAt ?? b.startAt).compareTo(a.createdAt ?? a.startAt));
    final recentTransactions = walletEntries.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final margin = revenue == 0 ? 0.0 : ((revenue - cost) / revenue) * 100;

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
      costNote: 'درآمد از اسناد خدمات تکمیل‌شده، وصول از رسیدها، و هزینه از دفتر حقوق/کمیسیون و اسناد هزینه ثبت‌شده محاسبه می‌شود. پرداخت حقوق و مساعده دوباره‌شماری نشده‌اند.',
      grossRevenue: grossRevenue,
      collectedRevenue: collectedRevenue,
      receivables: receivables,
      operatingExpense: operatingExpense,
      staffPayable: staffPayable,
      staffPaid: staffPaid,
      advancesOutstanding: advancesOutstanding,
      profitMarginPercent: margin,
      grossProfit: null,
      previousPeriodRevenue: previousRevenue,
      previousPeriodCost: previousCost,
      paymentsByMethod: paymentsByMethod,
      expensesByCategory: expensesByCategory,
      customerDebts: customerDebts,
      partialPayments: partialPayments,
      paymentTransactions: paymentTransactions,
      businessExpenses: businessExpenses,
      settlements: settlements,
    );
  }
}
