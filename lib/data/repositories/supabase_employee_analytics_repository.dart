import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_performance_report.dart';

/// Reads the real daily performance projection and the relational schedule
/// sources. It never falls back to local/demo data.
class SupabaseEmployeeAnalyticsRepository {
  SupabaseEmployeeAnalyticsRepository({
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

  int _minutes(String? value) {
    if (value == null || value.isEmpty) return 0;
    final parts = value.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  Future<EmployeePerformanceReport> fetchReport({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final tenant = _tenant();
    final start = DateTime(from.year, from.month, from.day);
    final endExclusive = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    if (!start.isBefore(endExclusive)) throw ArgumentError('بازه گزارش معتبر نیست.');

    final rows = await _client.from('employee_performance_daily')
        .select()
        .eq('business_id', tenant)
        .eq('employee_id', employeeId)
        .gte('work_date', _date(start))
        .lt('work_date', _date(endExclusive))
        .order('work_date');
    final days = rows.map((row) => EmployeePerformanceDay.fromJson(
      Map<String, dynamic>.from(row),
    )).toList(growable: false);

    final customerRows = await _client.from('appointments')
        .select('customer_id')
        .eq('business_id', tenant)
        .eq('employee_id', employeeId)
        .gte('starts_at', start.toUtc().toIso8601String())
        .lt('starts_at', endExclusive.toUtc().toIso8601String())
        .eq('status', 'completed');
    final customers = customerRows
        .map((row) => row['customer_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final scheduleMinutes = await _scheduledMinutes(
      tenant: tenant,
      employeeId: employeeId,
      from: start,
      toExclusive: endExclusive,
    );

    int sum(int Function(EmployeePerformanceDay) get) =>
        days.fold<int>(0, (total, day) => total + get(day));
    final attendanceAvailable = days.any((day) => day.attendanceAvailable);
    return EmployeePerformanceReport(
      days: days,
      totalAppointments: sum((day) => day.appointments),
      completed: sum((day) => day.completed),
      cancelled: sum((day) => day.cancelled),
      noShow: sum((day) => day.noShow),
      uniqueCustomers: customers.length,
      grossRevenue: sum((day) => day.grossRevenue),
      netRevenue: sum((day) => day.netRevenue),
      commission: sum((day) => day.commission),
      companyShare: sum((day) => day.companyShare),
      bookedMinutes: sum((day) => day.bookedMinutes),
      scheduledMinutes: scheduleMinutes,
      attendanceAvailable: attendanceAvailable,
      presentDays: days.where((day) => day.attendanceAvailable).length,
      absentDays: sum((day) => day.absentDays),
      workedMinutes: sum((day) => day.workedMinutes),
      lateMinutes: sum((day) => day.lateMinutes),
      overtimeMinutes: sum((day) => day.overtimeMinutes),
      earlyLeaveMinutes: sum((day) => day.earlyLeaveMinutes),
      leaveCount: sum((day) => day.leaveCount),
      earned: sum((day) => day.earned),
      bonus: sum((day) => day.bonus),
      deduction: sum((day) => day.deduction),
      advance: sum((day) => day.advance),
      salaryPaid: sum((day) => day.salaryPaid),
      walletBalanceDelta: sum((day) => day.walletDelta),
    );
  }

  Future<int> _scheduledMinutes({
    required String tenant,
    required String employeeId,
    required DateTime from,
    required DateTime toExclusive,
  }) async {
    final hours = await _client.from('employee_working_hours')
        .select('weekday,starts_at,ends_at,break_starts_at,break_ends_at,is_active,valid_from,valid_until')
        .eq('business_id', tenant)
        .eq('employee_id', employeeId);
    final exceptions = await _client.from('employee_schedule_exceptions')
        .select('work_date,is_available,starts_at,ends_at')
        .eq('business_id', tenant)
        .eq('employee_id', employeeId)
        .gte('work_date', _date(from))
        .lt('work_date', _date(toExclusive));
    final holidays = await _client.from('business_holidays')
        .select('holiday_date')
        .eq('business_id', tenant)
        .gte('holiday_date', _date(from))
        .lt('holiday_date', _date(toExclusive));
    final leaves = await _client.from('employee_leaves')
        .select('starts_at,ends_at,status')
        .eq('business_id', tenant)
        .eq('employee_id', employeeId)
        .eq('status', 'approved')
        .lt('starts_at', toExclusive.toUtc().toIso8601String())
        .gt('ends_at', from.toUtc().toIso8601String());

    final exceptionMap = <String, List<Map<String, dynamic>>>{};
    for (final raw in exceptions) {
      final item = Map<String, dynamic>.from(raw);
      exceptionMap.putIfAbsent(item['work_date'].toString(), () => []).add(item);
    }
    final holidayDates = holidays.map((row) => row['holiday_date'].toString()).toSet();
    var total = 0;
    for (var day = from; day.isBefore(toExclusive); day = day.add(const Duration(days: 1))) {
      final key = _date(day);
      if (holidayDates.contains(key)) continue;
      final dayExceptions = exceptionMap[key];
      var minutes = 0;
      if (dayExceptions != null && dayExceptions.isNotEmpty) {
        if (dayExceptions.any((item) => item['is_available'] == false)) continue;
        for (final item in dayExceptions) {
          final start = _minutes(item['starts_at']?.toString());
          final end = _minutes(item['ends_at']?.toString());
          if (end > start) minutes += end - start;
        }
      } else {
        final pgWeekday = day.weekday % 7;
        for (final raw in hours) {
          final item = Map<String, dynamic>.from(raw);
          if (item['is_active'] != true ||
              (item['weekday'] as num).toInt() != pgWeekday) continue;
          final validFrom = item['valid_from'] == null
              ? null : DateTime.parse(item['valid_from'].toString());
          final validUntil = item['valid_until'] == null
              ? null : DateTime.parse(item['valid_until'].toString());
          if (validFrom != null && day.isBefore(validFrom)) continue;
          if (validUntil != null && day.isAfter(validUntil)) continue;
          final shiftStart = _minutes(item['starts_at']?.toString());
          final shiftEnd = _minutes(item['ends_at']?.toString());
          if (shiftEnd <= shiftStart) continue;
          var shift = shiftEnd - shiftStart;
          final breakStart = _minutes(item['break_starts_at']?.toString());
          final breakEnd = _minutes(item['break_ends_at']?.toString());
          if (breakEnd > breakStart && breakStart >= shiftStart && breakEnd <= shiftEnd) {
            shift -= breakEnd - breakStart;
          }
          minutes += shift;
        }
      }
      final dayStart = day;
      final dayEnd = day.add(const Duration(days: 1));
      for (final raw in leaves) {
        final item = Map<String, dynamic>.from(raw);
        final leaveStart = DateTime.parse(item['starts_at'].toString()).toLocal();
        final leaveEnd = DateTime.parse(item['ends_at'].toString()).toLocal();
        if (!leaveStart.isBefore(dayEnd) || !leaveEnd.isAfter(dayStart)) continue;
        final overlapStart = leaveStart.isAfter(dayStart) ? leaveStart : dayStart;
        final overlapEnd = leaveEnd.isBefore(dayEnd) ? leaveEnd : dayEnd;
        minutes -= overlapEnd.difference(overlapStart).inMinutes;
      }
      total += minutes.clamp(0, 1440);
    }
    return total;
  }
}
