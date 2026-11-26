import 'package:supabase_flutter/supabase_flutter.dart';

Map<String,dynamic>? _oneRelation(dynamic value) {
  if (value is Map) return Map<String,dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) return Map<String,dynamic>.from(value.first as Map);
  return null;
}
import '../../core/models/page_result.dart';
import '../../core/utils/jalali.dart';
import '../models/appointment.dart';
import '../models/customer.dart';
import '../models/employee.dart';
import '../models/employee_schedule.dart';
import '../models/employee_service_config.dart';
import '../models/enums.dart';
import '../models/service.dart';
import 'appointment_repository.dart';
import 'customer_repository.dart';
import 'employee_repository.dart';
import 'service_repository.dart';

class SupabaseTenantScope {
  SupabaseTenantScope(this.client);
  final SupabaseClient client;
  String? _businessId;
  String? _userId;
  Future<String> get businessId async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('برای دریافت اطلاعات واقعی ابتدا وارد حساب شوید.');
    if (_userId != user.id) { _businessId = null; _userId = user.id; }
    if (_businessId != null) return _businessId!;
    final rows = await client.from('business_memberships').select('business_id').eq('user_id', client.auth.currentUser!.id).eq('is_active', true).limit(2);
    if (rows.length != 1) throw StateError(rows.isEmpty ? 'برای حساب شما مجموعه فعالی ثبت نشده است.' : 'چند مجموعه فعال یافت شد؛ انتخاب مجموعه لازم است.');
    _businessId = rows.first['business_id'] as String;
    return _businessId!;
  }
}

class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository(this.client, this.scope);
  final SupabaseClient client; final SupabaseTenantScope scope;
  Customer map(Map<String,dynamic> r) => Customer(id:r['id'].toString(),fullName:r['full_name'] as String? ?? '',phone:r['phone'] as String? ?? '',notes:r['notes'] as String? ?? '',tags:(r['tags'] as List? ?? const []).map((e)=>e.toString()).toList(),createdAt:DateTime.tryParse(r['created_at']?.toString() ?? ''),isArchived:r['is_active']==false);
  Future<List<Customer>> fetchAll({String query = ''}) async { final b=await scope.businessId; var q=client.from('customers').select().eq('business_id',b).eq('is_active',true); if(query.trim().isNotEmpty){ final term=query.trim().replaceAll('%',r'\%').replaceAll('_',r'\_'); q=q.or('full_name.ilike.%'+term+'%,phone.ilike.%'+term+'%,normalized_phone.ilike.%'+term+'%'); } final rows=await q.order('created_at',ascending:false); return rows.map((r)=>map(Map<String,dynamic>.from(r))).toList(); }
  Future<PageResult<Customer>> fetchCustomers({String query='',int page=1,int pageSize=8,String sortBy='createdAt'}) async { final all=await fetchAll(query:query); final start=((page-1)*pageSize).clamp(0,all.length); final end=(start+pageSize).clamp(start,all.length); return PageResult(items:all.sublist(start,end),total:all.length,page:page,pageSize:pageSize); }
  Future<Customer?> findById(String id) async { final b=await scope.businessId; final r=await client.from('customers').select().eq('business_id',b).eq('id',id).maybeSingle(); return r==null?null:map(Map<String,dynamic>.from(r)); }
  Future<Customer> createAndReturn(Customer c) async { final b=await scope.businessId; final row=await client.from('customers').insert({'business_id':b,'full_name':c.fullName.trim(),'phone':c.phone.trim(),'notes':c.notes,'tags':c.tags,'is_active':!c.isArchived}).select().single(); return map(Map<String,dynamic>.from(row)); }
  Future<void> create(Customer c) async { await createAndReturn(c); }
  Future<void> update(Customer c) async { final b=await scope.businessId; await client.from('customers').update({'full_name':c.fullName.trim(),'phone':c.phone.trim(),'notes':c.notes,'tags':c.tags,'is_active':!c.isArchived}).eq('business_id',b).eq('id',c.id); }
  Future<void> delete(String id) async { final b=await scope.businessId; await client.from('customers').update({'is_active':false}).eq('business_id',b).eq('id',id); }
}

