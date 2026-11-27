import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_attendance.dart';

/// Attendance ledger backed exclusively by public.employee_attendance_records.
/// Rows are append-only; corrections are new records linked to the source row.
class SupabaseEmployeeAttendanceRepository {
  SupabaseEmployeeAttendanceRepository({
    required SupabaseClient client,
    required String? Function() businessId,
  }) : _client = client, _businessId = businessId;

  final SupabaseClient _client;
  final String? Function() _businessId;

  String _tenant() {
    if (_client.auth.currentUser == null) {
      throw StateError('نشست Supabase معتبر نیست؛ دوباره وارد شوید.');
    }
    final value = _businessId();
    if (value == null || value.isEmpty) {
      throw StateError('عضویت فعال مجموعه تأیید نشده است.');
    }
    return value;
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<List<EmployeeAttendanceRecord>> fetchRecords({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final tenant = _tenant();
    final rows = await _client.from('employee_attendance_records')
        .select('id,employee_id,work_date,event_type,occurred_at,note,late_minutes,overtime_minutes,early_leave_minutes,worked_minutes,correction_of_id')
        .eq('business_id', tenant)
        .eq('employee_id', employeeId)
        .gte('work_date', _date(from))
        .lte('work_date', _date(to))
        .order('work_date', ascending: false)
        .order('occurred_at', ascending: false);
    return rows.map((row) => EmployeeAttendanceRecord.fromJson(
      Map<String, dynamic>.from(row),
    )).toList(growable: false);
  }

  Future<String> record({
    required String employeeId,
    required EmployeeAttendanceEventType type,
    required DateTime workDate,
    DateTime? occurredAt,
    String note = '',
    int lateMinutes = 0,
    int overtimeMinutes = 0,
    int earlyLeaveMinutes = 0,
    int workedMinutes = 0,
    String? correctionOfId,
  }) async {
    final tenant = _tenant();
    if (lateMinutes < 0 || overtimeMinutes < 0 ||
        earlyLeaveMinutes < 0 || workedMinutes < 0) {
      throw ArgumentError('مقادیر دقیقه نمی‌توانند منفی باشند.');
    }
    final timestamp = occurredAt ?? DateTime.now();
    final idempotencyKey = 'attendance:$employeeId:${type.key}:${timestamp.microsecondsSinceEpoch}';
    final row = await _client.from('employee_attendance_records').insert({
      'business_id': tenant,
      'employee_id': employeeId,
      'work_date': _date(workDate),
      'event_type': type.key,
      'occurred_at': timestamp.toUtc().toIso8601String(),
      'note': note.trim(),
      'late_minutes': lateMinutes,
      'overtime_minutes': overtimeMinutes,
      'early_leave_minutes': earlyLeaveMinutes,
      'worked_minutes': workedMinutes,
      'correction_of_id': correctionOfId,
      'idempotency_key': idempotencyKey,
    }).select('id').single();
    return row['id'].toString();
  }

  Future<EmployeeAttendancePayrollPolicy> fetchPayrollPolicy() async {
    final tenant = _tenant();
    final row = await _client.from('employee_attendance_payroll_policies')
        .select('enabled,late_deduction_per_minute_toman,absence_deduction_per_day_toman,overtime_payment_per_minute_toman,early_leave_deduction_per_minute_toman')
        .eq('business_id', tenant).maybeSingle();
    return row == null
        ? const EmployeeAttendancePayrollPolicy()
        : EmployeeAttendancePayrollPolicy.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> savePayrollPolicy(EmployeeAttendancePayrollPolicy policy) async {
    final tenant = _tenant();
    final userId = _client.auth.currentUser!.id;
    await _client.from('employee_attendance_payroll_policies').upsert({
      'business_id': tenant,
      ...policy.toJson(),
      'updated_by': userId,
    }, onConflict: 'business_id');
  }

  EmployeeAttendanceSummary summarize(
    List<EmployeeAttendanceRecord> records, {
    required DateTime from,
    required DateTime to,
  }) {
    final days = <String>{};
    final absent = <String>{};
    var worked = 0, overtime = 0, late = 0, early = 0;
    for (final record in records) {
      if (record.workDate.isBefore(from) ||
          record.workDate.isAfter(DateTime(to.year, to.month, to.day))) continue;
      final key = _date(record.workDate);
      if (record.type == EmployeeAttendanceEventType.checkIn ||
          record.type == EmployeeAttendanceEventType.checkOut ||
          record.type == EmployeeAttendanceEventType.manualCorrection) {
        days.add(key);
      }
      if (record.type == EmployeeAttendanceEventType.absence) absent.add(key);
      worked += record.workedMinutes;
      overtime += record.overtimeMinutes;
      late += record.lateMinutes;
      early += record.earlyLeaveMinutes;
    }
    return EmployeeAttendanceSummary(
      presentDays: days.length,
      absentDays: absent.length,
      workedMinutes: worked,
      overtimeMinutes: overtime,
      lateMinutes: late,
      earlyLeaveMinutes: early,
    );
  }
}
