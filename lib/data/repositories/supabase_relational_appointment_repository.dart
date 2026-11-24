import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/page_result.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/fa_num.dart';
import '../models/appointment.dart';
import '../models/enums.dart';
import 'appointment_repository.dart';

/// Supabase appointment repository. All writes go through atomic database RPCs;
/// list filtering, search and pagination are executed in PostgreSQL.
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
      'id,reference,customer_id,employee_id,starts_at,ends_at,status,note,price_toman,discount_toman,reschedule_count,cancel_reason,created_by,created_at,updated_at,deleted_at,customers(full_name,phone),employees(full_name),appointment_services(service_id,title_snapshot,category_snapshot,description_snapshot,direct_cost_toman_snapshot,duration_minutes,price_toman,list_price_toman_snapshot,discount_toman_snapshot,commission_rate_bps_snapshot,fixed_commission_amount_toman_snapshot,sort_order)';

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
      ..sort((a, b) => ((a['sort_order'] as num?) ?? 0)
          .compareTo((b['sort_order'] as num?) ?? 0));
    final start = DateTime.parse(row['starts_at'] as String).toLocal();
    final end = DateTime.parse(row['ends_at'] as String).toLocal();
    final rawStatus = row['status'] as String? ?? 'pending';
    final status = rawStatus == 'rejected'
        ? AppointmentStatus.cancelled
        : AppointmentStatus.fromKey(rawStatus == 'no_show' ? 'noShow' : rawStatus);
    final serviceNames = services
        .map((item) => item['title_snapshot'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    return Appointment(
      id: row['id'] as String,
      reference: row['reference'] as String? ?? '',
      customerId: row['customer_id'] as String,
      customerName: customer['full_name'] as String? ?? '',
      customerPhone: customer['phone'] as String? ?? '',
      serviceIds: services
          .map((item) => item['service_id'] as String)
          .toList(growable: false),
      serviceName: serviceNames.join('، '),
      employeeId: row['employee_id'] as String,
      employeeName: employee['full_name'] as String? ?? '',
      startAt: start,
      durationMinutes: end.difference(start).inMinutes,
      status: status,
      note: row['note'] as String? ?? '',
      price: (row['price_toman'] as num? ?? 0) - (row['discount_toman'] as num? ?? 0),
      discount: row['discount_toman'] as num? ?? 0,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.tryParse(row['created_at'] as String)?.toLocal(),
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.tryParse(row['updated_at'] as String)?.toLocal(),
      rescheduleCount: (row['reschedule_count'] as num?)?.toInt() ?? 0,
      cancelReason: row['cancel_reason'] as String?,
      createdBy: row['created_by'] as String? ?? 'سیستم',
      serviceSnapshots: services
          .map((item) => <String, dynamic>{
                'service_id': item['service_id'],
                'title': item['title_snapshot'],
                'category': item['category_snapshot'],
                'description': item['description_snapshot'],
                'direct_cost': item['direct_cost_toman_snapshot'],
                'duration_minutes': item['duration_minutes'],
                'price': item['price_toman'],
                'list_price': item['list_price_toman_snapshot'],
                'discount': item['discount_toman_snapshot'],
                'commission_rate_bps': item['commission_rate_bps_snapshot'],
                'fixed_commission_amount': item['fixed_commission_amount_toman_snapshot'],
              })
          .toList(growable: false),
    );
  }

  DateTime? _fromUtc(AppointmentFilter filter) =>
      filter.fromDate?.toDateTime().toUtc();

  DateTime? _toUtc(AppointmentFilter filter) =>
      filter.toDate?.addDays(1).toDateTime().toUtc();

  Future<PageResult<Appointment>> _fetchPage({
    AppointmentFilter filter = const AppointmentFilter(),
    int page = 1,
    int pageSize = 20,
    bool ascending = false,
    String? customerId,
  }) async {
    final tenant = _tenant();
    final response = await _client.rpc('list_appointments', params: {
      'p_business_id': tenant,
      'p_query': FaNum.toLatin(filter.query.trim()),
      'p_status': filter.status == null ? null : _statusKey(filter.status!),
      'p_service_id': filter.serviceId,
      'p_employee_id': filter.employeeId,
      'p_customer_id': customerId,
      'p_from': _fromUtc(filter)?.toIso8601String(),
      'p_to': _toUtc(filter)?.toIso8601String(),
      'p_page': page,
      'p_page_size': pageSize.clamp(1, 100),
      'p_ascending': ascending,
    });

    final payload = Map<String, dynamic>.from(response as Map);
    final rows = (payload['items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => _model(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return PageResult<Appointment>(
      items: rows,
      total: (payload['total'] as num?)?.toInt() ?? 0,
      page: (payload['page'] as num?)?.toInt() ?? page,
      pageSize: (payload['page_size'] as num?)?.toInt() ?? pageSize,
    );
  }

  Future<List<Appointment>> _fetchAll({
    AppointmentFilter filter = const AppointmentFilter(),
    String? customerId,
  }) async {
    const pageSize = 100;
    final all = <Appointment>[];
    var page = 1;
    var total = 0;
    do {
      final result = await _fetchPage(
        filter: filter,
        page: page,
        pageSize: pageSize,
        ascending: false,
        customerId: customerId,
      );
      if (result.items.isEmpty) break;
      all.addAll(result.items);
      total = result.total;
      page++;
    } while (all.length < total);
    return all;
  }

  @override
  Future<PageResult<Appointment>> fetchAppointments({
    AppointmentFilter filter = const AppointmentFilter(),
    int page = 1,
    int pageSize = 8,
    bool ascending = true,
  }) =>
      _fetchPage(
        filter: filter,
        page: page,
        pageSize: pageSize,
        ascending: ascending,
      );

  @override
  Future<List<Appointment>> fetchAll({
    AppointmentFilter filter = const AppointmentFilter(),
  }) =>
      _fetchAll(filter: filter);

  @override
  Future<List<Appointment>> fetchForDay(
    DateTime day, {
    String? employeeId,
    String? serviceId,
  }) {
    final jalali = JalaliDate.fromDateTime(day);
    return _fetchAll(
      filter: AppointmentFilter(
        employeeId: employeeId,
        serviceId: serviceId,
        fromDate: jalali,
        toDate: jalali,
      ),
    );
  }

  @override
  Future<List<Appointment>> fetchForCustomer(String customerId) =>
      _fetchAll(customerId: customerId);

  @override
  Future<Appointment?> findById(String id) async {
    _tenant();
    final result = await _fetchPage(
      filter: AppointmentFilter(query: id),
      page: 1,
      pageSize: 1,
    );
    for (final appointment in result.items) {
      if (appointment.id == id) return appointment;
    }
    return null;
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
    var query = _client
        .from('appointments')
        .select('id')
        .eq('business_id', tenant)
        .eq('employee_id', employeeId)
        .isFilter('deleted_at', null)
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

    await _client.rpc('update_appointment', params: {
      'p_appointment_id': appointment.id,
      'p_customer_id': appointment.customerId,
      'p_employee_id': appointment.employeeId,
      'p_starts_at': appointment.startAt.toUtc().toIso8601String(),
      'p_service_ids': appointment.serviceIds,
      'p_note': appointment.note,
    });

    if (current.status != appointment.status) {
      await changeStatus(
        appointment,
        appointment.status,
      );
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
  Future<void> changeStatus(
    Appointment appointment,
    AppointmentStatus status, {
    String? reason,
    String? operationType,
  }) async {
    await _client.rpc('set_appointment_status', params: {
      'p_appointment_id': appointment.id,
      'p_status': operationType == 'appointment_reject'
          ? 'rejected'
          : _statusKey(status),
      'p_reason': reason,
    });
  }

  @override
  Future<void> reschedule(
    Appointment appointment,
    DateTime newStart, {
    bool byCustomer = false,
  }) async {
    await _client.rpc('reschedule_appointment', params: {
      'p_appointment_id': appointment.id,
      'p_new_starts_at': newStart.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> delete(String id) async {
    await _client.rpc('delete_appointment', params: {
      'p_appointment_id': id,
      'p_reason': 'حذف امن از پنل مدیریت',
    });
  }
}