class SupabaseServiceRepository implements ServiceRepository {
  SupabaseServiceRepository(this.client,this.scope); final SupabaseClient client; final SupabaseTenantScope scope;
  Service map(Map<String,dynamic> r,List<String> employees) => Service(id:r['id'].toString(),title:r['title'] as String? ?? '',description:r['description'] as String? ?? '',price:r['price_toman'] as num? ?? 0,directCost:r['direct_cost_toman'] as num?,durationMinutes:(r['duration_minutes'] as num? ?? 30).toInt(),bufferMinutes:(r['buffer_minutes'] as num? ?? 0).toInt(),prepMinutes:(r['prep_minutes'] as num? ?? 0).toInt(),imageUrl:r['image_url'] as String?,discountPrice:r['discount_price_toman'] as num?,discountStartsAt:DateTime.tryParse(r['discount_starts_on']?.toString() ?? ''),discountEndsAt:DateTime.tryParse(r['discount_ends_on']?.toString() ?? ''),isActive:r['is_active'] as bool? ?? true,employeeIds:employees,category:r['category'] as String? ?? 'عمومی',maxPerDay:(r['max_per_day'] as num?)?.toInt(),advanceDays:(r['advance_days'] as num? ?? 30).toInt(),requiresConfirmation:r['requires_confirmation'] as bool? ?? false,order:(r['sort_order'] as num? ?? 0).toInt());
  Future<List<Service>> fetchServices({bool onlyActive=false,String query=''}) async { final b=await scope.businessId; var q=client.from('services').select('*,employee_services(employee_id,is_active)').eq('business_id',b).isFilter('archived_at',null); if(onlyActive) q=q.eq('is_active',true); if(query.trim().isNotEmpty) q=q.ilike('title','%'+query.trim()+'%'); final rows=await q.order('sort_order'); return rows.map((raw){final r=Map<String,dynamic>.from(raw); final ids=(r['employee_services'] as List? ?? const []).where((x)=>(x as Map)['is_active']==true).map((x)=>(x as Map)['employee_id'].toString()).toList(); return map(r,ids);}).toList(); }
  Future<Service?> findById(String id) async { for(final s in await fetchServices()){if(s.id==id)return s;} return null; }
  Map<String,dynamic> payload(Service s)=>{'title':s.title,'category':s.category,'description':s.description,'duration_minutes':s.durationMinutes,'price_toman':s.price,'direct_cost_toman':s.directCost,'buffer_minutes':s.bufferMinutes,'prep_minutes':s.prepMinutes,'image_url':s.imageUrl,'discount_price_toman':s.discountPrice,'discount_starts_on':s.discountStartsAt?.toIso8601String().substring(0,10),'discount_ends_on':s.discountEndsAt?.toIso8601String().substring(0,10),'is_active':s.isActive,'max_per_day':s.maxPerDay,'advance_days':s.advanceDays,'requires_confirmation':s.requiresConfirmation,'sort_order':s.order};
  Future<String> createAndReturn(Service s) async {final b=await scope.businessId; final row=await client.from('services').insert({'business_id':b,...payload(s)}).select('id').single(); return row['id'].toString();}
  Future<void> create(Service s) async {await createAndReturn(s);}
  Future<void> update(Service s) async {final b=await scope.businessId; await client.from('services').update(payload(s)).eq('business_id',b).eq('id',s.id);}
  Future<void> delete(String id) async {final b=await scope.businessId; await client.from('services').update({'is_active':false,'archived_at':DateTime.now().toUtc().toIso8601String()}).eq('business_id',b).eq('id',id);}
  Future<void> toggle(String id,bool active) async {final b=await scope.businessId; await client.from('services').update({'is_active':active}).eq('business_id',b).eq('id',id);}
  Future<List<String>> fetchCategories() async {final b=await scope.businessId; final rows=await client.from('service_categories').select('name').eq('business_id',b).eq('is_active',true).order('sort_order'); return rows.map((r)=>r['name'] as String).toList();}
  Future<void> addCategory(String name) async {final b=await scope.businessId; await client.from('service_categories').insert({'business_id':b,'name':name.trim()});}
  Future<void> renameCategory(String oldName,String newName) async {final b=await scope.businessId; final row=await client.from('service_categories').select('id').eq('business_id',b).eq('name',oldName).single(); await client.rpc('rename_service_category',params:{'p_business_id':b,'p_category_id':row['id'],'p_new_name':newName.trim()});}
  Future<void> deleteCategory(String name,{String? moveServicesTo}) async {final b=await scope.businessId; final row=await client.from('service_categories').select('id').eq('business_id',b).eq('name',name).single(); String? target; if(moveServicesTo!=null){final t=await client.from('service_categories').select('id').eq('business_id',b).eq('name',moveServicesTo).single(); target=t['id'] as String;} await client.rpc('delete_service_category',params:{'p_business_id':b,'p_category_id':row['id'],'p_target_category_id':target});}
  Future<List<EmployeeServiceConfig>> fetchEmployeeServiceConfigs() async {final b=await scope.businessId; final rows=await client.from('employee_services').select('employee_id,service_id,is_active,custom_price_toman,custom_duration_minutes,notes,employee_service_compensation(commission_rate_bps,fixed_commission_amount_toman)').eq('business_id',b); return rows.map((r){final x=Map<String,dynamic>.from(r); final c=_oneRelation(x['employee_service_compensation']); return EmployeeServiceConfig(employeeId:x['employee_id'].toString(),serviceId:x['service_id'].toString(),active:x['is_active'] as bool? ?? true,customPrice:(x['custom_price_toman'] as num?)?.toInt(),customDurationMinutes:(x['custom_duration_minutes'] as num?)?.toInt(),commissionRateBps:(c?['commission_rate_bps'] as num?)?.toInt(),fixedCommissionAmount:(c?['fixed_commission_amount_toman'] as num?)?.toInt(),specialtyNote:x['notes'] as String? ?? '');}).toList();}
  Future<void> saveEmployeeServiceConfig(EmployeeServiceConfig c) async {final b=await scope.businessId; await client.from('employee_services').upsert({'business_id':b,'employee_id':c.employeeId,'service_id':c.serviceId,'is_active':c.active,'custom_price_toman':c.customPrice,'custom_duration_minutes':c.customDurationMinutes,'notes':c.specialtyNote},onConflict:'business_id,employee_id,service_id'); await client.from('employee_service_compensation').upsert({'business_id':b,'employee_id':c.employeeId,'service_id':c.serviceId,'commission_rate_bps':c.commissionRateBps,'fixed_commission_amount_toman':c.fixedCommissionAmount},onConflict:'business_id,employee_id,service_id');}
}

