import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/repositories/appointment_repository.dart';
import 'package:datetime/data/repositories/customer_repository.dart';
import 'package:datetime/data/repositories/employee_repository.dart';
import 'package:datetime/data/repositories/service_repository.dart';

void main() {
  group('Datamonck offline startup', () {
    test('local database seeds the core modules synchronously', () {
      final database = AppDatabase();

      expect(database.customers, isNotEmpty);
      expect(database.employees, isNotEmpty);
      expect(database.services, isNotEmpty);
      expect(database.appointments, isNotEmpty);
    });

    test('core repositories read local mock data without a remote service', () async {
      final database = AppDatabase();

      final customers = await MockCustomerRepository(database).fetchAll();
      final employees = await MockEmployeeRepository(database).fetchEmployees();
      final services = await MockServiceRepository(database).fetchServices(onlyActive: true);
      final appointments = await MockAppointmentRepository(database).fetchAll();

      expect(customers, isNotEmpty);
      expect(employees, isNotEmpty);
      expect(services, isNotEmpty);
      expect(appointments, isNotEmpty);
    });
  });
}
