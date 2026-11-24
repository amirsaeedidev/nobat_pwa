import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';
import '../models/enums.dart';
import '../models/employee_schedule.dart';
import 'employee_repository.dart';

/// Tenant-scoped employee repository. All reads and writes use the active
/// Supabase session; RLS remains the final authorization boundary.
class SupabaseRelationalEmployeeRepository implements EmployeeRepository {
  SupabaseRelationalEmployeeRepository({
    required SupabaseClient client,
    required String? Function() businessId,
  })  : _client = client,
        _businessId = businessId;

  final SupabaseClient _client;
  final String? Function() _businessId;

  String _tenant() {
    if (_client.auth.currentUser == null) {
      throw StateError('نشست Supabase منقضی شده است؛ دوباره وارد شوید.');
    }
    final id = _businessId();
    if (id == null || id.isEmpty) {
      throw StateError('عضویت فعال مجموعه تأیید نشده است.');
    }
    return id;
  }

  static const _columns = '''
    id,full_name,phone,email,is_active,hired_on,terminated_on,notes,
    title,staff_role,employment_status,specialties,
    emergency_contact_name,emergency_contact_phone,schedule_enabled,buffer_minutes,
    employee_services(service_id,is_active),
    employee_working_hours(weekday,starts_at,ends_at,is_active,valid_from,valid_until)
  ''';

