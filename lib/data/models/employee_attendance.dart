enum EmployeeAttendanceEventType {
  checkIn('ورود', 'check_in'),
  checkOut('خروج', 'check_out'),
  absence('غیبت', 'absence'),
  mission('مأموریت', 'mission'),
  manualCorrection('اصلاح دستی', 'manual_correction');

  const EmployeeAttendanceEventType(this.label, this.key);
  final String label;
  final String key;

  static EmployeeAttendanceEventType fromKey(String? key) =>
      EmployeeAttendanceEventType.values.firstWhere(
        (value) => value.key == key,
        orElse: () => EmployeeAttendanceEventType.manualCorrection,
      );
}

class EmployeeAttendanceRecord {
  const EmployeeAttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.type,
    required this.occurredAt,
    this.note = '',
    this.lateMinutes = 0,
    this.overtimeMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.workedMinutes = 0,
    this.correctionOfId,
  });

  final String id;
  final String employeeId;
  final DateTime workDate;
  final EmployeeAttendanceEventType type;
  final DateTime occurredAt;
  final String note;
  final int lateMinutes;
  final int overtimeMinutes;
  final int earlyLeaveMinutes;
  final int workedMinutes;
  final String? correctionOfId;

  factory EmployeeAttendanceRecord.fromJson(Map<String, dynamic> row) =>
      EmployeeAttendanceRecord(
        id: row['id'].toString(),
        employeeId: row['employee_id'].toString(),
        workDate: DateTime.parse(row['work_date'].toString()),
        type: EmployeeAttendanceEventType.fromKey(row['event_type']?.toString()),
        occurredAt: DateTime.parse(row['occurred_at'].toString()).toLocal(),
        note: row['note']?.toString() ?? '',
        lateMinutes: (row['late_minutes'] as num?)?.toInt() ?? 0,
        overtimeMinutes: (row['overtime_minutes'] as num?)?.toInt() ?? 0,
        earlyLeaveMinutes: (row['early_leave_minutes'] as num?)?.toInt() ?? 0,
        workedMinutes: (row['worked_minutes'] as num?)?.toInt() ?? 0,
        correctionOfId: row['correction_of_id']?.toString(),
      );
}

class EmployeeAttendancePayrollPolicy {
  const EmployeeAttendancePayrollPolicy({
    this.enabled = false,
    this.lateDeductionPerMinute = 0,
    this.absenceDeductionPerDay = 0,
    this.overtimePaymentPerMinute = 0,
    this.earlyLeaveDeductionPerMinute = 0,
  });

  final bool enabled;
  final int lateDeductionPerMinute;
  final int absenceDeductionPerDay;
  final int overtimePaymentPerMinute;
  final int earlyLeaveDeductionPerMinute;

  factory EmployeeAttendancePayrollPolicy.fromJson(Map<String, dynamic> row) =>
      EmployeeAttendancePayrollPolicy(
        enabled: row['enabled'] == true,
        lateDeductionPerMinute: (row['late_deduction_per_minute_toman'] as num?)?.toInt() ?? 0,
        absenceDeductionPerDay: (row['absence_deduction_per_day_toman'] as num?)?.toInt() ?? 0,
        overtimePaymentPerMinute: (row['overtime_payment_per_minute_toman'] as num?)?.toInt() ?? 0,
        earlyLeaveDeductionPerMinute: (row['early_leave_deduction_per_minute_toman'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'late_deduction_per_minute_toman': lateDeductionPerMinute,
    'absence_deduction_per_day_toman': absenceDeductionPerDay,
    'overtime_payment_per_minute_toman': overtimePaymentPerMinute,
    'early_leave_deduction_per_minute_toman': earlyLeaveDeductionPerMinute,
  };
}

class EmployeeAttendanceSummary {
  const EmployeeAttendanceSummary({
    this.presentDays = 0,
    this.absentDays = 0,
    this.workedMinutes = 0,
    this.overtimeMinutes = 0,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
  });

  final int presentDays;
  final int absentDays;
  final int workedMinutes;
  final int overtimeMinutes;
  final int lateMinutes;
  final int earlyLeaveMinutes;
}
