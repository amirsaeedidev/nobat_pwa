
-- Make the undo RPC an invoker operation so source-table RLS remains in force.
create or replace function public.mark_business_activity_event_undo()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if new.undo_of_event_id is not null then
    update public.business_activity_events set undone_by_event_id=new.id
    where id=new.undo_of_event_id and undone_by_event_id is null;
    if not found then raise exception 'ACTIVITY_UNDO_ALREADY_CONSUMED' using errcode='40001'; end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.mark_business_activity_event_undo() from public,anon,authenticated;
drop trigger if exists business_activity_events_mark_undo on public.business_activity_events;
create trigger business_activity_events_mark_undo after insert on public.business_activity_events
for each row execute function public.mark_business_activity_event_undo();

create or replace function public.undo_business_activity_event(p_event_id uuid)
returns uuid language plpgsql security invoker set search_path=''
as $function$
declare
  v_event public.business_activity_events%rowtype; v_current jsonb; v_set_clause text;
  v_permission text; v_undo_event_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_event_id::text,0));
  select * into v_event from public.business_activity_events where id=p_event_id;
  if not found then raise exception 'ACTIVITY_EVENT_NOT_FOUND' using errcode='P0002'; end if;
  if v_event.undone_by_event_id is not null then return v_event.undone_by_event_id; end if;
  if not v_event.is_reversible or v_event.before_state is null or v_event.after_state is null then
    raise exception 'ACTIVITY_EVENT_NOT_REVERSIBLE' using errcode='22023'; end if;
  v_permission := case v_event.source_table
    when 'appointments' then 'appointments.manage' when 'customers' then 'customers.manage'
    when 'employees' then 'employees.manage' when 'services' then 'services.manage'
    when 'service_categories' then 'services.manage' when 'business_settings' then 'settings.manage'
    when 'app_records' then case v_event.entity_type when 'roles' then 'settings.roles.manage' when 'settings' then 'settings.manage' else 'activity.manage' end
    when 'employee_working_hours' then 'employees.schedule.manage'
    when 'employee_schedule_exceptions' then 'employees.schedule.manage'
    when 'employee_leaves' then 'employees.leave.manage'
    when 'employee_services' then 'employees.services.manage'
    when 'employee_commission_rules' then 'employees.services.manage'
    when 'employee_service_compensation' then 'employees.services.manage'
    when 'employee_pay_profiles' then 'finance.payroll.manage' else 'activity.manage' end;
  if not private.has_business_permission(v_event.business_id,v_permission) then
    raise exception 'ACTIVITY_UNDO_FORBIDDEN' using errcode='42501'; end if;
  if v_event.source_table not in (
    'appointments','customers','employees','services','service_categories','business_settings','app_records',
    'employee_working_hours','employee_schedule_exceptions','employee_leaves','employee_services',
    'employee_commission_rules','employee_service_compensation','employee_pay_profiles'
  ) then raise exception 'ACTIVITY_UNDO_TABLE_NOT_ALLOWED' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where t.%I::text=$1 and t.business_id=$2',
    v_event.source_table,v_event.entity_key_column) into v_current using v_event.entity_id,v_event.business_id;
  if v_current is null or (v_current-'updated_at') is distinct from (v_event.after_state-'updated_at') then
    raise exception 'ACTIVITY_UNDO_STALE_STATE' using errcode='40001'; end if;
  select string_agg(format('%1$I = src.%1$I',a.attname),', ' order by a.attnum) into v_set_clause
    from pg_attribute a where a.attrelid=format('public.%I',v_event.source_table)::regclass
      and a.attnum>0 and not a.attisdropped and a.attgenerated='' and a.attidentity=''
      and a.attname not in ('id','business_id','created_at','created_by','updated_at','updated_by',v_event.entity_key_column);
  if v_set_clause is null then raise exception 'ACTIVITY_UNDO_NO_MUTABLE_COLUMNS' using errcode='22023'; end if;
  if exists(select 1 from pg_attribute a where a.attrelid=format('public.%I',v_event.source_table)::regclass
    and a.attname='updated_by' and a.attnum>0 and not a.attisdropped) then
    v_set_clause := v_set_clause || ', updated_by = auth.uid()'; end if;
  perform set_config('app.undo_of_event_id',p_event_id::text,true);
  perform set_config('app.operation_id',gen_random_uuid()::text,true);
  execute format('update public.%I as target set %s from jsonb_populate_record(null::public.%I,$1) as src where target.%I::text=$2 and target.business_id=$3',
    v_event.source_table,v_set_clause,v_event.source_table,v_event.entity_key_column)
    using v_event.before_state,v_event.entity_id,v_event.business_id;
  select id into v_undo_event_id from public.business_activity_events where undo_of_event_id=p_event_id;
  if v_undo_event_id is null then raise exception 'ACTIVITY_UNDO_EVENT_NOT_RECORDED' using errcode='P0001'; end if;
  perform set_config('app.undo_of_event_id','',true);
  perform set_config('app.operation_id','',true);
  return v_undo_event_id;
end;
$function$;
revoke all on function public.undo_business_activity_event(uuid) from public,anon;
grant execute on function public.undo_business_activity_event(uuid) to authenticated;
