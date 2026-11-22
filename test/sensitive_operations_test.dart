import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:datetime/app/theme/app_palette.dart';
import 'package:datetime/core/widgets/sensitive_operation_dialog.dart';
import 'package:datetime/data/repositories/activity_repository.dart';
import 'package:datetime/features/activity_logs/presentation/providers/activity_provider.dart';
import 'package:datetime/features/activity_logs/presentation/pages/activity_logs_page.dart';
import 'package:datetime/data/repositories/appointment_repository.dart';
import 'package:datetime/data/repositories/customer_repository.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';
import 'package:datetime/data/repositories/employee_repository.dart';
import 'package:datetime/data/repositories/service_repository.dart';
import 'package:datetime/features/booking/presentation/providers/booking_provider.dart';
import 'package:datetime/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:datetime/features/reports/presentation/providers/reports_provider.dart';

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
    await operations.completeAppointment(appointment.id);

    expect(db.appointmentById(appointment.id)?.status, AppointmentStatus.completed);
    expect(operations.latestUndoableLogFor(appointment.id), isNull);
    expect(db.hasExecutedOperation('appointment-complete-financial:${appointment.id}'), isTrue);
    final completionAudit = db.activityLogs.firstWhere((item) => item.entityId == appointment.id && item.operationType == 'appointment_complete_financial_posting');
    expect(completionAudit.isReversible, isFalse);
    expect(completionAudit.idempotencyKey, 'appointment-complete-financial:${appointment.id}');
    expect(operations.undo(completionAudit.id), isFalse);
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

  test('activity provider refreshes complete audit history after undo', () async {
    const customer = Customer(id: 'history-refresh-customer', fullName: 'مشتری تاریخچه', phone: '09129999999');
    db.addCustomer(customer);
    await operations.deleteCustomer(customer.id);

    final provider = ActivityProvider(MockActivityRepository(db), db);
    addTearDown(provider.dispose);
    await provider.load();

    final deletion = provider.logs.firstWhere((log) => log.operationType == 'customer_delete');
    expect(deletion.entityId, customer.id);
    expect(deletion.operationLabel, 'حذف مشتری');
    expect(provider.canUndo(deletion), isTrue);

    expect(await provider.undo(deletion), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(db.customerById(customer.id), isNotNull);
    expect(provider.logs.any((log) => log.operationType == 'undo' && log.entityId == customer.id), isTrue);
    expect(provider.logs.any((log) => log.id == deletion.id), isTrue);
    expect(provider.canUndo(deletion), isFalse);
  });

  test('audit history is not truncated and searches entity metadata', () async {
    for (var index = 0; index < 115; index++) {
      db.log(
        ActivityType.settingsChanged,
        'رویداد ممیزی $index',
        'جزئیات رویداد $index',
        entity: 'رکورد آزمایش',
        entityId: 'audit-record-$index',
        operationType: 'audit_test_event',
        isReversible: false,
      );
    }

    final repository = MockActivityRepository(db);
    final all = await repository.fetchLogs();
    expect(all.where((log) => log.operationType == 'audit_test_event'), hasLength(115));

    final byEntityId = await repository.fetchLogs(query: 'audit-record-114');
    expect(byEntityId, hasLength(1));
    expect(byEntityId.single.entityId, 'audit-record-114');
  });

  testWidgets('sensitive operation dialog shows record details and cancel is safe', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.pastelPink]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showSensitiveOperationDialog(
                  context,
                  title: 'تأیید حذف آزمایشی',
                  description: 'این تغییر قابل بازگردانی است.',
                  recordDetails: const {'رکورد': 'مشتری آزمایشی', 'شناسه': 'customer-ui-1'},
                  isReversible: true,
                );
              },
              child: const Text('باز کردن تأیید'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('باز کردن تأیید'));
    await tester.pumpAndSettle();
    expect(find.text('تأیید حذف آزمایشی'), findsOneWidget);
    expect(find.text('مشتری آزمایشی'), findsOneWidget);
    expect(find.text('customer-ui-1'), findsOneWidget);

    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('sensitive operation dialog approves only after explicit confirmation', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.pastelPink]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showSensitiveOperationDialog(
                  context,
                  title: 'تأیید اصلاح مالی',
                  description: 'مبلغ ثبت‌شده تغییر می‌کند.',
                  recordDetails: const {'مبلغ': '۷۰۰٬۰۰۰'},
                  isReversible: false,
                  confirmLabel: 'تأیید اصلاح',
                );
              },
              child: const Text('باز کردن اصلاح'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('باز کردن اصلاح'));
    await tester.pumpAndSettle();
    expect(find.text('این عملیات قابل بازگردانی نیست. تاریخچه آن برای ممیزی ثبت می‌شود.'), findsOneWidget);
    await tester.tap(find.text('تأیید اصلاح'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });


  test('dashboard and reports providers refresh after appointment undo', () async {
    final appointment = Appointment(
      id: 'provider-refresh-appointment',
      reference: 'PR-001',
      customerId: db.customers.first.id,
      customerName: db.customers.first.fullName,
      customerPhone: db.customers.first.phone,
      serviceIds: const [],
      serviceName: 'خدمت به‌روزرسانی',
      employeeId: db.employees.first.id,
      employeeName: db.employees.first.fullName,
      startAt: DateTime.now().add(const Duration(hours: 2)),
      durationMinutes: 30,
      price: 175000,
    );
    db.addAppointment(appointment);

    final appointmentRepository = MockAppointmentRepository(db);
    final dashboard = DashboardProvider(
      MockDashboardRepository(db),
      db,
      appointmentRepository: appointmentRepository,
    );
    final reports = ReportsProvider(MockDashboardRepository(db), db);
    addTearDown(dashboard.dispose);
    addTearDown(reports.dispose);
    await Future.wait([dashboard.load(), reports.load()]);
    final cancelledBefore = reports.analytics.cancelledAppointments;

    await operations.cancelAppointment(appointment.id, reason: 'آزمایش همگام‌سازی');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(reports.analytics.cancelledAppointments, greaterThanOrEqualTo(1));

    expect(operations.undoLatestForEntity(appointment.id), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(dashboard.upcoming.any((item) => item.id == appointment.id), isTrue);
    expect(reports.analytics.cancelledAppointments, cancelledBefore);
    expect(dashboard.analytics, isNotNull);
  });

  test('public booking provider refreshes service catalogue after undo', () async {
    const service = Service(
      id: 'booking-provider-service',
      title: 'خدمت رزرو آزمایشی',
      price: 210000,
      durationMinutes: 30,
      category: 'آزمایش رزرو',
    );
    db.addService(service);

    final provider = BookingProvider(
      MockAppointmentRepository(db),
      MockServiceRepository(db),
      MockEmployeeRepository(db),
      MockCustomerRepository(db),
      db,
    );
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(provider.availableServices.any((item) => item.id == service.id), isTrue);

    await operations.deleteService(service.id);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(provider.availableServices.any((item) => item.id == service.id), isFalse);

    expect(operations.undoLatestForEntity(service.id), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(provider.availableServices.any((item) => item.id == service.id), isTrue);
  });


  test('wallet entry and settlement forms create immutable audited financial documents', () async {
    final employee = db.employees.first;
    final now = DateTime.now();
    final transaction = await operations.addWalletTransaction(
      employeeId: employee.id,
      amount: 1000000,
      type: EmployeeWalletTransactionType.bonus,
      description: 'پاداش برای تست مسیر فرم کیف پول',
      idempotencyKey: 'wallet-form-test-${employee.id}',
      createdAt: now,
    );

    expect(db.employeeWalletTransactions.any((item) => item.id == transaction.id), isTrue);
    expect(db.hasExecutedOperation('wallet-form-test-${employee.id}'), isTrue);
    final entryAudit = db.activityLogs.firstWhere((item) => item.operationType == 'financial_wallet_entry' && item.idempotencyKey == 'wallet-form-test-${employee.id}');
    expect(entryAudit.isReversible, isFalse);
    expect(operations.undo(entryAudit.id), isFalse);

    final settlement = await operations.settleEmployeeWallet(
      employeeId: employee.id,
      periodStart: now.subtract(const Duration(days: 1)),
      periodEnd: now.add(const Duration(days: 1)),
      periodType: EmployeeWalletPeriodType.manual,
      paidAmount: 100000,
      idempotencyKey: 'wallet-settlement-form-test-${employee.id}',
    );
    expect(db.employeeWalletSettlements.any((item) => item.id == settlement.id), isTrue);
    expect(db.hasExecutedOperation('wallet-settlement-form-test-${employee.id}'), isTrue);
    final settlementAudit = db.activityLogs.firstWhere((item) => item.operationType == 'financial_wallet_settlement' && item.idempotencyKey == 'wallet-settlement-form-test-${employee.id}');
    expect(settlementAudit.isReversible, isFalse);
    expect(operations.undo(settlementAudit.id), isFalse);
  });


  testWidgets('activity history page completes the real confirm and undo user flow', (tester) async {
    const customer = Customer(
      id: 'activity-ui-undo-customer',
      fullName: 'مشتری رابط کاربری',
      phone: '09128887766',
    );
    db.addCustomer(customer);
    await operations.deleteCustomer(customer.id);

    final provider = ActivityProvider(MockActivityRepository(db), db);
    addTearDown(provider.dispose);
    provider.search(customer.id);
    await provider.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.pastelPink]),
        home: ActivityLogsPageWithProvider(provider: provider),
      ),
    );
    // Activity pages may render an infinite shimmer while a provider refreshes.
    // Use bounded pumps for route/dialog transitions instead of pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final undoButton = find.byTooltip('بازگردانی این تغییر');
    expect(undoButton, findsOneWidget);
    await tester.tap(undoButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('تأیید بازگردانی تغییر'), findsOneWidget);
    expect(find.text('customer-ui-undo-customer'), findsOneWidget);
    await tester.tap(find.text('بازگردانی واقعی'));
    // Wait for the async local undo + repository refresh without waiting for
    // the perpetual skeleton animation to become idle.
    for (var attempt = 0; attempt < 12 && provider.loading; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(db.customerById(customer.id), isNotNull);
    expect(provider.logs.any((log) => log.operationType == 'undo' && log.entityId == customer.id), isTrue);
  });

}


class ActivityLogsPageWithProvider extends StatelessWidget {
  const ActivityLogsPageWithProvider({super.key, required this.provider});

  final ActivityProvider provider;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<ActivityProvider>.value(
        value: provider,
        child: const ActivityLogsPage(),
      );
}
