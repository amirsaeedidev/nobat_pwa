import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/models/employee_attendance.dart';
import 'package:datetime/data/models/employee_performance_report.dart';

void main() {
  test('attendance record parses the persisted Supabase event schema', () {
    final row = EmployeeAttendanceRecord.fromJson({
      'id': 'attendance-1',
      'employee_id': 'employee-1',
      'work_date': '2026-11-27',
      'event_type': 'check_out',
      'occurred_at': '2026-11-27T15:30:00Z',
      'note': 'پایان شیفت',
      'late_minutes': 0,
      'overtime_minutes': 25,
      'early_leave_minutes': 0,
      'worked_minutes': 480,
      'correction_of_id': null,
    });

    expect(row.type, EmployeeAttendanceEventType.checkOut);
    expect(row.workedMinutes, 480);
    expect(row.overtimeMinutes, 25);
    expect(row.note, 'پایان شیفت');
  });

  test('unknown attendance event fails to a non-destructive correction label', () {
    expect(
      EmployeeAttendanceEventType.fromKey('unknown'),
      EmployeeAttendanceEventType.manualCorrection,
    );
  });

  test('attendance payroll policy parses server policy without enabling it by default', () {
    final disabled = EmployeeAttendancePayrollPolicy.fromJson({});
    expect(disabled.enabled, isFalse);
    expect(disabled.lateDeductionPerMinute, 0);

    final enabled = EmployeeAttendancePayrollPolicy.fromJson({
      'enabled': true,
      'late_deduction_per_minute_toman': 1200,
      'absence_deduction_per_day_toman': 500000,
      'overtime_payment_per_minute_toman': 900,
      'early_leave_deduction_per_minute_toman': 800,
    });
    expect(enabled.enabled, isTrue);
    expect(enabled.absenceDeductionPerDay, 500000);
    expect(enabled.overtimePaymentPerMinute, 900);
  });

  test('performance daily projection parses actual database aggregate columns', () {
    final day = EmployeePerformanceDay.fromJson({
      'work_date': '2026-11-27',
      'appointment_count': 4,
      'completed_count': 3,
      'cancelled_count': 1,
      'no_show_count': 0,
      'unique_customers': 3,
      'gross_revenue_toman': 2000000,
      'net_revenue_toman': 1800000,
      'commission_toman': 540000,
      'company_share_toman': 1260000,
      'booked_minutes': 150,
      'attendance_data_available': true,
      'absence_count': 0,
      'worked_minutes': 420,
      'late_minutes': 10,
      'overtime_minutes': 25,
      'early_leave_minutes': 0,
      'approved_leave_count': 0,
      'earned_toman': 540000,
      'bonus_toman': 0,
      'deduction_toman': 0,
      'advance_toman': 0,
      'salary_paid_toman': 0,
      'wallet_delta_toman': 540000,
    });

    expect(day.appointments, 4);
    expect(day.completed, 3);
    expect(day.netRevenue, 1800000);
    expect(day.commission, 540000);
    expect(day.attendanceAvailable, isTrue);
    expect(day.workedMinutes, 420);
  });
}
