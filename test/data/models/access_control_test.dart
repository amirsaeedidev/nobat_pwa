import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/repositories/appointment_repository.dart';
import 'package:datetime/data/repositories/employee_repository.dart';

void main() {
  group('Mock role-based access control', () {
    test('seeds the six expected demo roles and accounts offline', () {
      final db = AppDatabase();
      expect(db.accessRoles.map((role) => role.id), containsAll([
        'global_admin', 'manager', 'operator', 'staff', 'accountant', 'custom_limited',
      ]));
      expect(db.accessAccounts.length, greaterThanOrEqualTo(6));
      expect(db.currentAccessAccount.roleId, 'global_admin');
    });

    test('global admin can manage roles and access every protected section', () {
      final db = AppDatabase();
      expect(db.hasPermission('permissions.manage'), isTrue);
      db.switchMockAccount('demo-manager');
      expect(db.hasPermission('permissions.manage'), isTrue);
      expect(db.canOpenRoute('/settings/permissions'), isTrue);
      expect(db.canOpenRoute('/employees/new'), isTrue);
    });

    test('operator has appointment operations but cannot deactivate staff or manage roles', () {
      final db = AppDatabase()..switchMockAccount('demo-operator');
      expect(db.hasPermission('appointments.create'), isTrue);
      expect(db.hasPermission('employees.deactivate'), isFalse);
      expect(db.hasPermission('permissions.manage'), isFalse);
      expect(db.canOpenRoute('/appointments/new'), isTrue);
      expect(db.canOpenRoute('/employees/new'), isFalse);
      expect(db.canOpenRoute('/settings/permissions'), isFalse);
      expect(() => db.deleteEmployee('emp-sara'), throwsA(isA<AccessDeniedException>()));
      expect(() => db.updateSettings(db.settings, logTitle: 'تغییر ساعت کاری'), throwsA(isA<AccessDeniedException>()));
    });

    test('staff can see own income and own appointments only', () async {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      expect(db.hasPermission('appointments.view_self'), isTrue);
      expect(db.hasPermission('appointments.view_all'), isFalse);
      expect(db.canViewEmployeeIncome('emp-zahra'), isTrue);
      expect(db.canViewEmployeeIncome('emp-shima'), isFalse);
      expect(() => db.addCustomer(db.customers.first), throwsA(isA<AccessDeniedException>()));
      final other = db.appointments.firstWhere((item) => item.employeeId != 'emp-zahra');
      expect(db.canOpenRoute('/appointments/${other.id}'), isFalse);
      final repository = MockAppointmentRepository(db);
      final visible = await repository.fetchAll();
      expect(visible.every((item) => item.employeeId == 'emp-zahra'), isTrue);
    });

    test('staff cannot read another employee attendance, leave, documents or notices directly', () {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      expect(() => db.attendanceFor('emp-shima'), throwsA(isA<AccessDeniedException>()));
      expect(() => db.attendanceSummary('emp-shima', from: DateTime(2026, 1, 1), to: DateTime(2026, 2, 1)),
          throwsA(isA<AccessDeniedException>()));
      expect(() => db.documentsFor('emp-shima'), throwsA(isA<AccessDeniedException>()));
      expect(() => db.leavesForEmployee('emp-shima'), throwsA(isA<AccessDeniedException>()));
      expect(() => db.noticesFor('emp-shima'), throwsA(isA<AccessDeniedException>()));
      expect(db.attendanceFor('emp-zahra').every((row) => row.employeeId == 'emp-zahra'), isTrue);
    });

    test('accountant can view financial data and settlements but cannot change roles', () {
      final db = AppDatabase()..switchMockAccount('demo-accountant');
      expect(db.hasPermission('finance.income.view'), isTrue);
      expect(db.hasPermission('finance.settlement.view'), isTrue);
      expect(db.canViewEmployeeIncome('emp-shima'), isTrue);
      expect(db.hasPermission('permissions.manage'), isFalse);
    });

    test('custom role and explicit deny override are enforced', () {
      final db = AppDatabase();
      db.assignEmployeeAccess(
        employeeId: 'emp-amir',
        roleId: 'custom_limited',
        overrides: const {'appointments.view_self': false, 'customers.create': true},
      );
      db.switchMockAccount('demo-custom');
      expect(db.hasPermission('appointments.view_self'), isFalse);
      expect(db.hasPermission('customers.create'), isTrue);
      expect(db.hasPermission('customers.view'), isTrue);
    });

    test('custom roles can be created and edited only by an authorized account', () {
      final db = AppDatabase();
      db.createAccessRole(name: 'پذیرش محدود', permissionIds: const ['appointments.view_all']);
      final role = db.accessRoles.firstWhere((item) => item.name == 'پذیرش محدود');
      db.updateAccessRole(role.id, name: 'پذیرش ویژه', permissionIds: const ['appointments.view_all', 'customers.view']);
      expect(db.accessRoleById(role.id)!.permissionIds, contains('customers.view'));
      db.switchMockAccount('demo-staff');
      expect(() => db.createAccessRole(name: 'غیرمجاز', permissionIds: const []), throwsA(isA<AccessDeniedException>()));
    });

    test('employee repository limits a staff account to its own profile', () async {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      final repository = MockEmployeeRepository(db);
      final employees = await repository.fetchEmployees();
      expect(employees.map((employee) => employee.id), ['emp-zahra']);
      expect(await repository.findById('emp-shima'), isNull);
    });

    test('personal income and other employee visibility can be revoked per person', () {
      final db = AppDatabase();
      db.assignEmployeeAccess(
        employeeId: 'emp-shima',
        roleId: 'manager',
        canViewOtherEmployees: false,
        canViewPersonalIncome: false,
      );
      db.switchMockAccount('demo-manager');
      expect(db.canViewEmployee('emp-zahra'), isFalse);
      expect(db.canViewEmployeeIncome('emp-shima'), isFalse);
    });
  });
}
