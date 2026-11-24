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
      bufferMinutes: 0,
      prepMinutes: 0,
      isActive: row['is_active'] as bool? ?? false,
      employeeIds: links,
      category: row['category'] as String? ?? '',
      order: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  static const _columns =
      'id,title,category,description,duration_minutes,price_toman,is_active,sort_order,employee_services(employee_id,is_active)';

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

  @override
  Future<void> create(Service service) async {
    final tenant = _tenant();
    final categoryId = service.category.trim().isEmpty
        ? null
        : await _ensureCategory(service.category.trim());
    final inserted = await _client.from('services').insert({
      'business_id': tenant,
      'category_id': categoryId,
      'title': service.title.trim(),
      'category': service.category.trim(),
      'description': service.description,
      'duration_minutes': service.durationMinutes,
      'price_toman': service.price,
      'is_active': service.isActive,
      'sort_order': service.order,
    }).select('id').single();
    await _syncEmployeeLinks(inserted['id'] as String, service.employeeIds);
  }

  @override
  Future<void> update(Service service) async {
    final tenant = _tenant();
    final categoryId = service.category.trim().isEmpty
        ? null
        : await _ensureCategory(service.category.trim());
    await _client.from('services').update({
      'category_id': categoryId,
      'title': service.title.trim(),
      'category': service.category.trim(),
      'description': service.description,
      'duration_minutes': service.durationMinutes,
      'price_toman': service.price,
      'is_active': service.isActive,
      'sort_order': service.order,
    }).eq('business_id', tenant).eq('id', service.id);
    await _syncEmployeeLinks(service.id, service.employeeIds);
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
    final tenant = _tenant();
    final history = await _client.from('appointment_services').select('id')
        .eq('business_id', tenant).eq('service_id', id).limit(1);
    if (history.isNotEmpty) {
      await toggle(id, false);
      return;
    }
    await _client.from('services').delete().eq('business_id', tenant).eq('id', id);
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
        .select('employee_id,service_id,is_active,custom_price_toman,custom_duration_minutes,notes')
        .eq('business_id', tenant);
    return rows.map((row) => EmployeeServiceConfig(
      employeeId: row['employee_id'] as String,
      serviceId: row['service_id'] as String,
      active: row['is_active'] as bool? ?? true,
      customPrice: (row['custom_price_toman'] as num?)?.toInt(),
      customDurationMinutes: (row['custom_duration_minutes'] as num?)?.toInt(),
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
      'notes': config.specialtyNote,
    }, onConflict: 'business_id,employee_id,service_id');
  }
}
