import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';
import '../models/employee_schedule.dart';
import 'employee_repository.dart';

/// Tenant-scoped staff repository using employees, employee_services and
/// employee_working_hours. Authorization is always re-evaluated by RLS.
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

  static const _columns =
      'id,full_name,phone,email,is_active,hired_on,notes,employee_services(service_id,is_active),employee_working_hours(weekday,starts_at,ends_at,is_active)';

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
    return Employee(
      id: row['id'] as String,
      fullName: row['full_name'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      email: row['email'] as String? ?? '',
      isActive: row['is_active'] as bool? ?? false,
      status: EmployeeStatus.fromKey(
        (row['is_active'] as bool? ?? false) ? 'active' : 'inactive',
        isActive: row['is_active'] as bool? ?? false,
      ),
      serviceIds: serviceRows.map((item) => item['service_id'] as String).toList(growable: false),
      schedule: schedule,
      notes: row['notes'] as String? ?? '',
      startedAt: row['hired_on'] == null ? null : DateTime.tryParse(row['hired_on'] as String),
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

  Future<void> _syncServices(String employeeId, List<String> serviceIds) async {
    final tenant = _tenant();
    final existing = await _client.from('employee_services').select('service_id')
        .eq('business_id', tenant).eq('employee_id', employeeId);
    final oldIds = existing.map((row) => row['service_id'] as String).toSet();
    final nextIds = serviceIds.toSet();
    final removeIds = oldIds.difference(nextIds);
    if (removeIds.isNotEmpty) {
      await _client.from('employee_services').delete()
          .eq('business_id', tenant).eq('employee_id', employeeId)
          .inFilter('service_id', removeIds.toList());
    }
    final addIds = nextIds.difference(oldIds);
    if (addIds.isNotEmpty) {
      await _client.from('employee_services').insert(addIds.map((serviceId) => {
        'business_id': tenant,
        'employee_id': employeeId,
        'service_id': serviceId,
      }).toList());
    }
  }

  Future<void> _syncSchedule(String employeeId, Map<int, List<Shift>> schedule) async {
    final tenant = _tenant();
    await _client.from('employee_working_hours').delete()
        .eq('business_id', tenant).eq('employee_id', employeeId);
    final rows = <Map<String, dynamic>>[];
    for (final entry in schedule.entries) {
      final pgWeekday = (entry.key + 6) % 7;
      for (final shift in entry.value) {
        EmployeeScheduleRules.validateShifts([shift]);
        rows.add({
          'business_id': tenant,
          'employee_id': employeeId,
          'weekday': pgWeekday,
          'starts_at': shift.start,
          'ends_at': shift.end,
          'is_active': true,
        });
      }
    }
    if (rows.isNotEmpty) await _client.from('employee_working_hours').insert(rows);
  }

  @override
  Future<void> create(Employee employee) async {
    final tenant = _tenant();
    final inserted = await _client.from('employees').insert({
      'business_id': tenant,
      'full_name': employee.fullName.trim(),
      'phone': employee.phone.trim().isEmpty ? null : employee.phone.trim(),
      'email': employee.email.trim().isEmpty ? null : employee.email.trim(),
      'is_active': employee.isActive,
      'hired_on': employee.startedAt?.toIso8601String().substring(0, 10),
      'notes': employee.notes,
    }).select('id').single();
    final id = inserted['id'] as String;
    await _syncServices(id, employee.serviceIds);
    await _syncSchedule(id, employee.schedule);
  }

  @override
  Future<void> update(Employee employee) async {
    final tenant = _tenant();
    await _client.from('employees').update({
      'full_name': employee.fullName.trim(),
      'phone': employee.phone.trim().isEmpty ? null : employee.phone.trim(),
      'email': employee.email.trim().isEmpty ? null : employee.email.trim(),
      'is_active': employee.isActive,
      'hired_on': employee.startedAt?.toIso8601String().substring(0, 10),
      'notes': employee.notes,
    }).eq('business_id', tenant).eq('id', employee.id);
    await _syncServices(employee.id, employee.serviceIds);
    await _syncSchedule(employee.id, employee.schedule);
  }

  @override
  Future<void> delete(String id) async {
    final tenant = _tenant();
    // Preserve appointment and financial history; archive the staff record.
    await _client.from('employees').update({
      'is_active': false,
      'terminated_on': DateTime.now().toIso8601String().substring(0, 10),
    }).eq('business_id', tenant).eq('id', id);
  }
}
