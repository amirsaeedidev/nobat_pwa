import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/report_analytics.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';

void main() {
  group('Datamonck report analytics', () {
    test('aggregates appointments, revenue, costs and profit from shared data', () async {
      final db = AppDatabase();
      final repository = MockDashboardRepository(db);
      final range = ReportDateRange.custom(
        JalaliDate.fromDateTime(DateTime(2000, 1, 1)),
        JalaliDate.fromDateTime(DateTime(2100, 1, 1)),
      );
      final report = await repository.fetchReportAnalytics(range: range);
      final completed = db.appointments.where((item) => item.status == AppointmentStatus.completed);
      final expectedRevenue = completed.fold<num>(0, (sum, item) => sum + item.price);
      expect(report.totalAppointments, db.appointments.length);
      expect(report.completedAppointments, completed.length);
      expect(report.revenue, expectedRevenue);
      expect(report.cost, report.commissionCost + report.payrollCost);
      expect(report.netProfit, report.revenue - report.cost);
      expect(report.statusCounts.values.fold<int>(0, (sum, value) => sum + value), report.totalAppointments);
      expect(report.trend, isNotEmpty);
      expect(report.services, isNotEmpty);
    });

    test('custom range includes both selected Jalali dates', () {
      final from = JalaliDate(1405, 8, 1);
      final to = JalaliDate(1405, 8, 3);
      final range = ReportDateRange.custom(from, to);
      expect(range.contains(from.toDateTime()), isTrue);
      expect(range.contains(to.toDateTime()), isTrue);
      expect(range.contains(to.addDays(1).toDateTime()), isFalse);
      expect(range.endExclusive.difference(range.start).inDays, 3);
    });

    test('blocks report access without income permission', () async {
      final db = AppDatabase();
      db.switchMockAccount('demo-operator');
      final repository = MockDashboardRepository(db);
      final range = ReportDateRange.preset(ReportPeriod.thisMonth);
      expect(() => repository.fetchReportAnalytics(range: range), throwsA(isA<AccessDeniedException>()));
    });
  });
}