class SupabaseEmployeeRepository implements EmployeeRepository {
  SupabaseEmployeeRepository(this.client,this.scope); final SupabaseClient client; final SupabaseTenantScope scope;
  Future<List<Employee>> fetchEmployees({bool onlyActive=false,String? serviceId}) async {final b=await scope.businessId; var q=client.from('employees').select('*,employee_services(service_id,is_active),employee_working_hours(weekday,starts_at,ends_at,is_active)').eq('business_id',b); if(onlyActive) q=q.eq('is_active',true); final rows=await q.order('full_name'); final result=<Employee>[]; for(final raw in rows){final r=Map<String,dynamic>.from(raw); final ss=(r['employee_services'] as List? ?? const []).where((x)=>(x as Map)['is_active']==true).map((x)=>(x as Map)['service_id'].toString()).toList(); if(serviceId!=null&&!ss.contains(serviceId))continue; final schedule=<int,List<Shift>>{}; for(final rawHour in (r['employee_working_hours'] as List? ?? const [])){final h=Map<String,dynamic>.from(rawHour); if(h['is_active']!=true)continue; final postgresDay=(h['weekday'] as num).toInt(); final day=(postgresDay+1)%7; schedule.putIfAbsent(day,()=>[]).add(Shift(start:h['starts_at'].toString().substring(0,5),end:h['ends_at'].toString().substring(0,5)));} final active=r['is_active'] as bool? ?? true; result.add(Employee(id:r['id'].toString(),fullName:r['full_name'] as String? ?? '',phone:r['phone'] as String? ?? '',title:r['title'] as String? ?? '',role:StaffRole.fromKey(r['staff_role'] as String? ?? 'specialist'),isActive:active,status:EmployeeStatus.fromKey(r['employment_status'] as String?,isActive:active),serviceIds:ss,schedule:schedule,email:r['email'] as String? ?? '',startedAt:DateTime.tryParse(r['hired_on']?.toString() ?? ''),specialties:(r['specialties'] as List? ?? const []).map((e)=>e.toString()).toList(),notes:r['notes'] as String? ?? '',emergencyContactName:r['emergency_contact_name'] as String? ?? '',emergencyContactPhone:r['emergency_contact_phone'] as String? ?? '',scheduleEnabled:r['schedule_enabled'] as bool? ?? true,bufferMinutes:(r['buffer_minutes'] as num? ?? 0).toInt()));} return result;}
  Future<Employee?> findById(String id) async {for(final e in await fetchEmployees()){if(e.id==id)return e;}return null;}
  Future<void> save(Employee e) async {final b=await scope.businessId; final profile={'full_name':e.fullName,'phone':e.phone,'email':e.email,'title':e.title,'staff_role':e.role.key,'is_active':e.isActive,'employment_status':e.employmentStatus.name,'hired_on':e.startedAt?.toIso8601String().substring(0,10),'notes':e.notes,'specialties':e.specialties,'emergency_contact_name':e.emergencyContactName,'emergency_contact_phone':e.emergencyContactPhone,'schedule_enabled':e.scheduleEnabled,'buffer_minutes':e.bufferMinutes}; final existingRows=e.id.startsWith('emp-')?const <dynamic>[]:await client.from('employee_services').select('service_id,is_active,custom_price_toman,custom_duration_minutes,notes,employee_service_compensation(commission_rate_bps,fixed_commission_amount_toman)').eq('business_id',b).eq('employee_id',e.id); final existingByService=<String,Map<String,dynamic>>{}; for(final row in existingRows){final value=Map<String,dynamic>.from(row);existingByService[value['service_id'].toString()]=value;} final services=e.serviceIds.map((id){final old=existingByService[id];return <String,dynamic>{'service_id':id,'is_active':old?['is_active']??true,'custom_price_toman':old?['custom_price_toman'],'custom_duration_minutes':old?['custom_duration_minutes'],'notes':old?['notes']??''};}).toList(); final hours=<Map<String,dynamic>>[]; e.schedule.forEach((day,shifts){for(final s in shifts){hours.add({'weekday':(day+6)%7,'starts_at':s.start,'ends_at':s.end,'is_active':true});}}); final dynamic id=e.id.startsWith('emp-')?null:e.id; await client.rpc('save_employee_profile',params:{'p_business_id':b,'p_employee_id':id,'p_profile':profile,'p_services':services,'p_working_hours':hours}); for(final raw in existingRows){final row=Map<String,dynamic>.from(raw);final serviceId=row['service_id'].toString();if(!e.serviceIds.contains(serviceId))continue;final comp=_oneRelation(row['employee_service_compensation']);if(comp==null)continue;await client.from('employee_service_compensation').upsert({'business_id':b,'employee_id':id ?? (await client.from('employees').select('id').eq('business_id',b).eq('full_name',e.fullName).order('created_at',ascending:false).limit(1).single())['id'],'service_id':serviceId,'commission_rate_bps':comp['commission_rate_bps'],'fixed_commission_amount_toman':comp['fixed_commission_amount_toman']},onConflict:'business_id,employee_id,service_id');}}
  Future<void> create(Employee e)=>save(e); Future<void> update(Employee e)=>save(e);
  Future<void> delete(String id) async {final b=await scope.businessId; await client.from('employees').update({'is_active':false,'employment_status':'inactive'}).eq('business_id',b).eq('id',id);}
  Future<List<EmployeeScheduleException>> fetchScheduleExceptions(String employeeId) async {
    final b=await scope.businessId;
    final rows=await client.from('employee_schedule_exceptions').select('work_date,is_available,starts_at,ends_at,reason').eq('business_id',b).eq('employee_id',employeeId).order('work_date');
    final grouped=<String,List<Map<String,dynamic>>>{};
    for(final raw in rows){final row=Map<String,dynamic>.from(raw);final key=row['work_date'].toString().substring(0,10);grouped.putIfAbsent(key,()=>[]).add(row);}
    return grouped.entries.map((entry){final rows=entry.value;final closed=rows.any((row)=>row['is_available']==false);final shifts=closed?const <Shift>[]:rows.where((row)=>row['is_available']==true&&row['starts_at']!=null&&row['ends_at']!=null).map((row)=>Shift(start:row['starts_at'].toString().substring(0,5),end:row['ends_at'].toString().substring(0,5))).toList();return EmployeeScheduleException(employeeId:employeeId,dateKey:entry.key,title:rows.first['reason'] as String? ?? 'ساعات ویژه',isClosed:closed,shifts:shifts);}).toList();
  }
  Future<void> saveScheduleException(EmployeeScheduleException exception) async {
    final b=await scope.businessId;
    await client.from('employee_schedule_exceptions').delete().eq('business_id',b).eq('employee_id',exception.employeeId).eq('work_date',exception.dateKey);
    if(exception.isClosed){await client.from('employee_schedule_exceptions').insert({'business_id':b,'employee_id':exception.employeeId,'work_date':exception.dateKey,'is_available':false,'reason':exception.title});}
    else {for(final shift in exception.shifts){await client.from('employee_schedule_exceptions').insert({'business_id':b,'employee_id':exception.employeeId,'work_date':exception.dateKey,'is_available':true,'starts_at':shift.start,'ends_at':shift.end,'reason':exception.title});}}
  }
  Future<void> deleteScheduleException(String employeeId,String dateKey) async {final b=await scope.businessId;await client.from('employee_schedule_exceptions').delete().eq('business_id',b).eq('employee_id',employeeId).eq('work_date',dateKey);}
  EmployeeLeave _mapLeave(Map<String,dynamic> r)=>EmployeeLeave(id:r['id'].toString(),employeeId:r['employee_id'].toString(),startAt:DateTime.parse(r['starts_at'].toString()).toLocal(),endAt:DateTime.parse(r['ends_at'].toString()).toLocal(),type:EmployeeLeaveType.values.firstWhere((v)=>v.name==r['leave_type'],orElse:()=>EmployeeLeaveType.daily),status:EmployeeLeaveStatus.values.firstWhere((v)=>v.name==r['status'],orElse:()=>EmployeeLeaveStatus.pending),description:r['description'] as String? ?? '',createdAt:DateTime.parse(r['created_at'].toString()).toLocal(),approvedBy:r['reviewed_by']?.toString());
  Future<List<EmployeeLeave>> fetchLeaves(String employeeId) async {final b=await scope.businessId;final rows=await client.from('employee_leaves').select().eq('business_id',b).eq('employee_id',employeeId).order('starts_at',ascending:false);return rows.map((r)=>_mapLeave(Map<String,dynamic>.from(r))).toList();}
  Future<void> createLeave(EmployeeLeave leave) async {final b=await scope.businessId;await client.from('employee_leaves').insert({'business_id':b,'employee_id':leave.employeeId,'starts_at':leave.startAt.toUtc().toIso8601String(),'ends_at':leave.endAt.toUtc().toIso8601String(),'leave_type':leave.type.name,'status':leave.status.name,'description':leave.description,'requested_by':client.auth.currentUser!.id});}
  Future<void> updateLeave(EmployeeLeave leave) async {final b=await scope.businessId;await client.from('employee_leaves').update({'status':leave.status.name,'description':leave.description,'reviewed_by':client.auth.currentUser!.id,'reviewed_at':DateTime.now().toUtc().toIso8601String()}).eq('business_id',b).eq('employee_id',leave.employeeId).eq('id',leave.id);}
  Future<void> deleteLeave(String id) async {final b=await scope.businessId;await client.from('employee_leaves').delete().eq('business_id',b).eq('id',id);}
  Future<List<DateTime>> fetchBusinessHolidays() async {final b=await scope.businessId;final rows=await client.from('business_holidays').select('holiday_date').eq('business_id',b).order('holiday_date');return rows.map((row)=>DateTime.parse(row['holiday_date'].toString())).toList();}
}

