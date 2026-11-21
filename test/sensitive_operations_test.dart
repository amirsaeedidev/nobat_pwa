import 'package:flutter_test/flutter_test.dart';

import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/appointment.dart';
import 'package:datetime/data/models/business_finance.dart';
import 'package:datetime/data/models/customer.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/employee.dart';
import 'package:datetime/data/models/service.dart';
import 'package:datetime/data/models/employee_wallet.dart';
import 'package:datetime/data/models/employee_hr.dart';
import 'package:datetime/data/repositories/operations_repository.dart';

void main() {
  late AppDatabase db;
  late OperationsRepository operations;

  setUp(() {
    db = AppDatabase();
    operations = OperationsRepository(db);
  });

  test('customer deletion is audited, idempotent and really undoable', () async {
    const customer = Customer(id: 'operation-customer', fullName: 'مشتری آزمایشی', phone: '09120000000');
    db.addCustomer(customer);

    await operations.deleteCustomer(customer.id);

    expect(db.customerById(customer.id), isNull);
    final audit = operations.latestUndoableLogFor(customer.id);
    expect(audit, isNotNull);
    expect(audit!.operationType, 'customer_delete');
    expect(audit.actor, db.currentAccessAccount.name);
    expect(audit.isReversible, isTrue);
    expect(audit.idempotencyKey, 'customer-delete:${customer.id}');
    expect(db.hasExecutedOperation('customer-delete:${customer.id}'), isTrue);

    expect(operations.undo(audit.id), isTrue);
    expect(db.hasExecutedOperation('customer-delete:${customer.id}'), isFalse);
    expect(db.customerById(customer.id)?.fullName, customer.fullName);
    expect(db.canUndoLog(audit.id), isFalse);
  });

  test('customer with appointment history is archived and restored without orphaning', () async {
    const customer = Customer(id: 'operation-customer-history', fullName: 'مشتری دارای سابقه', phone: '09121111111');
    db.addCustomer(customer);
    final appointment = Appointment(
      id: 'operation-appointment',
      reference: 'OP-001',
      customerId: customer.id,
      customerName: customer.fullName,
      customerPhone: customer.phone,
      serviceIds: const [],
      serviceName: 'خدمت آزمایشی',
      employeeId: db.employees.first.id,
      employeeName: db.employees.first.fullName,
      startAt: DateTime(2026, 11, 25, 10),
      durationMinutes: 30,
      price: 100000,
    );
    db.addAppointment(appointment);

    await operations.deleteCustomer(customer.id);
    expect(db.customerById(customer.id)?.isArchived, isTrue);
    expect(db.appointmentById(appointment.id)?.customerId, customer.id);
    expect(operations.undoLatestForEntity(customer.id), isTrue);
    expect(db.customerById(customer.id)?.isArchived, isFalse);
  });

  test('appointment cancellation restores its exact previous state via undo', () async {
    final appointment = Appointment(
      id: 'operation-cancel-appointment',
      reference: 'OP-002',
      customerId: db.customers.first.id,
      customerName: db.customers.first.fullName,
      customerPhone: db.customers.first.phone,
      serviceIds: const [],
      serviceName: 'خدمت آزمایشی',
      employeeId: db.employees.first.id,
      employeeName: db.employees.first.fullName,
      startAt: DateTime(2026, 11, 26, 11),
      durationMinutes: 30,
      price: 120000,
    );
    db.addAppointment(appointment);

    await operations.cancelAppointment(appointment.id, reason: 'درخواست مشتری');

    expect(db.appointmentById(appointment.id)?.status, AppointmentStatus.cancelled);
    expect(operations.undoLatestForEntity(appointment.id), isTrue);
    expect(db.appointmentById(appointment.id)?.status, AppointmentStatus.pending);
  });

  test('category move and its dependent service references are restored together', () async {
    db.addServiceCategory('عملیات آزمایشی');
    db.addServiceCategory('مقصد آزمایشی');
    const service = Service(
      id: 'operation-service',
      title: 'خدمت وابسته',
      price: 250000,
      durationMinutes: 45,
      category: 'عملیات آزمایشی',
    );
    db.addService(service);

    await operations.deleteServiceCategory('عملیات آزمایشی', moveServicesTo: 'مقصد آزمایشی');

    expect(db.serviceCategories, isNot(contains('عملیات آزمایشی')));
    expect(db.serviceById(service.id)?.category, 'مقصد آزمایشی');
    expect(operations.undoLatestForEntity('عملیات آزمایشی'), isTrue);
    expect(db.serviceCategories, contains('عملیات آزمایشی'));
    expect(db.serviceById(service.id)?.category, 'عملیات آزمایشی');
  });

  test('financial correction creates permanent reversal documents and has no undo', () async {
    final employee = db.employees.first;
    final original = db.addWalletTransaction(
      employeeId: employee.id,
      amount: 50000,
      type: EmployeeWalletTransactionType.bonus,
      description: 'پاداش آزمایشی برای ممیزی',
      idempotencyKey: 'operation-finance-seed',
    );

    final documents = await operations.correctWalletTransaction(
      transactionId: original.id,
      correctedAmount: 70000,
      description: 'اصلاح مبلغ پاداش',
    );

    expect(documents, hasLength(2));
    expect(documents.first.amount, -original.amount);
    expect(documents.last.amount, 70000);
    expect(operations.latestUndoableLogFor(original.id), isNull);
    final audit = db.activityLogs.firstWhere((item) => item.entityId == original.id && item.operationType == 'financial_correction');
    expect(audit.isReversible, isFalse);
    expect(operations.undo(audit.id), isFalse);
  });

  test('role and permission assignment is audited and undo restores the previous role', () async {
    final employee = db.employees.first;
    final previous = db.accessAssignmentFor(employee.id)!;

    await operations.assignEmployeeRole(
      employeeId: employee.id,
      roleId: 'operator',
      overrides: const {'customers.view': false},
      canViewOtherEmployees: false,
      canViewPersonalIncome: false,
    );

    expect(db.accessAssignmentFor(employee.id)?.roleId, 'operator');
    final audit = operations.latestUndoableLogFor(employee.id);
    expect(audit?.operationType, 'access_assignment');
    expect(audit?.isReversible, isTrue);

    expect(operations.undoLatestForEntity(employee.id), isTrue);
    expect(db.accessAssignmentFor(employee.id)?.roleId, previous.roleId);
    expect(db.accessAssignmentFor(employee.id)?.overrides, previous.overrides);
  });

  test('service used in appointment history is archived and can be restored', () async {
    const service = Service(
      id: 'operation-service-history',
      title: 'خدمت دارای سابقه',
      price: 350000,
      durationMinutes: 60,
      category: 'آزمایش',
    );
    db.addService(service);
    final appointment = Appointment(
      id: 'operation-service-appointment',
      reference: 'OP-003',
      customerId: db.customers.first.id,
      customerName: db.customers.first.fullName,
      customerPhone: db.customers.first.phone,
      serviceIds: [service.id],
      serviceName: service.title,
      employeeId: db.employees.first.id,
      employeeName: db.employees.first.fullName,
      startAt: DateTime(2026, 11, 27, 12),
      durationMinutes: 60,
      price: service.price,
    );
    db.addAppointment(appointment);

    await operations.deleteService(service.id);

    expect(db.serviceById(service.id)?.isActive, isFalse);
    expect(db.appointmentById(appointment.id)?.serviceIds, contains(service.id));
    expect(operations.undoLatestForEntity(service.id), isTrue);
    expect(db.serviceById(service.id)?.isActive, isTrue);
  });

  test('undo is blocked when a dependent service changed after category deletion', () async {
    db.addServiceCategory('دسته قدیمی');
    db.addServiceCategory('دسته مقصد');
    const service = Service(
      id: 'operation-stale-service',
      title: 'خدمت اولیه',
      price: 180000,
      durationMinutes: 30,
      category: 'دسته قدیمی',
    );
    db.addService(service);

    await operations.deleteServiceCategory('دسته قدیمی', moveServicesTo: 'دسته مقصد');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    db.updateService(db.serviceById(service.id)!.copyWith(title: 'خدمت ویرایش‌شده'));

    expect(operations.undoLatestForEntity('دسته قدیمی'), isFalse);
    expect(db.serviceById(service.id)?.title, 'خدمت ویرایش‌شده');
    expect(db.serviceById(service.id)?.category, 'دسته مقصد');
  });

  test('employee deletion restores service relationships and payroll configuration', () async {
    const service = Service(
      id: 'operation-employee-service',
      title: 'خدمت پرسنل آزمایشی',
      price: 100000,
      durationMinutes: 30,
      category: 'آزمایش پرسنل',
    );
    db.addService(service);
    final employee = Employee(
      id: 'operation-employee',
      fullName: 'پرسنل آزمایشی',
      phone: '09123334455',
      serviceIds: [service.id],
    );
    db.addEmployee(employee);

    await operations.deleteEmployee(employee.id);

    expect(db.employeeById(employee.id), isNull);
    expect(db.serviceById(service.id)?.employeeIds, isNot(contains(employee.id)));
    expect(operations.undoLatestForEntity(employee.id), isTrue);
    expect(db.employeeById(employee.id)?.fullName, employee.fullName);
    expect(db.serviceById(service.id)?.employeeIds, contains(employee.id));
    expect(db.employeeServiceConfig(employee.id, service.id), isNotNull);
  });

  test('completed appointment cannot be undone because it created financial entries', () async {
    final appointment = Appointment(
      id: 'operation-completed-appointment',
      reference: 'OP-004',
      customerId: db.customers.first.id,
      customerName: db.customers.first.fullName,
      customerPhone: db.customers.first.phone,
      serviceIds: const [],
      serviceName: 'خدمت تکمیل‌شده',
      employeeId: db.employees.first.id,
      employeeName: db.employees.first.fullName,
      startAt: DateTime(2026, 11, 28, 9),
      durationMinutes: 30,
      price: 150000,
    );
    db.addAppointment(appointment);
    db.changeStatus(appointment, AppointmentStatus.completed);

    expect(db.appointmentById(appointment.id)?.status, AppointmentStatus.completed);
    expect(operations.latestUndoableLogFor(appointment.id), isNull);
  });

  test('appointment with posted receipt cannot be deleted', () async {
    final appointment = Appointment(
      id: 'operation-paid-appointment',
      reference: 'OP-005',
      customerId: db.customers.first.id,
      customerName: db.customers.first.fullName,
      customerPhone: db.customers.first.phone,
      serviceIds: const [],
      serviceName: 'خدمت پرداخت‌شده',
      employeeId: db.employees.first.id,
      employeeName: db.employees.first.fullName,
      startAt: DateTime(2026, 11, 29, 9),
      durationMinutes: 30,
      price: 200000,
    );
    db.addAppointment(appointment);
    db.recordAppointmentPayment(
      appointmentId: appointment.id,
      amount: 50000,
      method: BusinessPaymentMethod.cash,
      description: 'رسید آزمایشی',
      idempotencyKey: 'operation-paid-receipt',
    );

    await expectLater(operations.deleteAppointment(appointment.id), throwsStateError);
    expect(db.appointmentById(appointment.id), isNotNull);
    expect(db.paymentsForAppointment(appointment.id), hasLength(1));
  });

  test('custom role creation is audited, idempotent and undoable', () async {
    final role = await operations.createAccessRole(
      name: 'نقش آزمایشی قابل بازگردانی',
      permissionIds: const ['customers.view', 'appointments.view_self'],
    );

    expect(db.accessRoleById(role.id)?.permissionIds, contains('customers.view'));
    final audit = operations.latestUndoableLogFor(role.id);
    expect(audit, isNotNull);
    expect(audit!.operationType, 'access_role_create');
    expect(audit.operationLabel, 'ایجاد نقش دسترسی');
    expect(audit.actor, db.currentAccessAccount.name);
    expect(audit.isReversible, isTrue);
    expect(operations.undo(audit.id), isTrue);
    expect(db.accessRoleById(role.id), isNull);
    expect(db.hasExecutedOperation('access-role-create:نقش آزمایشی قابل بازگردانی'), isFalse);
  });

  test('custom role creation cannot be undone after a staff member is assigned to it', () async {
    final role = await operations.createAccessRole(name: 'نقش دارای تخصیص');
    final employee = db.employees.first;

    await operations.assignEmployeeRole(employeeId: employee.id, roleId: role.id);

    expect(db.accessRoleById(role.id), isNotNull);
    expect(operations.latestUndoableLogFor(role.id), isNull);
  });

  test('attendance payroll policy changes are confirmed through repository, audited and undoable', () async {
    final next = AttendancePayrollPolicy(
      enabled: true,
      lateDeductionPerMinute: 1200,
      absenceDeductionPerDay: 250000,
      overtimePaymentPerMinute: 1800,
      earlyLeaveDeductionPerMinute: 900,
    );

    expect(await operations.saveAttendancePayrollPolicy(next), isTrue);
    expect(db.attendancePayrollPolicy.enabled, isTrue);
    expect(db.attendancePayrollPolicy.lateDeductionPerMinute, 1200);

    final audit = operations.latestUndoableLogFor('attendance-payroll-policy');
    expect(audit, isNotNull);
    expect(audit!.operationType, 'financial_attendance_policy_update');
    expect(audit.operationLabel, 'تغییر قانون مالی حضور و غیاب');
    expect(audit.actor, db.currentAccessAccount.name);
    expect(audit.isReversible, isTrue);
    expect(operations.canUndo(audit.id), isTrue);

    expect(operations.undo(audit.id), isTrue);
    expect(db.attendancePayrollPolicy.enabled, isFalse);
    expect(db.attendancePayrollPolicy.lateDeductionPerMinute, 0);
    expect(db.hasExecutedOperation(audit.idempotencyKey!), isFalse);
    expect(operations.canUndo(audit.id), isFalse);
  });

  test('no-op permission assignment cannot produce a fake success or undo', () async {
    final employee = db.employees.first;
    final current = db.accessAssignmentFor(employee.id)!;
    final before = db.activityLogs.length;

    await expectLater(
      operations.assignEmployeeRole(
        employeeId: employee.id,
        roleId: current.roleId,
        overrides: current.overrides,
        canViewOtherEmployees: current.canViewOtherEmployees,
        canViewPersonalIncome: current.canViewPersonalIncome,
      ),
      throwsStateError,
    );

    expect(db.activityLogs.length, before);
    expect(operations.latestUndoableLogFor(employee.id), isNull);
  });

  test('unchanged attendance payroll policy does not create a fake undo entry', () async {
    final before = db.activityLogs.length;
    expect(await operations.saveAttendancePayrollPolicy(const AttendancePayrollPolicy()), isFalse);
    expect(db.activityLogs.length, before);
    expect(operations.latestUndoableLogFor('attendance-payroll-policy'), isNull);
  });

  test('failed operation does not consume its idempotency key', () {
    expect(
      () => db.executeSensitiveOperation<void>(
        idempotencyKey: 'operation-failure-test',
        operationType: 'test_failure',
        entityName: 'آزمایش',
        entityId: 'failure',
        description: 'عملیات آزمایشی ناموفق',
        reversible: false,
        action: () => throw StateError('failure'),
      ),
      throwsStateError,
    );
    expect(db.hasExecutedOperation('operation-failure-test'), isFalse);
  });
}
