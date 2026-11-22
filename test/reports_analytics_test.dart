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
      final expectedRevenue = db.employeeFinanceEntries.fold<int>(0, (sum, item) => sum + item.receivedAmount);
      expect(report.totalAppointments, db.appointments.length);
      expect(report.completedAppointments, completed.length);
      expect(report.revenue, expectedRevenue);
      expect(report.cost, report.commissionCost + report.payrollCost + report.operatingExpense);
      expect(report.netProfit, report.revenue - report.cost);
      expect(report.statusCounts.values.fold<int>(0, (sum, value) => sum + value), report.totalAppointments);
      expect(report.trend, isNotEmpty);
      expect(report.services, isNotEmpty);
    });

    test('combined filters match service category, customer, staff and appointment status', () {
      final db = AppDatabase();
      final source = db.appointments.first;
      final service = db.services.first;
      final item = source.copyWith(
        serviceIds: [service.id],
        employeeId: db.employees.first.id,
        customerId: db.customers.first.id,
        status: AppointmentStatus.completed,
      );
      const filter = ReportAnalyticsFilter(
        serviceId: 'service-id-placeholder',
        category: 'دسته تست',
        employeeId: 'employee-id-placeholder',
        customerId: 'customer-id-placeholder',
        status: AppointmentStatus.completed,
      );
      expect(filter.matches(item, serviceCategories: {'دسته تست'}), isFalse);
      final valid = ReportAnalyticsFilter(
        serviceId: service.id,
        category: service.category,
        employeeId: item.employeeId,
        customerId: item.customerId,
        status: AppointmentStatus.completed,
      );
      expect(valid.matches(item, serviceCategories: {service.category}), isTrue);
      expect(valid.copyWith(clearCategory: true).category, isNull);
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

    test('dashboard and report monthly revenue reconcile to the same finance ledger', () async {
      final db = AppDatabase();
      final repository = MockDashboardRepository(db);
      final report = await repository.fetchReportAnalytics(
        range: ReportDateRange.preset(ReportPeriod.thisMonth),
      );
      final dashboard = await repository.fetchStats(period: StatsPeriod.monthly);
      final series = await repository.fetchRevenueSeries(months: 1);
      expect(dashboard.totalRevenue, report.revenue);
      expect(dashboard.monthRevenue, report.revenue);
      expect(series.single.value, report.revenue);

      final allTime = await repository.fetchReportAnalytics(range: ReportDateRange.custom(
        JalaliDate(1400, 1, 1), JalaliDate(1450, 1, 1),
      ));
      final services = await repository.fetchServiceRevenue(limit: 100);
      expect(services.fold<num>(0, (sum, item) => sum + item.value), allTime.revenue);
    });

    test('accountant sees financial ledgers but not operational or customer details', () async {
      final db = AppDatabase();
      db.switchMockAccount('demo-accountant');
      final range = ReportDateRange.custom(
        JalaliDate(1400, 1, 1),
        JalaliDate(1450, 1, 1),
      );
      final report = await MockDashboardRepository(db).fetchReportAnalytics(range: range);
      expect(report.revenue, greaterThan(0));
      expect(report.employees, isNotEmpty);
      expect(report.walletTransactions, isNotEmpty);
      expect(report.operationalAppointments, isEmpty);
      expect(report.customerMetrics, isEmpty);
      expect(report.customerDebts, isEmpty);
      expect(report.totalAppointments, 0);
      expect(report.uniqueCustomers, 0);
    });

    test('blocks report access without income permission', () async {
      final db = AppDatabase();
      db.switchMockAccount('demo-operator');
      final repository = MockDashboardRepository(db);
      final range = ReportDateRange.preset(ReportPeriod.thisMonth);
      await expectLater(repository.fetchReportAnalytics(range: range), throwsA(isA<AccessDeniedException>()));
    });
  });
}
