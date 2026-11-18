import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/appointment.dart';
import 'package:datetime/data/models/customer.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/report_analytics.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';

void main() {
  group('Datamonck service, customer and appointment reports', () {
    test('status changes, service price snapshots, repeat visits and direct costs stay consistent', () async {
      final db = AppDatabase();
      final now = DateTime.now();
      final customer = Customer(
        id: 'phase4-customer', fullName: 'مشتری آزمون فاز چهار',
        phone: '09000000000', createdAt: now.subtract(const Duration(days: 5)),
      );
      db.addCustomer(customer);

      final employee = db.employees.first;
      var service = db.services.first.copyWith(price: 600000, directCost: 150000);
      db.updateService(service);
      final template = db.appointments.first;

      Appointment makeAppointment(String id, DateTime date, {required AppointmentStatus status}) => template.copyWith(
        id: id, reference: 'P4-$id', customerId: customer.id,
        customerName: customer.fullName, customerPhone: customer.phone,
        serviceIds: [service.id], serviceName: service.title,
        employeeId: employee.id, employeeName: employee.fullName,
        startAt: date, durationMinutes: service.durationMinutes,
        status: status, price: service.price, createdAt: date,
        serviceSnapshots: [{
          'service_id': service.id, 'title': service.title,
          'price': service.price, 'direct_cost': service.directCost,
        }],
      );

      final first = makeAppointment('p4-first', now.subtract(const Duration(days: 4)), status: AppointmentStatus.pending);
      db.addAppointment(first);
      db.changeStatus(first, AppointmentStatus.completed);

      // قیمت خدمت بعد از اولین ارائه تغییر می‌کند؛ نوبت اول باید قیمت تاریخی خود را حفظ کند.
      service = service.copyWith(price: 700000);
      db.updateService(service);
      final second = makeAppointment('p4-second', now.subtract(const Duration(days: 2)), status: AppointmentStatus.pending);
      db.addAppointment(second);
      db.changeStatus(second, AppointmentStatus.completed);

      final cancelled = makeAppointment('p4-cancelled', now.subtract(const Duration(days: 1)), status: AppointmentStatus.pending);
      db.addAppointment(cancelled);
      db.changeStatus(cancelled, AppointmentStatus.cancelled, reason: 'درخواست مشتری');

      final noShow = makeAppointment('p4-no-show', now.subtract(const Duration(days: 1, hours: 2)), status: AppointmentStatus.pending);
      db.addAppointment(noShow);
      db.changeStatus(noShow, AppointmentStatus.noShow);

      expect(db.customerById(customer.id)!.visitCount, 2);
      expect(db.customerById(customer.id)!.cancelCount, 1);
      expect(db.customerById(customer.id)!.noShowCount, 1);

      final range = ReportDateRange.custom(
        JalaliDate.fromDateTime(now.subtract(const Duration(days: 7))),
        JalaliDate.fromDateTime(now),
      );
      final filter = ReportAnalyticsFilter(
        serviceId: service.id, employeeId: employee.id, customerId: customer.id,
      );
      final report = await MockDashboardRepository(db).fetchReportAnalytics(range: range, filter: filter);

      expect(report.operationalAppointments, hasLength(4));
      expect(report.operationalStatusCounts[AppointmentStatus.completed.label], 2);
      expect(report.operationalStatusCounts[AppointmentStatus.cancelled.label], 1);
      expect(report.operationalStatusCounts[AppointmentStatus.noShow.label], 1);
      expect(report.services, hasLength(1));
      expect(report.services.single.count, 2);
      expect(report.services.single.averagePrice, 650000);
      expect(report.services.single.directCost, 300000);
      expect(report.services.single.profit, report.services.single.revenue - 300000);
      expect(report.services.single.employeeCounts[employee.fullName], 2);
      expect(report.services.single.trend, hasLength(2));
      expect(report.weekdayDemand, hasLength(7));
      expect(report.customerMetrics.single.customerId, customer.id);
      expect(report.customerMetrics.single.lifetimeVisits, 2);
      expect(report.customerMetrics.single.repeatVisits, 1);
      expect(report.newCustomers, 1);
      expect(report.repeatCustomerRate, 100);
      expect(report.rejectedAppointments, 0);
    });

    test('status and service filters only narrow operational tables, not financial totals', () async {
      final db = AppDatabase();
      final repository = MockDashboardRepository(db);
      final range = ReportDateRange.custom(
        JalaliDate.fromDateTime(DateTime(2000, 1, 1)),
        JalaliDate.fromDateTime(DateTime(2100, 1, 1)),
      );
      final all = await repository.fetchReportAnalytics(range: range);
      final serviceId = db.services.first.id;
      final filtered = await repository.fetchReportAnalytics(
        range: range,
        filter: ReportAnalyticsFilter(serviceId: serviceId, status: AppointmentStatus.completed),
      );
      expect(filtered.operationalAppointments.every((item) =>
        item.serviceIds.contains(serviceId) && item.status == AppointmentStatus.completed), isTrue);
      expect(filtered.operationalAppointments.length, lessThanOrEqualTo(all.operationalAppointments.length));
      expect(filtered.revenue, all.revenue);
      expect(filtered.cost, all.cost);
    });
  });
}
