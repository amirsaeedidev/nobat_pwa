import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_service_config.dart';
import '../models/service.dart';
import 'service_repository.dart';

/// Normalized service catalog repository backed by public.services,
/// public.service_categories and public.employee_services.
class SupabaseRelationalServiceRepository implements ServiceRepository {
  SupabaseRelationalServiceRepository({
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

  Service _model(Map<String, dynamic> row) {
    final links = (row['employee_services'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['is_active'] != false)
        .map((item) => item['employee_id'] as String)
        .toList(growable: false);
    return Service(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      price: row['price_toman'] as num? ?? 0,
      durationMinutes: (row['duration_minutes'] as num?)?.toInt() ?? 0,
      bufferMinutes: (row['buffer_minutes'] as num?)?.toInt() ?? 0,
      prepMinutes: (row['prep_minutes'] as num?)?.toInt() ?? 0,
      directCost: row['direct_cost_toman'] as num?,
      imageUrl: row['image_url'] as String?,
      discountPrice: row['discount_price_toman'] as num?,
      discountStartsAt: row['discount_starts_on'] == null ? null : DateTime.tryParse(row['discount_starts_on'] as String),
      discountEndsAt: row['discount_ends_on'] == null ? null : DateTime.tryParse(row['discount_ends_on'] as String),
      maxPerDay: (row['max_per_day'] as num?)?.toInt(),
      advanceDays: (row['advance_days'] as num?)?.toInt() ?? 30,
      requiresConfirmation: row['requires_confirmation'] as bool? ?? false,
      isActive: row['is_active'] as bool? ?? false,
      employeeIds: links,
      category: row['category'] as String? ?? '',
      order: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  static const _columns =
      'id,title,category,description,duration_minutes,price_toman,is_active,sort_order,direct_cost_toman,image_url,discount_price_toman,discount_starts_on,discount_ends_on,prep_minutes,buffer_minutes,max_per_day,advance_days,requires_confirmation,employee_services(employee_id,is_active)';

  @override
  Future<List<Service>> fetchServices({bool onlyActive = false, String query = ''}) async {
    final tenant = _tenant();
    var request = _client.from('services').select(_columns).eq('business_id', tenant);
    if (onlyActive) request = request.eq('is_active', true);
    final normalized = query.trim();
    if (normalized.isNotEmpty) {
      final safe = normalized.replaceAll(',', '').replaceAll('%', r'\%').replaceAll('_', r'\_');
      request = request.or('title.ilike.%$safe%,category.ilike.%$safe%');
    }
    final rows = await request.order('sort_order');
    return rows.map((row) => _model(Map<String, dynamic>.from(row))).toList(growable: false);
  }

  @override
  Future<Service?> findById(String id) async {
    final tenant = _tenant();
    final row = await _client.from('services').select(_columns)
        .eq('business_id', tenant).eq('id', id).maybeSingle();
    return row == null ? null : _model(Map<String, dynamic>.from(row));
  }

  Map<String, dynamic> _servicePayload(Service service) => {
    'title': service.title.trim(),
    'category': service.category.trim(),
    'description': service.description,
    'duration_minutes': service.durationMinutes,
    'price_toman': service.price,
    'is_active': service.isActive,
    'sort_order': service.order,
    'direct_cost_toman': service.directCost,
    'image_url': service.imageUrl,
    'discount_price_toman': service.discountPrice,
    'discount_starts_on': service.discountStartsAt == null ? null : _dateOnly(service.discountStartsAt!),
    'discount_ends_on': service.discountEndsAt == null ? null : _dateOnly(service.discountEndsAt!),
    'prep_minutes': service.prepMinutes,
    'buffer_minutes': service.bufferMinutes,
    'max_per_day': service.maxPerDay,
    'advance_days': service.advanceDays,
    'requires_confirmation': service.requiresConfirmation,
  };

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Future<void> create(Service service) async {
    final configs = service.employeeIds.map((employeeId) => EmployeeServiceConfig(
      employeeId: employeeId, serviceId: service.id,
    )).toList(growable: false);
    await saveCatalogItem(service, configs);
  }

  @override
  Future<void> update(Service service) async {
    final tenant = _tenant();
    final categoryId = service.category.trim().isEmpty
        ? null
        : await _ensureCategory(service.category.trim());
    await _client.from('services').update({
      'category_id': categoryId,
      ..._servicePayload(service),
    }).eq('business_id', tenant).eq('id', service.id);
    await _syncEmployeeLinks(service.id, service.employeeIds);
  }

  @override
  Future<String> saveCatalogItem(
    Service service,
    List<EmployeeServiceConfig> configs,
  ) async {
    final tenant = _tenant();
    final serviceId = service.id.startsWith('srv-') ? null : service.id;
    final result = await _client.rpc('save_service_catalog_item', params: {
      'p_business_id': tenant,
      'p_service_id': serviceId,
      'p_service': _servicePayload(service),
      'p_employee_configs': configs.map((config) => {
        'employee_id': config.employeeId,
        'is_active': config.active,
        'custom_price_toman': config.customPrice,
        'custom_duration_minutes': config.customDurationMinutes,
        'commission_rate_bps': config.commissionRateBps,
        'fixed_commission_amount_toman': config.fixedCommissionAmount,
        'notes': config.specialtyNote,
      }).toList(growable: false),
    });
    return result as String;
  }

  Future<void> _syncEmployeeLinks(String serviceId, List<String> employeeIds) async {
    final tenant = _tenant();
    final existing = await _client.from('employee_services').select('employee_id')
        .eq('business_id', tenant).eq('service_id', serviceId);
    final oldIds = existing.map((row) => row['employee_id'] as String).toSet();
    final nextIds = employeeIds.toSet();
    final removeIds = oldIds.difference(nextIds);
    if (removeIds.isNotEmpty) {
      await _client.from('employee_services').delete()
          .eq('business_id', tenant).eq('service_id', serviceId)
          .inFilter('employee_id', removeIds.toList());
    }
    final addIds = nextIds.difference(oldIds);
    if (addIds.isNotEmpty) {
      await _client.from('employee_services').insert(addIds.map((employeeId) => {
        'business_id': tenant,
        'employee_id': employeeId,
        'service_id': serviceId,
      }).toList());
    }
  }

  @override
  Future<void> delete(String id) async {
    // Keep service identity and snapshots stable for all historical appointments.
    await toggle(id, false);
  }

  @override
  Future<void> toggle(String id, bool isActive) async {
    final tenant = _tenant();
    await _client.from('services').update({'is_active': isActive})
        .eq('business_id', tenant).eq('id', id);
  }

  Future<String> _ensureCategory(String name) async {
    final tenant = _tenant();
    final row = await _client.from('service_categories').select('id')
        .eq('business_id', tenant).eq('name', name).maybeSingle();
    if (row != null) return row['id'] as String;
    final inserted = await _client.from('service_categories').insert({
      'business_id': tenant,
      'name': name,
    }).select('id').single();
    return inserted['id'] as String;
  }

  @override
  Future<List<String>> fetchCategories() async {
    final tenant = _tenant();
    final rows = await _client.from('service_categories').select('name')
        .eq('business_id', tenant).eq('is_active', true).order('sort_order');
    return rows.map((row) => row['name'] as String).toList(growable: false);
  }

  @override
  Future<void> addCategory(String name) async {
    await _ensureCategory(name.trim());
  }

  @override
  Future<void> renameCategory(String oldName, String newName) async {
    final tenant = _tenant();
    final target = await _client.from('service_categories').select('id')
        .eq('business_id', tenant).eq('name', oldName).single();
    await _client.from('service_categories').update({'name': newName.trim()})
        .eq('business_id', tenant).eq('id', target['id']);
    await _client.from('services').update({'category': newName.trim()})
        .eq('business_id', tenant).eq('category', oldName);
  }

  @override
  Future<void> deleteCategory(String name, {String? moveServicesTo}) async {
    final tenant = _tenant();
    final source = await _client.from('service_categories').select('id')
        .eq('business_id', tenant).eq('name', name).maybeSingle();
    if (source == null) return;
    final dependents = await _client.from('services').select('id')
        .eq('business_id', tenant).eq('category_id', source['id']);
    if (dependents.isNotEmpty) {
      final targetName = moveServicesTo?.trim();
      if (targetName == null || targetName.isEmpty || targetName == name) {
        throw StateError('برای حذف این دسته‌بندی ابتدا دسته‌بندی مقصد را مشخص کنید.');
      }
      final target = await _client.from('service_categories').select('id')
          .eq('business_id', tenant).eq('name', targetName).single();
      await _client.from('services').update({
        'category': targetName,
        'category_id': target['id'],
      }).eq('business_id', tenant).eq('category_id', source['id']);
    }
    await _client.from('service_categories').delete()
        .eq('business_id', tenant).eq('id', source['id']);
  }

  @override
  Future<List<EmployeeServiceConfig>> fetchEmployeeServiceConfigs() async {
    final tenant = _tenant();
    final rows = await _client.from('employee_services')
         .select('employee_id,service_id,is_active,custom_price_toman,custom_duration_minutes,commission_rate_bps,fixed_commission_amount_toman,notes')
        .eq('business_id', tenant);
    return rows.map((row) => EmployeeServiceConfig(
      employeeId: row['employee_id'] as String,
      serviceId: row['service_id'] as String,
      active: row['is_active'] as bool? ?? true,
      customPrice: (row['custom_price_toman'] as num?)?.toInt(),
      customDurationMinutes: (row['custom_duration_minutes'] as num?)?.toInt(),
      commissionRateBps: (row['commission_rate_bps'] as num?)?.toInt(),
      fixedCommissionAmount: (row['fixed_commission_amount_toman'] as num?)?.toInt(),
      specialtyNote: row['notes'] as String? ?? '',
    )).toList(growable: false);
  }

  @override
  Future<void> saveEmployeeServiceConfig(EmployeeServiceConfig config) async {
    final tenant = _tenant();
    await _client.from('employee_services').upsert({
      'business_id': tenant,
      'employee_id': config.employeeId,
      'service_id': config.serviceId,
      'is_active': config.active,
      'custom_price_toman': config.customPrice,
      'custom_duration_minutes': config.customDurationMinutes,
      'commission_rate_bps': config.commissionRateBps,
      'fixed_commission_amount_toman': config.fixedCommissionAmount,
      'notes': config.specialtyNote,
    }, onConflict: 'business_id,employee_id,service_id');
  }
}
