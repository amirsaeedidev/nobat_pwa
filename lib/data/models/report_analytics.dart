import '../core/utils/jalali.dart';
import 'appointment.dart';
import 'employee_wallet.dart';

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

class ReportServiceMetric {
  const ReportServiceMetric({required this.name, required this.revenue, required this.count});
  final String name;
  final num revenue;
  final int count;
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
  num get netProfit => revenue - cost;

  static ReportAnalytics empty(ReportDateRange range) => ReportAnalytics(
    range: range, revenue: 0, cost: 0, commissionCost: 0, payrollCost: 0,
    totalAppointments: 0, completedAppointments: 0, cancelledAppointments: 0,
    noShowAppointments: 0, uniqueCustomers: 0, statusCounts: const {},
    trend: const [], employees: const [], services: const [],
    recentAppointments: const [], recentTransactions: const [],
    costNote: 'هزینه‌ها فقط از اسناد مالی ثبت‌شده محاسبه می‌شوند.',
  );
}
