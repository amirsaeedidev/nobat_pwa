import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/employee.dart';
import 'package:datetime/data/models/employee_schedule.dart';

void main() {
  group('Employee schedule and leave management', () {
    late AppDatabase db;
    late Employee employee;

    setUp(() {
      db = AppDatabase();
      employee = db.employees.first;
    });

    test('weekly shifts validate and are stored for an employee only', () {
      final date = DateTime.now().add(const Duration(days: 40));
      final weekday = JalaliDate.fromDateTime(date).weekday;
      db.saveEmployeeWeeklySchedule(employee.id, {weekday: const [Shift(start: '09:00', end: '12:00'), Shift(start: '13:00', end: '17:00')]}, bufferMinutes: 10);
      expect(db.employeeShiftsForDate(employee.id, date), hasLength(2));
      expect(db.employeeById(employee.id)!.bufferMinutes, 10);
    });

    test('overlapping or invalid shifts are rejected', () {
      expect(
        () => db.saveEmployeeWeeklySchedule(employee.id, const {1: [Shift(start: '09:00', end: '13:00'), Shift(start: '12:00', end: '15:00')]}),
        throwsArgumentError,
      );
      expect(
        () => db.saveEmployeeWeeklySchedule(employee.id, const {1: [Shift(start: '15:00', end: '09:00')]}),
        throwsArgumentError,
      );
    });

    test('dated exception overrides weekly schedule, including closed day', () {
      final date = DateTime.now().add(const Duration(days: 42));
      final weekday = JalaliDate.fromDateTime(date).weekday;
      db.saveEmployeeWeeklySchedule(employee.id, {weekday: const [Shift(start: '09:00', end: '17:00')]});
      final key = EmployeeScheduleRules.dateKey(date);
      db.saveEmployeeScheduleException(EmployeeScheduleException(employeeId: employee.id, dateKey: key, isClosed: true));
      expect(db.employeeShiftsForDate(employee.id, date), isEmpty);
      db.saveEmployeeScheduleException(EmployeeScheduleException(employeeId: employee.id, dateKey: key, isClosed: false, shifts: const [Shift(start: '10:00', end: '14:00')]));
      expect(db.employeeShiftsForDate(employee.id, date).single.start, '10:00');
    });

    test('approved hourly leave blocks only its time range; pending leave does not', () {
      final date = DateTime.now().add(const Duration(days: 44));
      final weekday = JalaliDate.fromDateTime(date).weekday;
      db.saveEmployeeWeeklySchedule(employee.id, {weekday: const [Shift(start: '09:00', end: '17:00')]});
      final start = DateTime(date.year, date.month, date.day, 11);
      final leave = EmployeeLeave(
        id: 'leave-test', employeeId: employee.id, startAt: start,
        endAt: start.add(const Duration(hours: 2)), type: EmployeeLeaveType.hourly,
        status: EmployeeLeaveStatus.pending, createdAt: DateTime.now(),
      );
      db.addEmployeeLeave(leave);
      expect(db.isEmployeeAvailableAt(employeeId: employee.id, startAt: start, durationMinutes: 30), isTrue);
      db.updateEmployeeLeave(leave.copyWith(status: EmployeeLeaveStatus.approved));
      expect(db.isEmployeeAvailableAt(employeeId: employee.id, startAt: start, durationMinutes: 30), isFalse);
      expect(db.isEmployeeAvailableAt(employeeId: employee.id, startAt: start.subtract(const Duration(hours: 1)), durationMinutes: 30), isTrue);
    });

    test('availability rejects time outside shift and respects disabled schedule', () {
      final date = DateTime.now().add(const Duration(days: 46));
      final weekday = JalaliDate.fromDateTime(date).weekday;
      db.saveEmployeeWeeklySchedule(employee.id, {weekday: const [Shift(start: '10:00', end: '14:00')]});
      final atNine = DateTime(date.year, date.month, date.day, 9);
      expect(db.isEmployeeAvailableAt(employeeId: employee.id, startAt: atNine, durationMinutes: 30), isFalse);
      db.saveEmployeeWeeklySchedule(employee.id, {weekday: const [Shift(start: '09:00', end: '17:00')]}, enabled: false);
      expect(db.isEmployeeAvailableAt(employeeId: employee.id, startAt: atNine, durationMinutes: 30), isFalse);
    });

    test('leave data round-trips without losing approval metadata', () {
      final leave = EmployeeLeave(
        id: 'leave-roundtrip', employeeId: employee.id,
        startAt: DateTime(2026, 11, 20, 9), endAt: DateTime(2026, 11, 20, 17),
        type: EmployeeLeaveType.emergency, status: EmployeeLeaveStatus.approved,
        description: 'تست آفلاین', createdAt: DateTime(2026, 11, 1), approvedBy: 'مدیر',
      );
      final restored = EmployeeLeave.fromJson(leave.toJson());
      expect(restored.status, EmployeeLeaveStatus.approved);
      expect(restored.approvedBy, 'مدیر');
      expect(restored.description, 'تست آفلاین');
    });
  });
}
