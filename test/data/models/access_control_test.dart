import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/repositories/appointment_repository.dart';
import 'package:datetime/data/models/employee_payroll.dart';
import 'package:datetime/data/models/employee_wallet.dart';

void main() {
  group('Two-role access control', () {
    test('only global admin and personnel roles are seeded', () {
      final db = AppDatabase();
      expect(db.accessRoles.map((role) => role.id).toSet(), {'global_admin', 'staff'});
      expect(db.accessAccounts.map((account) => account.roleId).toSet(), {'global_admin', 'staff'});
      expect(db.currentAccessAccount.roleId, 'global_admin');
    });

    test('global admin has unrestricted access and manages personnel permissions', () {
      final db = AppDatabase();
      expect(db.hasPermission('permissions.manage'), isTrue);
      expect(db.hasPermission('employees.deactivate'), isTrue);
      expect(db.hasPermission('finance.income.view'), isTrue);
      expect(db.canOpenRoute('/settings/permissions'), isTrue);
      expect(db.canOpenRoute('/services'), isTrue);
    });

    test('personnel receives only personal appointment and wallet actions', () {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      for (final permission in [
        'appointments.view_self',
        'appointments.confirm',
        'appointments.reject',
        'appointments.create',
        'appointments.edit',
        'appointments.cancel',
        'appointments.complete',
        'finance.wallet.view',
        'finance.commission.view',
        'finance.advance.request',
        'finance.settlement.request',
        'employees.leave.request',
      ]) {
        expect(db.hasPermission(permission), isTrue, reason: permission);
      }
      expect(db.hasPermission('permissions.manage'), isFalse);
      expect(db.hasPermission('appointments.view_all'), isFalse);
      expect(db.hasPermission('finance.income.view'), isFalse);
      expect(db.canOpenRoute('/settings/permissions'), isFalse);
      expect(db.canOpenRoute('/services'), isFalse);
      expect(db.canOpenRoute('/employees'), isFalse);
      expect(db.canOpenRoute('/employees/emp-zahra/leaves'), isTrue);
      expect(db.canOpenRoute('/employees/emp-zahra/schedule'), isFalse);
      expect(db.canOpenRoute('/dashboard'), isFalse);
      expect(db.canOpenRoute('/search'), isFalse);
      expect(db.canOpenRoute('/my-wallet'), isTrue);
      expect(db.employees.map((employee) => employee.id).toSet(), {'emp-zahra'});
      expect(db.appointments.every((appointment) => appointment.employeeId == 'emp-zahra'), isTrue);
    });

    test('personnel appointment repository only returns own appointments', () async {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      final repository = MockAppointmentRepository(db);
      final visible = await repository.fetchAll();
      expect(visible.every((item) => item.employeeId == 'emp-zahra'), isTrue);
    });

    test('public booking routes are disabled', () {
      final db = AppDatabase();
      expect(db.canOpenRoute('/book'), isFalse);
      expect(db.canOpenRoute('/book/manage'), isFalse);
    });

    test('personnel can request an advance but cannot post a paid advance', () {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      db.addPayrollAdvance(PayrollAdvance(
        id: 'advance-request-test',
        employeeId: 'emp-zahra',
        amount: 500000,
        requestedAt: DateTime(2026, 11, 23),
        description: 'درخواست مساعده آزمایشی',
        status: AdvanceStatus.requested,
      ));
      expect(db.payrollAdvances.single.status, AdvanceStatus.requested);
      expect(
        () => db.addPayrollAdvance(PayrollAdvance(
          id: 'advance-paid-test',
          employeeId: 'emp-zahra',
          amount: 500000,
          requestedAt: DateTime(2026, 11, 23),
          paidAt: DateTime(2026, 11, 23),
          description: 'ثبت پرداخت مستقیم',
          status: AdvanceStatus.paid,
        )),
        throwsA(isA<AccessDeniedException>()),
      );
    });

    test('personnel can submit a settlement request and manager can review it', () {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      final available = db.walletSummaryFor('emp-zahra').payableBalance;
      expect(available, greaterThan(0));
      final available = db.walletSummaryFor('emp-zahra').payableBalance;
      expect(available, greaterThan(0));
      db.requestWalletSettlement(EmployeeWalletSettlementRequest(
        id: 'settlement-request-test',
        employeeId: 'emp-zahra',
        requestedAt: DateTime(2026, 11, 23),
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 23, 23, 59),
        amount: available,
        description: 'درخواست تسویه آزمایشی',
      ));
      expect(db.walletSettlementRequestsFor('emp-zahra'), hasLength(1));
      expect(
        () => db.walletSettlementRequestsFor('emp-shima'),
        throwsA(isA<AccessDeniedException>()),
      );
      db.switchMockAccount('demo-global-admin');
      db.reviewWalletSettlementRequest('settlement-request-test', EmployeeWalletRequestStatus.approved);
      expect(
        db.walletSettlementRequestsFor('emp-zahra').single.status,
        EmployeeWalletRequestStatus.approved,
      );
    });
  });
}
