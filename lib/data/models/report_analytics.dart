import '../../core/utils/jalali.dart';
import 'appointment.dart';
import 'employee_wallet.dart';
import 'business_finance.dart';
import 'enums.dart';

enum ReportPeriod {
  today('امروز'), yesterday('دیروز'), thisWeek('هفته جاری'),
  lastWeek('هفته گذشته'), thisMonth('ماه جاری'), lastMonth('ماه گذشته'),
  thisYear('سال جاری'), custom('بازه دلخواه');
  const ReportPeriod(this.label);
  final String label;
}

class ReportDateRange {
  const ReportDateRange({required this.period, required this.start, required this.endExclusive});
  final ReportPeriod period;
  final DateTime start;
  final DateTime endExclusive;

  factory ReportDateRange.preset(ReportPeriod period, {DateTime? now}) {
    final today = JalaliDate.fromDateTime(now ?? DateTime.now());
    late JalaliDate start;
    late JalaliDate end;
    switch (period) {
      case ReportPeriod.today:
        start = today; end = today.addDays(1); break;
      case ReportPeriod.yesterday:
        start = today.addDays(-1); end = today; break;
      case ReportPeriod.thisWeek:
        start = today.addDays(-today.weekday); end = start.addDays(7); break;
      case ReportPeriod.lastWeek:
        end = today.addDays(-today.weekday); start = end.addDays(-7); break;
      case ReportPeriod.thisMonth:
        start = JalaliDate(today.year, today.month, 1); end = start.addMonths(1); break;
      case ReportPeriod.lastMonth:
        end = JalaliDate(today.year, today.month, 1); start = end.addMonths(-1); break;
      case ReportPeriod.thisYear:
        start = JalaliDate(today.year, 1, 1); end = JalaliDate(today.year + 1, 1, 1); break;
      case ReportPeriod.custom:
        start = today; end = today.addDays(1); break;
    }
    return ReportDateRange(period: period, start: start.toDateTime(), endExclusive: end.toDateTime());
  }

  factory ReportDateRange.custom(JalaliDate from, JalaliDate to) {
    if (to.isBefore(from)) throw ArgumentError('تاریخ پایان نمی‌تواند قبل از تاریخ شروع باشد.');
    return ReportDateRange(
      period: ReportPeriod.custom,
      start: from.toDateTime(),
      endExclusive: to.addDays(1).toDateTime(),
    );
  }

  JalaliDate get jalaliStart => JalaliDate.fromDateTime(start);
  JalaliDate get jalaliEnd => JalaliDate.fromDateTime(endExclusive.subtract(const Duration(days: 1)));
  String get label => '${jalaliStart.short} تا ${jalaliEnd.short}';
  bool contains(DateTime value) => !value.isBefore(start) && value.isBefore(endExclusive);
}

class ReportTrendPoint {
  const ReportTrendPoint({required this.label, required this.start, required this.revenue, required this.cost, required this.appointments});
  final String label;
  final DateTime start;
  final num revenue;
  final num cost;
  final int appointments;
}

class ReportEmployeeMetric {
  const ReportEmployeeMetric({required this.employeeId, required this.name, required this.revenue, required this.commission});
  final String employeeId;
  final String name;
  final num revenue;
  final num commission;
}

class ReportAnalyticsFilter {
  const ReportAnalyticsFilter({this.serviceId, this.employeeId, this.customerId, this.status});
  final String? serviceId, employeeId, customerId;
  final AppointmentStatus? status;
  bool get isEmpty => serviceId == null && employeeId == null && customerId == null && status == null;
  bool matches(Appointment item) =>
    (serviceId == null || item.serviceIds.contains(serviceId)) &&
    (employeeId == null || item.employeeId == employeeId) &&
    (customerId == null || item.customerId == customerId) &&
    (status == null || item.status == status);

  ReportAnalyticsFilter copyWith({
    String? serviceId, String? employeeId, String? customerId,
    AppointmentStatus? status, bool clearService = false,
    bool clearEmployee = false, bool clearCustomer = false, bool clearStatus = false,
  }) => ReportAnalyticsFilter(
    serviceId: clearService ? null : (serviceId ?? this.serviceId),
    employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
    customerId: clearCustomer ? null : (customerId ?? this.customerId),
    status: clearStatus ? null : (status ?? this.status),
  );
}

class ReportServiceMetric {
  const ReportServiceMetric({
    required this.name, required this.revenue, required this.count,
    this.serviceId = '', this.averagePrice = 0, this.directCost,
    this.profit, this.marginPercent, this.employeeCounts = const {},
  });
  final String serviceId, name;
  final num revenue, averagePrice;
  final int count;
  /// null یعنی حداقل یکی از نوبت‌های تاریخی این خدمت هزینه مستقیم ثبت‌شده ندارد.
  final num? directCost, profit, marginPercent;
  final Map<String, int> employeeCounts;
}

class ReportCustomerMetric {
  const ReportCustomerMetric({
    required this.customerId, required this.name, required this.visits, required this.lifetimeVisits,
    required this.totalSpent, required this.averageSpend, required this.lastVisitAt,
    required this.firstVisitAt, required this.averageGapDays, required this.isNew,
    required this.isLoyal, required this.isInactive, required this.isAtRisk,
    required this.repeatVisits,
  });
  final String customerId, name;
  final int visits, lifetimeVisits, repeatVisits;
  final num totalSpent, averageSpend;
  final DateTime? firstVisitAt, lastVisitAt;
  final double? averageGapDays;
  final bool isNew, isLoyal, isInactive, isAtRisk;
}