  Employee _model(Map<String, dynamic> row) {
    final serviceRows = (row['employee_services'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['is_active'] != false);
    final schedule = <int, List<Shift>>{};
    final hourRows = (row['employee_working_hours'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['is_active'] != false);
    for (final item in hourRows) {
      final pgWeekday = (item['weekday'] as num).toInt();
      final appWeekday = (pgWeekday + 1) % 7; // Saturday-first UI.
      schedule.putIfAbsent(appWeekday, () => []).add(Shift(
        start: (item['starts_at'] as String).substring(0, 5),
        end: (item['ends_at'] as String).substring(0, 5),
      ));
    }
    for (final shifts in schedule.values) {
      shifts.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    }
    final active = row['is_active'] as bool? ?? false;
    return Employee(
      id: row['id'] as String,
      fullName: row['full_name'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      email: row['email'] as String? ?? '',
      title: row['title'] as String? ?? '',
      role: StaffRole.fromKey(row['staff_role'] as String? ?? 'specialist'),
      isActive: active,
      status: EmployeeStatus.fromKey(
        row['employment_status'] as String? ?? (active ? 'active' : 'inactive'),
        isActive: active,
      ),
      serviceIds: serviceRows.map((item) => item['service_id'] as String).toList(growable: false),
      schedule: schedule,
      notes: row['notes'] as String? ?? '',
      startedAt: row['hired_on'] == null ? null : DateTime.tryParse(row['hired_on'] as String),
      specialties: (row['specialties'] as List? ?? const []).whereType<String>().toList(growable: false),
      emergencyContactName: row['emergency_contact_name'] as String? ?? '',
      emergencyContactPhone: row['emergency_contact_phone'] as String? ?? '',
      scheduleEnabled: row['schedule_enabled'] as bool? ?? true,
      bufferMinutes: (row['buffer_minutes'] as num?)?.toInt() ?? 0,
      // Ratings and appointment totals are not stored in the employee profile.
      // Keep them at zero rather than presenting fabricated defaults.
      bookedCount: 0,
      rating: 0,
    );
  }

  @override
  Future<List<Employee>> fetchEmployees({bool onlyActive = false, String? serviceId}) async {
    final tenant = _tenant();
    var request = _client.from('employees').select(_columns).eq('business_id', tenant);
    if (onlyActive) request = request.eq('is_active', true);
    if (serviceId != null) {
      final links = await _client.from('employee_services').select('employee_id')
          .eq('business_id', tenant).eq('service_id', serviceId).eq('is_active', true);
      final ids = links.map((row) => row['employee_id'] as String).toList();
      if (ids.isEmpty) return const [];
      request = request.inFilter('id', ids);
    }
    final rows = await request.order('full_name');
    return rows.map((row) => _model(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  @override
  Future<Employee?> findById(String id) async {
    final tenant = _tenant();
    final row = await _client.from('employees').select(_columns)
        .eq('business_id', tenant).eq('id', id).maybeSingle();
    return row == null ? null : _model(Map<String, dynamic>.from(row));
  }

  Future<List<Map<String, dynamic>>> _existingServiceRows(String employeeId) async {
    final tenant = _tenant();
    final rows = await _client.from('employee_services')
        .select('service_id,is_active,custom_price_toman,custom_duration_minutes,notes')
        .eq('business_id', tenant).eq('employee_id', employeeId);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  List<Map<String, dynamic>> _servicePayload(
    Employee employee,
    List<Map<String, dynamic>> existing,
  ) {
    final byId = <String, Map<String, dynamic>>{
      for (final row in existing) row['service_id'] as String: row,
    };
    return employee.serviceIds.toSet().map((serviceId) {
      final old = byId[serviceId];
      return <String, dynamic>{
        'service_id': serviceId,
        'is_active': old?['is_active'] ?? true,
        'custom_price_toman': old?['custom_price_toman'],
        'custom_duration_minutes': old?['custom_duration_minutes'],
        'notes': old?['notes'] ?? '',
      };
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _workingHoursPayload(Employee employee) {
    final rows = <Map<String, dynamic>>[];
    for (final entry in employee.schedule.entries) {
      final pgWeekday = (entry.key + 6) % 7;
      EmployeeScheduleRules.validateShifts(entry.value);
      for (final shift in entry.value) {
        rows.add({
          'weekday': pgWeekday,
          'starts_at': shift.start,
          'ends_at': shift.end,
          'is_active': true,
        });
      }
    }
    return rows;
  }

  Future<void> _save(Employee employee, {required bool create}) async {
    final tenant = _tenant();
    final oldServices = !create && employee.id.isNotEmpty
        ? await _existingServiceRows(employee.id)
        : const <Map<String, dynamic>>[];
    final profile = <String, dynamic>{
      'full_name': employee.fullName.trim(),
      'phone': employee.phone.trim().isEmpty ? null : employee.phone.trim(),
      'email': employee.email.trim().isEmpty ? null : employee.email.trim(),
      'is_active': employee.isActive,
      'hired_on': employee.startedAt?.toIso8601String().substring(0, 10),
      'notes': employee.notes,
      'title': employee.title.trim(),
      'staff_role': employee.role.key,
      'employment_status': employee.employmentStatus.name,
      'specialties': employee.specialties,
      'emergency_contact_name': employee.emergencyContactName.trim(),
      'emergency_contact_phone': employee.emergencyContactPhone.trim(),
      'schedule_enabled': employee.scheduleEnabled,
      'buffer_minutes': employee.bufferMinutes,
    };
    await _client.rpc('save_employee_profile', params: {
      'p_business_id': tenant,
      'p_employee_id': create ? null : employee.id,
      'p_profile': profile,
      'p_services': _servicePayload(employee, oldServices),
      'p_working_hours': _workingHoursPayload(employee),
    });
  }

  @override
  Future<void> create(Employee employee) => _save(employee, create: true);

  @override
  Future<void> update(Employee employee) => _save(employee, create: false);

  @override
  Future<void> delete(String id) async {
    final tenant = _tenant();
    final now = DateTime.now().toIso8601String().substring(0, 10);
    final result = await _client.from('employees').update({
      'is_active': false,
      'employment_status': 'inactive',
      'terminated_on': now,
    }).eq('business_id', tenant).eq('id', id).select('id');
    if (result.isEmpty) throw StateError('پرسنل پیدا نشد یا مجوز بایگانی ندارید.');
  }

  @override
  Future<List<EmployeeScheduleException>> fetchScheduleExceptions({
    required String employeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final tenant = _tenant();
    final rows = await _client.from('employee_schedule_exceptions')
        .select('employee_id,work_date,is_available,starts_at,ends_at,reason')
        .eq('business_id', tenant).eq('employee_id', employeeId)
        .gte('work_date', _date(from)).lte('work_date', _date(to))
        .order('work_date');
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      grouped.putIfAbsent(row['work_date'] as String, () => []).add(row);
    }
    return grouped.entries.map((entry) {
      final items = entry.value;
      final closed = items.any((item) => item['is_available'] == false);
      final shifts = closed ? const <Shift>[] : items.map((item) => Shift(
        start: (item['starts_at'] as String).substring(0, 5),
        end: (item['ends_at'] as String).substring(0, 5),
      )).toList(growable: false);
      return EmployeeScheduleException(
        employeeId: employeeId,
        dateKey: entry.key,
        title: (items.first['reason'] as String?) ?? 'ساعات ویژه',
        isClosed: closed,
        shifts: shifts,
      );
    }).toList(growable: false);
  }

  @override
  Future<void> saveScheduleException(EmployeeScheduleException exception) async {
    final tenant = _tenant();
    EmployeeScheduleRules.validateShifts(exception.shifts);
    await _client.rpc('replace_employee_schedule_exception', params: {
      'p_business_id': tenant,
      'p_employee_id': exception.employeeId,
      'p_work_date': exception.dateKey,
      'p_is_closed': exception.isClosed,
      'p_reason': exception.title,
      'p_shifts': exception.isClosed ? const [] : exception.shifts.map((shift) => {
        'starts_at': shift.start,
        'ends_at': shift.end,
      }).toList(growable: false),
    });
  }

  @override
  Future<void> deleteScheduleException(String employeeId, String dateKey) async {
    final tenant = _tenant();
    await _client.from('employee_schedule_exceptions').delete()
        .eq('business_id', tenant).eq('employee_id', employeeId).eq('work_date', dateKey);
  }

  @override
  Future<List<EmployeeLeave>> fetchLeaves(String employeeId) async {
    final tenant = _tenant();
    final rows = await _client.from('employee_leaves')
        .select('id,employee_id,starts_at,ends_at,leave_type,status,description,created_at,reviewed_by')
        .eq('business_id', tenant).eq('employee_id', employeeId)
        .order('starts_at', ascending: false);
    return rows.map((raw) {
      final row = Map<String, dynamic>.from(raw);
      final typeKey = switch (row['leave_type'] as String) {
        'hourly' => EmployeeLeaveType.hourly,
        'multi_day' => EmployeeLeaveType.multiDay,
        'emergency' => EmployeeLeaveType.emergency,
        'other' => EmployeeLeaveType.holiday,
        _ => EmployeeLeaveType.daily,
      };
      final statusKey = switch (row['status'] as String) {
        'approved' => EmployeeLeaveStatus.approved,
        'rejected' => EmployeeLeaveStatus.rejected,
        'cancelled' => EmployeeLeaveStatus.cancelled,
        _ => EmployeeLeaveStatus.pending,
      };
      return EmployeeLeave(
        id: row['id'] as String,
        employeeId: row['employee_id'] as String,
        startAt: DateTime.parse(row['starts_at'] as String).toLocal(),
        endAt: DateTime.parse(row['ends_at'] as String).toLocal(),
        type: typeKey,
        status: statusKey,
        description: row['description'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        approvedBy: row['reviewed_by'] as String?,
      );
    }).toList(growable: false);
  }

  @override
  Future<void> createLeave(EmployeeLeave leave) async {
    final tenant = _tenant();
    final type = switch (leave.type) {
      EmployeeLeaveType.hourly => 'hourly',
      EmployeeLeaveType.multiDay => 'multi_day',
      EmployeeLeaveType.emergency => 'emergency',
      EmployeeLeaveType.holiday => 'other',
      EmployeeLeaveType.daily => 'daily',
    };
    await _client.from('employee_leaves').insert({
      'business_id': tenant,
      'employee_id': leave.employeeId,
      'starts_at': leave.startAt.toUtc().toIso8601String(),
      'ends_at': leave.endAt.toUtc().toIso8601String(),
      'leave_type': type,
      'status': 'pending',
      'description': leave.description.trim(),
    });
  }

  @override
  Future<void> reviewLeave(EmployeeLeave leave) async {
    final tenant = _tenant();
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('نشست کاربر معتبر نیست.');
    final status = switch (leave.status) {
      EmployeeLeaveStatus.approved => 'approved',
      EmployeeLeaveStatus.rejected => 'rejected',
      EmployeeLeaveStatus.cancelled => 'cancelled',
      EmployeeLeaveStatus.pending => 'pending',
    };
    final result = await _client.from('employee_leaves').update({
      'status': status,
      'reviewed_by': userId,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('business_id', tenant).eq('employee_id', leave.employeeId)
      .eq('id', leave.id).eq('status', 'pending').select('id');
    if (result.isEmpty) throw StateError('درخواست مرخصی تغییر نکرد؛ شاید قبلاً بررسی شده باشد.');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
