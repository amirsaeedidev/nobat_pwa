import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/page_result.dart';
import '../../core/utils/jalali.dart';
import '../models/appointment.dart';
import '../models/enums.dart';
import 'appointment_repository.dart';

/// Appointment repository using the relational schema and the protected
/// create/status/reschedule RPCs. It never writes appointment rows directly.
class SupabaseRelationalAppointmentRepository implements AppointmentRepository {
  SupabaseRelationalAppointmentRepository({
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
      'id,reference,customer_id,employee_id,starts_at,ends_at,status,note,price_toman,reschedule_count,cancel_reason,created_at,updated_at,customers(full_name,phone),employees(full_name),appointment_services(service_id,title_snapshot,duration_minutes,price_toman,sort_order)';

  Appointment _model(Map<String, dynamic> row) {
    final customer = row['customers'] is Map
        ? Map<String, dynamic>.from(row['customers'] as Map)
        : <String, dynamic>{};
    final employee = row['employees'] is Map
        ? Map<String, dynamic>.from(row['employees'] as Map)
        : <String, dynamic>{};
    final services = (row['appointment_services'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((a, b) => ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0));
    final start = DateTime.parse(row['starts_at'] as String).toLocal();
    final end = DateTime.parse(row['ends_at'] as String).toLocal();
    final rawStatus = row['status'] as String? ?? 'pending';
    final status = rawStatus == 'rejected'
        ? AppointmentStatus.cancelled
        : AppointmentStatus.fromKey(rawStatus == 'no_show' ? 'noShow' : rawStatus);
    final serviceNames = services.map((item) => item['title_snapshot'] as String? ?? '').where((name) => name.isNotEmpty).toList();
    return Appointment(
      id: row['id'] as String,
      reference: row['reference'] as String? ?? '',
      customerId: row['customer_id'] as String,
      customerName: customer['full_name'] as String? ?? '',
      customerPhone: customer['phone'] as String? ?? '',
      serviceIds: services.map((item) => item['service_id'] as String).toList(growable: false),
      serviceName: serviceNames.join('، '),
      employeeId: row['employee_id'] as String,
      employeeName: employee['full_name'] as String? ?? '',
      startAt: start,
      durationMinutes: end.difference(start).inMinutes,
      status: status,
      note: row['note'] as String? ?? '',
      price: row['price_toman'] as num? ?? 0,
      createdAt: row['created_at'] == null ? null : DateTime.tryParse(row['created_at'] as String)?.toLocal(),
      updatedAt: row['updated_at'] == null ? null : DateTime.tryParse(row['updated_at'] as String)?.toLocal(),
      rescheduleCount: (row['reschedule_count'] as num?)?.toInt() ?? 0,
      cancelReason: row['cancel_reason'] as String?,
      serviceSnapshots: services.map((item) => {
        'service_id': item['service_id'],
        'title': item['title_snapshot'],
        'duration_minutes': item['duration_minutes'],
        'price': item['price_toman'],
      }).toList(growable: false),
    );
  }

  Future<List<Appointment>> _fetchAll() async {
    final tenant = _tenant();
    final rows = await _client.from('appointments').select(_columns)
        .eq('business_id', tenant).order('starts_at', ascending: false);
    return rows.map((row) => _model(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  @override
  Future<PageResult<Appointment>> fetchAppointments({
    AppointmentFilter filter = const AppointmentFilter(),
    int page = 1,
    int pageSize = 8,
    bool ascending = true,
  }) async {
    final items = await fetchAll(filter: filter);
    items.sort((a, b) => ascending ? a.startAt.compareTo(b.startAt) : b.startAt.compareTo(a.startAt));
    final start = (page - 1) * pageSize;
    return PageResult<Appointment>(
      items: items.skip(start).take(pageSize).toList(growable: false),
      total: items.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<Appointment>> fetchAll({AppointmentFilter filter = const AppointmentFilter()}) async {
    final items = await _fetchAll();
    return items.where(filter.matches).toList(growable: false);
  }

  @override
  Future<List<Appointment>> fetchForDay(DateTime day, {String? employeeId, String? serviceId}) async {
    final items = await _fetchAll();
    return items.where((item) =>
      item.startAt.year == day.year &&
      item.startAt.month == day.month &&
      item.startAt.day == day.day &&
      (employeeId == null || item.employeeId == employeeId) &&
      (serviceId == null || item.serviceIds.contains(serviceId)))
      .toList(growable: false);
  }

  @override
  Future<List<Appointment>> fetchForCustomer(String customerId) async =>
      (await _fetchAll()).where((item) => item.customerId == customerId).toList(growable: false);

  @override
  Future<Appointment?> findById(String id) async {
    final tenant = _tenant();
    final row = await _client.from('appointments').select(_columns)
        .eq('business_id', tenant).eq('id', id).maybeSingle();
    return row == null ? null : _model(Map<String, dynamic>.from(row));
  }

  @override
  Future<Appointment?> findConflict({
    required String employeeId,
    required DateTime startAt,
    required int durationMinutes,
    String? ignoreId,
  }) async {
    final tenant = _tenant();
    final endAt = startAt.add(Duration(minutes: durationMinutes));
    var query = _client.from('appointments').select('id')
        .eq('business_id', tenant)
        .eq('employee_id', employeeId)
        .inFilter('status', ['pending', 'confirmed'])
        .lt('starts_at', endAt.toUtc().toIso8601String())
        .gt('ends_at', startAt.toUtc().toIso8601String());
    if (ignoreId != null) query = query.neq('id', ignoreId);
    final rows = await query.limit(1);
    if (rows.isEmpty) return null;
    return findById(rows.first['id'] as String);
  }

  @override
  Future<void> create(Appointment appointment) async {
    final tenant = _tenant();
    await _client.rpc('create_appointment', params: {
      'p_business_id': tenant,
      'p_customer_id': appointment.customerId,
      'p_employee_id': appointment.employeeId,
      'p_starts_at': appointment.startAt.toUtc().toIso8601String(),
      'p_service_ids': appointment.serviceIds,
      'p_reference': appointment.reference,
      'p_note': appointment.note,
      'p_idempotency_key': appointment.id,
    });
  }

  @override
  Future<void> update(Appointment appointment) async {
    final current = await findById(appointment.id);
    if (current == null) throw StateError('نوبت مورد نظر پیدا نشد.');
    if (current.customerId != appointment.customerId ||
        current.employeeId != appointment.employeeId ||
        current.serviceIds.join('|') != appointment.serviceIds.join('|')) {
      throw UnsupportedError('تغییر مشتری، پرسنل یا خدمات نوبت تا زمان ارائه RPC ویرایش امن پشتیبانی نمی‌شود.');
    }
    if (current.startAt != appointment.startAt) {
      await reschedule(current, appointment.startAt);
    }
    if (current.note != appointment.note) {
      throw UnsupportedError('ویرایش توضیحات نوبت هنوز در RPC امن سمت سرور فعال نشده است.');
    }
    if (current.status != appointment.status) {
      await changeStatus(appointment, appointment.status);
    }
  }

  String _statusKey(AppointmentStatus status) => switch (status) {
    AppointmentStatus.noShow => 'no_show',
    AppointmentStatus.pending => 'pending',
    AppointmentStatus.confirmed => 'confirmed',
    AppointmentStatus.completed => 'completed',
    AppointmentStatus.cancelled => 'cancelled',
  };

  @override
  Future<void> changeStatus(Appointment appointment, AppointmentStatus status, {String? reason, String? operationType}) async {
    await _client.rpc('set_appointment_status', params: {
      'p_appointment_id': appointment.id,
      'p_status': _statusKey(status),
      'p_reason': reason,
    });
  }

  @override
  Future<void> reschedule(Appointment appointment, DateTime newStart, {bool byCustomer = false}) async {
    await _client.rpc('reschedule_appointment', params: {
      'p_appointment_id': appointment.id,
      'p_new_starts_at': newStart.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> delete(String id) async {
    await _client.rpc('set_appointment_status', params: {
      'p_appointment_id': id,
      'p_status': 'cancelled',
      'p_reason': 'حذف از پنل مدیریت',
    });
  }
}
