import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/employee_service_config.dart';
import 'package:datetime/data/models/appointment.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/service.dart';

void main() {
  group('EmployeeServiceConfig', () {
    test('serializes employee-specific settings without losing nullable defaults', () {
      const config = EmployeeServiceConfig(
        employeeId: 'emp-test',
        serviceId: 'srv-test',
        customPrice: 125000,
        customDurationMinutes: 75,
        commissionRateBps: 2500,
        fixedCommissionAmount: 5000,
        specialtyNote: 'مهارت آزمایشی',
      );
      final restored = EmployeeServiceConfig.fromJson(config.toJson());
      expect(restored.employeeId, 'emp-test');
      expect(restored.customPrice, 125000);
      expect(restored.customDurationMinutes, 75);
      expect(restored.commissionRateBps, 2500);
      expect(restored.fixedCommissionAmount, 5000);
      expect(restored.active, isTrue);
    });

    test('database applies custom price, duration and commission and excludes disabled services', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final service = db.services.first;
      db.saveEmployeeServiceConfig(EmployeeServiceConfig(
        employeeId: employee.id,
        serviceId: service.id,
        customPrice: 230000,
        customDurationMinutes: 80,
        commissionRateBps: 2750,
        fixedCommissionAmount: 3000,
      ));
      expect(db.employeeOffersService(employee.id, service.id), isTrue);
      expect(db.effectiveServicePrice(employee.id, service.id), 230000);
      expect(db.effectiveServiceDuration(employee.id, service.id), 80);
      expect(db.employeeServiceConfig(employee.id, service.id)?.commissionRateBps, 2750);

      db.saveEmployeeServiceConfig(EmployeeServiceConfig(
        employeeId: employee.id,
        serviceId: service.id,
        active: false,
      ));
      expect(db.employeeOffersService(employee.id, service.id), isFalse);
      expect(db.eligibleEmployeesForService(service.id).any((item) => item.id == employee.id), isFalse);
    });

    test('service with appointment history is archived instead of deleted', () {
      final db = AppDatabase();
      final appointment = db.appointments.first;
      final serviceId = appointment.serviceIds.first;
      final service = db.serviceById(serviceId);
      expect(service, isNotNull);
      db.deleteService(serviceId);
      expect(db.serviceById(serviceId), isNotNull);
      expect(db.serviceById(serviceId)!.isActive, isFalse);
      expect(db.appointments.any((item) => item.id == appointment.id), isTrue);
    });

    test('appointment snapshots keep service-specific price and commission after rules change', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final service = db.services.first;
      db.saveEmployeeServiceConfig(EmployeeServiceConfig(
        employeeId: employee.id,
        serviceId: service.id,
        customPrice: 50000,
        customDurationMinutes: 65,
        commissionRateBps: 4000,
      ));
      final appointment = db.appointments.first.copyWith(
        id: 'apt-service-snapshot-test',
        reference: 'TEST-3',
        employeeId: employee.id,
        employeeName: employee.fullName,
        serviceIds: [service.id],
        serviceName: service.title,
        price: 50000,
        durationMinutes: 65,
        status: AppointmentStatus.confirmed,
        serviceSnapshots: [
          {
            'service_id': service.id,
            'title': service.title,
            'price': 50000,
            'duration_minutes': 65,
            'commission_rate_bps': 4000,
            'fixed_commission_amount': 0,
            'commission_basis': 'afterDiscount',
          },
        ],
      );
      db.addAppointment(appointment);
      db.saveEmployeeServiceConfig(EmployeeServiceConfig(
        employeeId: employee.id,
        serviceId: service.id,
        customPrice: 90000,
        customDurationMinutes: 90,
        commissionRateBps: 1500,
      ));
      db.changeStatus(appointment.copyWith(status: AppointmentStatus.completed), AppointmentStatus.completed);
      final entry = db.financeEntriesFor(employee.id).firstWhere((item) => item.appointmentId == appointment.id);
      expect(entry.grossAmount, 50000);
      expect(entry.rateBps, 4000);
      expect(entry.commissionAmount, 20000);
      expect(db.finalizeCompletedAppointment(appointment.id), isFalse);
    });

    test('newly created services retain their general settings', () {
      final db = AppDatabase();
      final service = Service(id: 'srv-new-test', title: 'خدمت تست', price: 10000, durationMinutes: 25);
      db.addService(service);
      expect(db.serviceById(service.id)?.price, 10000);
    });
  });
}