class ReportHourMetric {
  const ReportHourMetric({required this.hour, required this.appointments, required this.scheduledMinutes, required this.bookedMinutes});
  final int hour, appointments, scheduledMinutes, bookedMinutes;
}

class ReportWeekdayMetric {
  const ReportWeekdayMetric({required this.weekday, required this.label, required this.appointments});
  final int weekday;
  final String label;
  final int appointments;
}

class ReportCustomerDebt {
  const ReportCustomerDebt({required this.customerId, required this.customerName, required this.amount, required this.appointmentCount});
  final String customerId, customerName;
  final int amount, appointmentCount;
}

class ReportAnalytics {
  const ReportAnalytics({
    required this.range, required this.revenue, required this.cost,
    required this.commissionCost, required this.payrollCost,
    required this.totalAppointments, required this.completedAppointments,
    required this.cancelledAppointments, required this.noShowAppointments,
    required this.uniqueCustomers, required this.statusCounts, required this.trend,
    required this.employees, required this.services, required this.recentAppointments,
    required this.recentTransactions, required this.costNote,
    this.grossRevenue = 0, this.collectedRevenue = 0, this.receivables = 0,
    this.operatingExpense = 0, this.staffPayable = 0, this.staffPaid = 0,
    this.advancesOutstanding = 0, this.profitMarginPercent = 0,
    this.grossProfit, this.previousPeriodRevenue = 0, this.previousPeriodCost = 0,
    this.paymentsByMethod = const {}, this.expensesByCategory = const {},
    this.customerDebts = const [], this.partialPayments = const [],
    this.paymentTransactions = const [], this.businessExpenses = const [],
    this.settlements = const [],
    this.operationalAppointments = const [],
    this.customerMetrics = const [],
    this.hourlyDemand = const [],
    this.weekdayDemand = const [],
    this.repeatCustomerRate = 0,
    this.newCustomers = 0,
    this.oldCustomers = 0,
    this.loyalCustomers = 0,
    this.inactiveCustomers = 0,
    this.atRiskCustomers = 0,
    this.rejectedAppointments = 0,
    this.capacityMinutes = 0,
    this.bookedCapacityMinutes = 0,
    this.directCostCoveragePercent = 0,
    this.filter = const ReportAnalyticsFilter(),
  });
  final ReportDateRange range;
  final num revenue, cost, commissionCost, payrollCost;
  final int totalAppointments, completedAppointments, cancelledAppointments, noShowAppointments, uniqueCustomers;
  final Map<String, int> statusCounts;
  final List<ReportTrendPoint> trend;
  final List<ReportEmployeeMetric> employees;
  final List<ReportServiceMetric> services;
  final List<Appointment> recentAppointments;
  final List<EmployeeWalletTransaction> recentTransactions;
  final String costNote;
  final num grossRevenue, collectedRevenue, receivables, operatingExpense;
  final num staffPayable, staffPaid, advancesOutstanding, profitMarginPercent;
  final num? grossProfit;
  final num previousPeriodRevenue, previousPeriodCost;
  final Map<String, num> paymentsByMethod, expensesByCategory;
  final List<ReportCustomerDebt> customerDebts;
  final List<AppointmentPayment> partialPayments, paymentTransactions;
  final List<BusinessExpense> businessExpenses;
  final List<EmployeeWalletSettlement> settlements;
  final List<Appointment> operationalAppointments;
  final List<ReportCustomerMetric> customerMetrics;
  final List<ReportHourMetric> hourlyDemand;
  final List<ReportWeekdayMetric> weekdayDemand;
  final num repeatCustomerRate;
  final int newCustomers, oldCustomers, loyalCustomers, inactiveCustomers, atRiskCustomers;
  /// در مدل فعلی وضعیت مستقل «ردشده» وجود ندارد؛ مقدار صفر به‌معنی عدم پشتیبانی وضعیت است.
  final int rejectedAppointments;
  final int capacityMinutes, bookedCapacityMinutes;
  final num directCostCoveragePercent;
  final ReportAnalyticsFilter filter;
  num get netProfit => revenue - cost;
  num get netRevenue => revenue;
  num get discounts => grossRevenue - revenue;
  num get capacityUtilizationPercent => capacityMinutes <= 0 ? 0 : bookedCapacityMinutes * 100 / capacityMinutes;
  int get emptyCapacityMinutes => (capacityMinutes - bookedCapacityMinutes).clamp(0, capacityMinutes);

  static ReportAnalytics empty(ReportDateRange range) => ReportAnalytics(
    range: range, revenue: 0, cost: 0, commissionCost: 0, payrollCost: 0,
    totalAppointments: 0, completedAppointments: 0, cancelledAppointments: 0,
    noShowAppointments: 0, uniqueCustomers: 0, statusCounts: const {},
    trend: const [], employees: const [], services: const [],
    recentAppointments: const [], recentTransactions: const [],
    costNote: 'هزینه‌ها فقط از اسناد مالی ثبت‌شده محاسبه می‌شوند.',
  );
}