class SupabaseAppointmentRepository implements AppointmentRepository {
  SupabaseAppointmentRepository(this.client,this.scope); final SupabaseClient client; final SupabaseTenantScope scope;
  Appointment map(Map<String,dynamic> r){final c=Map<String,dynamic>.from(r['customers'] as Map? ?? const {}); final e=Map<String,dynamic>.from(r['employees'] as Map? ?? const {}); final rawSnapshots=(r['appointment_services'] as List? ?? const []).map((x)=>Map<String,dynamic>.from(x as Map)).toList(); final ss=rawSnapshots.map((x)=><String,dynamic>{'service_id':x['service_id'],'title':x['title_snapshot'],'category':x['category_snapshot'],'description':x['description_snapshot'],'duration_minutes':x['duration_minutes'],'price':x['price_toman'],'direct_cost':x['direct_cost_toman_snapshot'],'commission_rate_bps':x['commission_rate_bps_snapshot'],'fixed_commission_amount':x['fixed_commission_amount_toman_snapshot'],'commission_basis':x['commission_basis_snapshot']}).toList(); final start=DateTime.parse(r['starts_at'].toString()).toLocal(); final end=DateTime.parse(r['ends_at'].toString()).toLocal(); final rawStatus=r['status'].toString(); final status=rawStatus=='no_show'?AppointmentStatus.noShow:AppointmentStatus.fromKey(rawStatus=='rejected'?'cancelled':rawStatus); return Appointment(id:r['id'].toString(),reference:r['reference']?.toString() ?? '',customerId:r['customer_id'].toString(),customerName:c['full_name']?.toString() ?? '',customerPhone:c['phone']?.toString() ?? '',serviceIds:ss.map((x)=>x['service_id'].toString()).toList(),serviceName:ss.map((x)=>x['title'].toString()).join('، '),employeeId:r['employee_id'].toString(),employeeName:e['full_name']?.toString() ?? '',startAt:start,durationMinutes:end.difference(start).inMinutes,status:status,note:r['note']?.toString() ?? '',price:r['price_toman'] as num? ?? 0,createdAt:DateTime.tryParse(r['created_at']?.toString() ?? ''),updatedAt:DateTime.tryParse(r['updated_at']?.toString() ?? ''),rescheduleCount:(r['reschedule_count'] as num? ?? 0).toInt(),cancelReason:r['cancel_reason'] as String?,serviceSnapshots:ss);}
  Future<List<Appointment>> fetchAll({AppointmentFilter filter=const AppointmentFilter()}) async { final first=await fetchAppointments(filter:filter,page:1,pageSize:100,ascending:true); final all=<Appointment>[...first.items]; for(var page=2;all.length<first.total;page++){final next=await fetchAppointments(filter:filter,page:page,pageSize:100,ascending:true); if(next.items.isEmpty)break; all.addAll(next.items);} return all; }
  Future<PageResult<Appointment>> fetchAppointments({AppointmentFilter filter=const AppointmentFilter(),int page=1,int pageSize=8,bool ascending=true}) async {final b=await scope.businessId; final response=await client.rpc('list_appointments',params:{'p_business_id':b,'p_query':filter.query,'p_status':filter.status==null?null:(filter.status==AppointmentStatus.noShow?'no_show':filter.status!.key),'p_service_id':filter.serviceId,'p_employee_id':filter.employeeId,'p_from':filter.fromDate?.toDateTime().toUtc().toIso8601String(),'p_to':filter.toDate?.addDays(1).toDateTime().toUtc().toIso8601String(),'p_page':page,'p_page_size':pageSize,'p_ascending':ascending}); final d=Map<String,dynamic>.from(response as Map); final items=(d['items'] as List? ?? const []).map((x)=>map(Map<String,dynamic>.from(x as Map))).toList(); return PageResult(items:items,total:(d['total'] as num).toInt(),page:page,pageSize:pageSize);}
  Future<List<Appointment>> fetchForDay(DateTime day,{String? employeeId,String? serviceId})=>fetchAll(filter:AppointmentFilter(employeeId:employeeId,serviceId:serviceId,fromDate:JalaliDate.fromDateTime(day),toDate:JalaliDate.fromDateTime(day)));
  Future<List<Appointment>> fetchForCustomer(String id) async {final b=await scope.businessId; final r=await client.rpc('list_appointments',params:{'p_business_id':b,'p_customer_id':id,'p_page':1,'p_page_size':100,'p_ascending':false}); final d=Map<String,dynamic>.from(r as Map); return (d['items'] as List? ?? const []).map((x)=>map(Map<String,dynamic>.from(x as Map))).toList();}
  Future<Appointment?> findById(String id) async {final rows=await fetchAll(); for(final a in rows){if(a.id==id)return a;} return null;}
  Future<Appointment?> findConflict({required String employeeId,required DateTime startAt,required int durationMinutes,String? ignoreId}) async {final rows=await fetchForDay(startAt,employeeId:employeeId); for(final a in rows){if(a.id!=ignoreId&&a.status.isActive&&a.startAt.isBefore(startAt.add(Duration(minutes:durationMinutes)))&&startAt.isBefore(a.endAt))return a;} return null;}
  Future<void> create(Appointment a) async {final b=await scope.businessId; await client.rpc('create_appointment',params:{'p_business_id':b,'p_customer_id':a.customerId,'p_employee_id':a.employeeId,'p_starts_at':a.startAt.toUtc().toIso8601String(),'p_service_ids':a.serviceIds,'p_reference':a.reference,'p_note':a.note,'p_idempotency_key':a.id});}
  Future<void> update(Appointment a) async {await client.rpc('update_appointment',params:{'p_appointment_id':a.id,'p_customer_id':a.customerId,'p_employee_id':a.employeeId,'p_starts_at':a.startAt.toUtc().toIso8601String(),'p_service_ids':a.serviceIds,'p_note':a.note});}
  Future<void> changeStatus(Appointment a,AppointmentStatus s,{String? reason}) async {await client.rpc('set_appointment_status',params:{'p_appointment_id':a.id,'p_status':s==AppointmentStatus.noShow?'no_show':s.key,'p_reason':reason});}
  Future<void> reschedule(Appointment a,DateTime d,{bool byCustomer=false}) async {await client.rpc('reschedule_appointment',params:{'p_appointment_id':a.id,'p_new_starts_at':d.toUtc().toIso8601String()});}
  Future<void> delete(String id) async {await client.rpc('delete_appointment',params:{'p_appointment_id':id});}
}
/// Explicit failure repositories: a missing Supabase configuration never switches
/// a production module back to local/mock records.
class UnavailableCustomerRepository implements CustomerRepository {
  Never fail()=>throw StateError('اتصال Supabase فعال نیست؛ اطلاعات آزمایشی نمایش داده نمی‌شود.');
  Future<PageResult<Customer>> fetchCustomers({String query='',int page=1,int pageSize=8,String sortBy='createdAt'}) async=>fail();
  Future<List<Customer>> fetchAll({String query=''}) async=>fail(); Future<Customer?> findById(String id) async=>fail();
  Future<void> create(Customer c) async=>fail(); Future<Customer> createAndReturn(Customer c) async=>fail(); Future<void> update(Customer c) async=>fail(); Future<void> delete(String id) async=>fail();
}
class UnavailableServiceRepository implements ServiceRepository {
  Never fail()=>throw StateError('اتصال Supabase فعال نیست؛ اطلاعات آزمایشی نمایش داده نمی‌شود.');
  Future<List<Service>> fetchServices({bool onlyActive=false,String query=''}) async=>fail(); Future<Service?> findById(String id) async=>fail();
  Future<void> create(Service s) async=>fail(); Future<String> createAndReturn(Service s) async=>fail(); Future<void> update(Service s) async=>fail(); Future<void> delete(String id) async=>fail(); Future<void> toggle(String id,bool active) async=>fail();
  Future<List<String>> fetchCategories() async=>fail(); Future<void> addCategory(String name) async=>fail(); Future<void> renameCategory(String oldName,String newName) async=>fail(); Future<void> deleteCategory(String name,{String? moveServicesTo}) async=>fail();
  Future<List<EmployeeServiceConfig>> fetchEmployeeServiceConfigs() async=>fail(); Future<void> saveEmployeeServiceConfig(EmployeeServiceConfig c) async=>fail();
}
class UnavailableEmployeeRepository implements EmployeeRepository {
  Never fail()=>throw StateError('اتصال Supabase فعال نیست؛ اطلاعات آزمایشی نمایش داده نمی‌شود.');
  Future<List<Employee>> fetchEmployees({bool onlyActive=false,String? serviceId}) async=>fail(); Future<Employee?> findById(String id) async=>fail();
  Future<void> create(Employee e) async=>fail(); Future<void> update(Employee e) async=>fail(); Future<void> delete(String id) async=>fail();
  Future<List<EmployeeScheduleException>> fetchScheduleExceptions(String employeeId) async=>fail();
  Future<void> saveScheduleException(EmployeeScheduleException exception) async=>fail();
  Future<void> deleteScheduleException(String employeeId,String dateKey) async=>fail();
  Future<List<EmployeeLeave>> fetchLeaves(String employeeId) async=>fail();
  Future<void> createLeave(EmployeeLeave leave) async=>fail();
  Future<void> updateLeave(EmployeeLeave leave) async=>fail();
  Future<void> deleteLeave(String id) async=>fail();
  Future<List<DateTime>> fetchBusinessHolidays() async=>fail();
}
class UnavailableAppointmentRepository implements AppointmentRepository {
  Never fail()=>throw StateError('اتصال Supabase فعال نیست؛ اطلاعات آزمایشی نمایش داده نمی‌شود.');
  Future<PageResult<Appointment>> fetchAppointments({AppointmentFilter filter=const AppointmentFilter(),int page=1,int pageSize=8,bool ascending=true}) async=>fail();
  Future<List<Appointment>> fetchAll({AppointmentFilter filter=const AppointmentFilter()}) async=>fail(); Future<List<Appointment>> fetchForDay(DateTime day,{String? employeeId,String? serviceId}) async=>fail(); Future<List<Appointment>> fetchForCustomer(String id) async=>fail(); Future<Appointment?> findById(String id) async=>fail();
  Future<Appointment?> findConflict({required String employeeId,required DateTime startAt,required int durationMinutes,String? ignoreId}) async=>fail();
  Future<void> create(Appointment a) async=>fail(); Future<void> update(Appointment a) async=>fail(); Future<void> changeStatus(Appointment a,AppointmentStatus s,{String? reason}) async=>fail(); Future<void> reschedule(Appointment a,DateTime d,{bool byCustomer=false}) async=>fail(); Future<void> delete(String id) async=>fail();
}