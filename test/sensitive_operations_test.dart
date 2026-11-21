import 'package:flutter_test/flutter_test.dart';

import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/appointment.dart';
import 'package:datetime/data/models/customer.dart';
import 'package:datetime/data/models/enums.dart';
import 'package:datetime/data/models/service.dart';
import 'package:datetime/data/models/employee_wallet.dart';
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

    expect(operations.undo(audit.id), isTrue);
    expect(db.customerById(customer.id)?.fullName, customer.fullName);
    expect(db.canUndoLog(audit.id), isFalse);
  });

  test('customer with appointment history cannot be deleted or orphaned', () async {
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
