import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/appointment.dart';
import 'package:datetime/data/models/business_finance.dart';
import 'package:datetime/data/models/employee_finance.dart';
import 'package:datetime/data/models/enums.dart';

void main() {
  group('CommissionCalculator', () {
    test('calculates 30 percent of ten million with integer arithmetic', () {
      expect(CommissionCalculator.commission(baseAmount: 10000000, rateBps: 3000), 3000000);
    });
    test('uses the selected discount basis', () {
      expect(CommissionCalculator.base(basis: CommissionBasis.gross, grossAmount: 10000000, discountAmount: 2000000, receivedAmount: 8000000), 10000000);
      expect(CommissionCalculator.base(basis: CommissionBasis.afterDiscount, grossAmount: 10000000, discountAmount: 2000000, receivedAmount: 8000000), 8000000);
      expect(CommissionCalculator.base(basis: CommissionBasis.netReceived, grossAmount: 10000000, discountAmount: 2000000, receivedAmount: 6500000), 6500000);
      expect(CommissionCalculator.commission(baseAmount: 8000000, rateBps: 3000), 2400000);
    });
    test('rejects invalid negative values and discount above gross', () {
      expect(() => CommissionCalculator.commission(baseAmount: -1, rateBps: 3000), throwsArgumentError);
      expect(() => CommissionCalculator.base(basis: CommissionBasis.afterDiscount, grossAmount: 100, discountAmount: 101, receivedAmount: 0), throwsArgumentError);
    });
    test('resolves service-specific rule before category rule and general rate', () {
      final profile = EmployeePayProfile(employeeId: 'e1', generalRateBps: 2000, rules: [
        const EmployeeCommissionRule(id: 'category', category: 'مو', rateBps: 2500),
        const EmployeeCommissionRule(id: 'service', serviceId: 's1', rateBps: 4000),
      ]);
      expect(profile.ruleFor(serviceId: 's1', category: 'مو', date: DateTime(2026, 1, 1))?.rateBps, 4000);
      expect(profile.ruleFor(serviceId: 's2', category: 'مو', date: DateTime(2026, 1, 1))?.rateBps, 2500);
      expect(profile.ruleFor(serviceId: 's3', category: 'پوست', date: DateTime(2026, 1, 1)), isNull);
    });
  });

  group('Datamonck employee finance ledger', () {
    Appointment pendingAppointment(AppDatabase db, String id, {num price = 10000000}) {
      final employee = db.employees.first;
      final service = db.services.first;
      return Appointment(
        id: id, reference: id, customerId: 'customer-mock', customerName: 'مشتری آزمایشی',
        customerPhone: '09120000000', serviceIds: [service.id], serviceName: service.title,
        employeeId: employee.id, employeeName: employee.fullName, startAt: DateTime(2026, 11, 10),
        durationMinutes: service.durationMinutes, status: AppointmentStatus.pending, price: price,
      );
    }

    test('creates commission once when appointment is completed; cancelled appointments create none', () {
      final db = AppDatabase();
      final first = pendingAppointment(db, 'appt-finance-once');
      db.addAppointment(first);
      db.changeStatus(first, AppointmentStatus.completed);
      final initial = db.financeEntriesFor(first.employeeId).where((e) => e.appointmentId == first.id).length;
      expect(initial, 1);
      expect(db.finalizeCompletedAppointment(first.id), isFalse);
      expect(db.financeEntriesFor(first.employeeId).where((e) => e.appointmentId == first.id).length, 1);

      final cancelled = pendingAppointment(db, 'appt-finance-cancelled');
      db.addAppointment(cancelled);
      db.changeStatus(cancelled, AppointmentStatus.cancelled);
      expect(db.hasCommissionForAppointment(cancelled.id), isFalse);
    });

    test('fixed salary plus commission keeps both parts in employee profile', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      db.savePayProfile(EmployeePayProfile(employeeId: employee.id, method: EmployeePaymentMethod.fixedPlusCommission, monthlySalary: 12000000, generalRateBps: 3000));
      final appointment = pendingAppointment(db, 'appt-salary-plus');
      db.addAppointment(appointment);
      db.changeStatus(appointment, AppointmentStatus.completed);
      final entry = db.financeEntriesFor(employee.id).firstWhere((e) => e.appointmentId == appointment.id);
      expect(entry.commissionAmount, 3000000);
      expect(db.payProfileFor(employee.id).monthlySalary, 12000000);
    });

    test('discount and refunds create immutable traceable adjustment entries', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final appointment = pendingAppointment(db, 'appt-finance-refund');
      db.addAppointment(appointment);
      db.changeStatus(appointment, AppointmentStatus.completed);
      final entry = db.financeEntriesFor(employee.id).firstWhere((e) => e.appointmentId == appointment.id);
      expect(entry.commissionAmount, 3000000);
      expect(db.recordCommissionRefund(entry.id, 5000000), isTrue);
      final refund = db.financeEntriesFor(employee.id).firstWhere((e) => e.type == FinanceEntryType.refund && e.reversesEntryId == entry.id);
      expect(refund.commissionAmount, -1500000);
      expect(db.financeEntriesFor(employee.id).firstWhere((e) => e.id == entry.id).commissionAmount, 3000000);
      expect(() => db.recordCommissionRefund(entry.id, 6000000), throwsArgumentError);
    });

    test('cumulative partial refunds reverse exactly the original rounded commission', () {
      final db = AppDatabase();
      final appointment = pendingAppointment(db, 'appt-refund-rounding', price: 3).copyWith(
        serviceSnapshots: [{
          'service_id': db.services.first.id,
          'price': 3,
          'commission_rate_bps': 3000,
          'commission_basis': 'afterDiscount',
        }],
      );
      db.addAppointment(appointment);
      db.changeStatus(appointment, AppointmentStatus.completed);
      final original = db.employeeFinanceEntries.singleWhere((entry) =>
        entry.appointmentId == appointment.id && entry.type == FinanceEntryType.commission);
      expect(original.commissionAmount, 1);
      final receipt = db.recordAppointmentPayment(
        appointmentId: appointment.id, amount: 3,
        method: BusinessPaymentMethod.cash, description: 'رسید تست گردکردن',
        idempotencyKey: 'rounding-receipt',
      );
      for (var i = 0; i < 3; i++) {
        db.refundAppointmentPayment(
          paymentId: receipt.id, amount: 1,
          description: 'برگشت جزئی ${i + 1}',
          idempotencyKey: 'rounding-refund-${i + 1}',
        );
      }
      final refunds = db.employeeFinanceEntries.where((entry) =>
        entry.type == FinanceEntryType.refund && entry.reversesEntryId == original.id);
      expect(refunds.fold<int>(0, (sum, entry) => sum + entry.commissionAmount), -1);
      expect(refunds.fold<int>(0, (sum, entry) => sum - entry.receivedAmount), 3);
    });

    test('changing future rate does not rewrite existing ledger snapshots', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final appointment = pendingAppointment(db, 'appt-snapshot');
      db.addAppointment(appointment);
      db.changeStatus(appointment, AppointmentStatus.completed);
      final before = db.financeEntriesFor(employee.id).firstWhere((e) => e.appointmentId == appointment.id);
      db.savePayProfile(db.payProfileFor(employee.id).copyWith(generalRateBps: 4500));
      final after = db.financeEntriesFor(employee.id).firstWhere((e) => e.appointmentId == appointment.id);
      expect(after.rateBps, before.rateBps);
      expect(after.commissionAmount, before.commissionAmount);
    });
  });
}
