import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/repositories/supabase_core_repositories.dart';

void main() {
  group('Core repositories fail closed without Supabase', () {
    test('appointments do not fall back to local records', () async {
      final repository = UnavailableAppointmentRepository();
      await expectLater(repository.fetchAll(), throwsA(isA<StateError>()));
      await expectLater(repository.fetchAppointments(), throwsA(isA<StateError>()));
    });

    test('customers do not fall back to local records', () async {
      final repository = UnavailableCustomerRepository();
      await expectLater(repository.fetchAll(), throwsA(isA<StateError>()));
      await expectLater(repository.fetchCustomers(), throwsA(isA<StateError>()));
    });

    test('services do not fall back to local records', () async {
      final repository = UnavailableServiceRepository();
      await expectLater(repository.fetchServices(), throwsA(isA<StateError>()));
      await expectLater(repository.fetchCategories(), throwsA(isA<StateError>()));
    });

    test('employees do not fall back to local records', () async {
      final repository = UnavailableEmployeeRepository();
      await expectLater(repository.fetchEmployees(), throwsA(isA<StateError>()));
    });
  });
}
