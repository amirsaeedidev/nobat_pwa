import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/appointment.dart';
import 'package:datetime/data/models/employee.dart';
import 'package:datetime/data/models/employee_finance.dart';
import 'package:datetime/data/models/employee_hr.dart';
import 'package:datetime/data/models/employee_payroll.dart';
import 'package:datetime/data/models/employee_schedule.dart';
import 'package:datetime/data/models/employee_service_config.dart';
import 'package:datetime/data/models/employee_wallet.dart';
import 'package:datetime/data/models/enums.dart';

void main() {
  group('Phase 10 personnel integration', () {
    test('service edits and employee edits keep both sides of the relation synchronized', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final service = db.services.first;

      db.updateService(service.copyWith(
        employeeIds: service.employeeIds.where((id) => id != employee.id).toList(),
      ));
      expect(db.employeeById(employee.id)!.serviceIds, isNot(contains(service.id)));
      expect(db.employeeOffersService(employee.id, service.id), isFalse);

      final updatedService = db.serviceById(service.id)!;
      db.updateService(updatedService.copyWith(employeeIds: [...updatedService.employeeIds, employee.id]));
      expect(db.employeeById(employee.id)!.serviceIds, contains(service.id));
      expect(db.employeeOffersService(employee.id, service.id), isTrue);
    });

    test('attendance supports multiple non-overlapping shifts in one day', () {
      final db = AppDatabase();
      final employee = db.employees.first;
      final day = DateTime(2026, 1, 10);
      db.recordAttendance(AttendanceRecord(
        id: 'phase10-in-1', employeeId: employee.id, date: day,
        type: AttendanceEventType.checkIn, at: day.add(const Duration(hours: 9)),
      ));
      db.recordAttendance(AttendanceRecord(
        id: 'phase10-out-1', employeeId: employee.id, date: day,
        type: AttendanceEventType.checkOut, at: day.add(const Duration(hours: 12)),
      ));
      db.recordAttendance(AttendanceRecord(
        id: 'phase10-in-2', employeeId: employee.id, date: day,
        type: AttendanceEventType.checkIn, at: day.add(const Duration(hours: 13)),
      ));
      db.recordAttendance(AttendanceRecord(
        id: 'phase10-out-2', employeeId: employee.id, date: day,
        type: AttendanceEventType.checkOut, at: day.add(const Duration(hours: 18)),
      ));
      final summary = db.attendanceSummary(employee.id, from: day, to: day.add(const Duration(days: 1)));
      expect(summary.presentDays, 1);
      expect(summary.workedMinutes, 480);
    });

    test('employee role cannot mutate another employee schedule or delete their leave', () {
      final db = AppDatabase()..switchMockAccount('demo-staff');
      final target = db.employeeById('emp-shima')!;
      final day = DateTime(2026, 12, 1);
      expect(
        () => db.saveEmployeeScheduleException(EmployeeScheduleException(
          employeeId: target.id, dateKey: EmployeeScheduleRules.dateKey(day), isClosed: true,
        )),
        throwsA(isA<AccessDeniedException>()),
      );
      db.switchMockAccount('demo-global-admin');
      final leave = EmployeeLeave(
        id: 'phase10-protected-leave', employeeId: target.id,
        startAt: day, endAt: day.add(const Duration(days: 1)),
        type: EmployeeLeaveType.daily, status: EmployeeLeaveStatus.pending,
        createdAt: DateTime.now(), description: 'درخواست آزمایشی',
      );
      db.addEmployeeLeave(leave);
      db.switchMockAccount('demo-staff');
      expect(() => db.deleteEmployeeLeave(leave.id), throwsA(isA<AccessDeniedException>()));
    });

    test('complete personnel financial journey remains consistent through settlement', () {
      final db = AppDatabase();
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final employeeTemplate = db.employees.first;
      final service = db.services.first;
      final employee = employeeTemplate.copyWith(
        id: 'emp-phase10-integration',
        fullName: 'پرسنل سناریوی یکپارچه',
        phone: '09129990001',
        serviceIds: [service.id],
      );
      db.addEmployee(employee);

      db.savePayProfile(EmployeePayProfile(
        employeeId: employee.id,
        method: EmployeePaymentMethod.fixedPlusCommission,
        monthlySalary: 2000000,
        generalRateBps: 2000,
        basis: CommissionBasis.afterDiscount,
      ));
      db.saveSalaryContract(SalaryContract(
        id: 'phase10-salary-contract',
        employeeId: employee.id,
        monthlyBase: 2000000,
        effectiveFrom: monthStart,
      ));
      db.saveEmployeeServiceConfig(EmployeeServiceConfig(
        employeeId: employee.id,
        serviceId: service.id,
        active: true,
        commissionRateBps: 4000,
      ));
      final appointmentDay = now.add(const Duration(days: 60));
      final appointmentStart = DateTime(appointmentDay.year, appointmentDay.month, appointmentDay.day, 10);
      db.saveEmployeeWeeklySchedule(employee.id, {
        JalaliDate.fromDateTime(appointmentDay).weekday: const [Shift(start: '09:00', end: '18:00')],
      });
      expect(db.employeeOffersService(employee.id, service.id), isTrue);
      expect(db.isEmployeeAvailableAt(
        employeeId: employee.id,
        startAt: appointmentStart,
        durationMinutes: service.totalMinutes,
      ), isTrue);

      final customer = db.customers.first;
      final appointment = Appointment(
        id: 'phase10-integration-appointment',
        reference: 'PHASE10-001',
        customerId: customer.id,
        customerName: customer.fullName,
        customerPhone: customer.phone,
        serviceIds: [service.id],
        serviceName: service.title,
        employeeId: employee.id,
        employeeName: employee.fullName,
        startAt: appointmentStart,
        durationMinutes: service.totalMinutes,
        price: service.price,
        serviceSnapshots: [{
          'service_id': service.id,
          'title': service.title,
          'category': service.category,
          'price': service.price,
          'duration_minutes': service.totalMinutes,
          'commission_rate_bps': 4000,
          'fixed_commission_amount': 0,
          'commission_basis': CommissionBasis.afterDiscount.name,
        }],
      );
      db.addAppointment(appointment);
      db.changeStatus(appointment, AppointmentStatus.completed);
      final commission = db.financeEntriesFor(employee.id)
          .singleWhere((entry) => entry.appointmentId == appointment.id);
      expect(commission.commissionAmount, (service.price * 0.4).round());
      expect(db.hasCommissionForAppointment(appointment.id), isTrue);

      db.addWalletTransaction(
        employeeId: employee.id, amount: 500000,
        type: EmployeeWalletTransactionType.bonus, description: 'پاداش عملکرد سناریو',
      );
      db.addWalletTransaction(
        employeeId: employee.id, amount: -200000,
        type: EmployeeWalletTransactionType.advance, description: 'مساعده سناریو',
      );
      db.addWalletTransaction(
        employeeId: employee.id, amount: -50000,
        type: EmployeeWalletTransactionType.deduction, description: 'کسورات سناریو',
      );

      final payroll = db.payrollFor(employee.id, at: now);
      expect(payroll.baseSalary, 2000000);
      expect(payroll.approvedCommission, commission.commissionAmount);
      expect(payroll.approvedBonuses, 500000);
      expect(payroll.deductions, 50000);
      expect(payroll.advanceDeducted, 200000);
      expect(payroll.payable, 2000000 + commission.commissionAmount + 500000 - 50000 - 200000);

      expect(db.accruePayrollBaseToWallet(employee.id, at: now), 1);
      expect(db.accruePayrollBaseToWallet(employee.id, at: now), 0);
      final periodEnd = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
      final due = db.walletPeriodDue(employee.id, monthStart, periodEnd);
      expect(due, payroll.payable);

      final settlement = db.settleEmployeeWallet(
        employeeId: employee.id,
        periodStart: monthStart,
        periodEnd: periodEnd,
        periodType: EmployeeWalletPeriodType.monthly,
        paidAmount: due,
        idempotencyKey: 'phase10-settlement-once',
      );
      expect(settlement.remainingAfter, 0);
      expect(db.walletBalanceFor(employee.id), 0);
      expect(db.payrollFor(employee.id, at: now).payable, 0);
    });

    test('commission refunds and attendance policy flow into payroll preview', () {
      final db = AppDatabase();
      final now = DateTime.now();
      final template = db.employees.first;
      final service = db.services.first;
      final employee = template.copyWith(
        id: 'emp-phase10-adjustments',
        fullName: 'پرسنل اصلاحات',
        phone: '09129990002',
        serviceIds: [service.id],
      );
      db.addEmployee(employee);
      db.savePayProfile(EmployeePayProfile(
        employeeId: employee.id, method: EmployeePaymentMethod.commissionOnly,
        generalRateBps: 3000,
      ));
      final customer = db.customers.first;
      final appointment = Appointment(
        id: 'phase10-refund-appointment', reference: 'PHASE10-REFUND',
        customerId: customer.id, customerName: customer.fullName,
        customerPhone: customer.phone, serviceIds: [service.id],
        serviceName: service.title, employeeId: employee.id,
        employeeName: employee.fullName, startAt: now,
        durationMinutes: service.totalMinutes, price: service.price,
      );
      db.addAppointment(appointment);
      db.changeStatus(appointment, AppointmentStatus.completed);
      final original = db.financeEntriesFor(employee.id).single;
      expect(db.recordCommissionRefund(original.id, 100000), isTrue);
      final payroll = db.payrollFor(employee.id, at: now);
      expect(payroll.approvedCommission, original.commissionAmount);
      expect(payroll.commissionRefunds, greaterThan(0));

      final day = DateTime(now.year, now.month, now.day);
      db.recordAttendance(AttendanceRecord(
        id: 'phase10-policy-in', employeeId: employee.id, date: day,
        type: AttendanceEventType.checkIn, at: day.add(const Duration(hours: 9)),
        lateMinutes: 10,
      ));
      db.recordAttendance(AttendanceRecord(
        id: 'phase10-policy-out', employeeId: employee.id, date: day,
        type: AttendanceEventType.checkOut, at: day.add(const Duration(hours: 18)),
        overtimeMinutes: 30,
      ));
      db.saveAttendancePayrollPolicy(const AttendancePayrollPolicy(
        enabled: true, lateDeductionPerMinute: 1000, overtimePaymentPerMinute: 500,
      ));
      final updated = db.payrollFor(employee.id, at: now);
      expect(updated.attendanceAdjustment, 5000);
    });
  });
}
