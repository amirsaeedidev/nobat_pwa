import '../../core/utils/jalali.dart';
import '../mock/app_database.dart';
import '../models/appointment.dart';
import '../models/dashboard_stats.dart';
import '../models/enums.dart';

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
    final periodItems = all.where((a) {
      if (period == StatsPeriod.daily) return a.jalali.sameDay(today);
      return !a.jalali.isBefore(periodStart);
    }).toList();

    final completed = periodItems.where((a) => a.status == AppointmentStatus.completed);
    final cancelled = periodItems.where((a) => a.status == AppointmentStatus.cancelled || a.status == AppointmentStatus.noShow);

    final totalRevenue = periodItems
        .where((a) => a.status == AppointmentStatus.completed)
        .fold<num>(0, (sum, a) => sum + a.price);

    final monthStart = JalaliDate(today.year, today.month, 1);
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
}
