import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/employee_analytics.dart';
import 'package:datetime/data/models/enums.dart';

void main() {
  group('EmployeeAnalyticsCalculator', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase());
    tearDown(() => db.dispose());

    test('calculates counts and financial totals from mock appointments and ledger', () {
      final employee = db.employees.first;
      final now = DateTime.now();
      final filter = EmployeeAnalyticsFilter(
        from: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30)),
        to: DateTime(now.year, now.month, now.day).add(const Duration(days: 16)),
      );
      final report = EmployeeAnalyticsCalculator.calculate(db: db, employee: employee, filter: filter);
      final expected = db.appointments.where((a) =>
        a.employeeId == employee.id &&
        !a.startAt.isBefore(filter.from) &&
        a.startAt.isBefore(filter.to)
      ).toList();

      expect(report.totalAppointments, expected.length);
      expect(report.completed, expected.where((a) => a.status == AppointmentStatus.completed).length);
      expect(report.cancelled, expected.where((a) => a.status == AppointmentStatus.cancelled).length);
      expect(report.noShow, expected.where((a) => a.status == AppointmentStatus.noShow).length);
      expect(report.netRevenue, greaterThanOrEqualTo(0));
      expect(report.commission, greaterThanOrEqualTo(0));
      expect(report.companyShare + report.commission, report.netRevenue);
      expect(report.utilizationRate, inInclusiveRange(0, 100));
    });

    test('status and service filters change the underlying appointment series', () {
      final employee = db.employees.first;
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
      final to = DateTime(now.year, now.month, now.day).add(const Duration(days: 16));
      final all = EmployeeAnalyticsCalculator.calculate(
        db: db, employee: employee, filter: EmployeeAnalyticsFilter(from: from, to: to),
      );
      final completed = EmployeeAnalyticsCalculator.calculate(
        db: db, employee: employee,
        filter: EmployeeAnalyticsFilter(from: from, to: to, status: AppointmentStatus.completed),
      );
      expect(completed.totalAppointments, completed.completed);
      expect(completed.totalAppointments, lessThanOrEqualTo(all.totalAppointments));

      if (employee.serviceIds.isNotEmpty) {
        final service = EmployeeAnalyticsCalculator.calculate(
          db: db, employee: employee,
          filter: EmployeeAnalyticsFilter(from: from, to: to, serviceId: employee.serviceIds.first),
        );
        expect(service.totalAppointments, lessThanOrEqualTo(all.totalAppointments));
      }
    });

    test('daily and monthly chart points are derived from the selected date range', () {
      final employee = db.employees.first;
      final start = DateTime.now().subtract(const Duration(days: 6));
      final report = EmployeeAnalyticsCalculator.calculate(
        db: db, employee: employee,
        filter: EmployeeAnalyticsFilter(
          from: DateTime(start.year, start.month, start.day),
          to: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      expect(report.dailyRevenue, hasLength(7));
      expect(report.dailyAppointments, hasLength(7));
      expect(report.monthlyRevenue, isNotEmpty);
    });
  });
}
