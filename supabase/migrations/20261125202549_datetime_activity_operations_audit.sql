
-- Durable, tenant-scoped activity journal. Source row changes and their events
-- are written in the same PostgreSQL transaction by triggers.
create table if not exists public.business_activity_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null default gen_random_uuid() unique,
  business_id uuid not null references public.businesses(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_name text not null default 'کاربر',
  source_table text not null,
  entity_key_column text not null,
  entity_type text not null,
  entity_id text not null,
  action text not null,
  operation_type text not null,
  type text not null,
  title text not null,
  description text not null default '',
  before_state jsonb,
  after_state jsonb,
  idempotency_key text,
  is_reversible boolean not null default false,
  undo_of_event_id uuid references public.business_activity_events(id) on delete restrict,
  undone_by_event_id uuid references public.business_activity_events(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint business_activity_events_undo_not_self
    check (undo_of_event_id is null or undo_of_event_id <> id)
);
create index if not exists business_activity_events_business_created_idx
  on public.business_activity_events (business_id, created_at desc);
create index if not exists business_activity_events_business_entity_idx
  on public.business_activity_events (business_id, entity_type, entity_id, created_at desc);
create index if not exists business_activity_events_business_operation_idx
  on public.business_activity_events (business_id, operation_type, created_at desc);
create unique index if not exists business_activity_events_undo_once_idx
  on public.business_activity_events (undo_of_event_id) where undo_of_event_id is not null;
create unique index if not exists business_activity_events_idempotency_idx
  on public.business_activity_events (business_id, source_table, idempotency_key)
  where idempotency_key is not null;
alter table public.business_activity_events enable row level security;
revoke all on public.business_activity_events from anon, authenticated;
grant select on public.business_activity_events to authenticated;
drop policy if exists business_activity_events_read on public.business_activity_events;
create policy business_activity_events_read on public.business_activity_events
  for select to authenticated using (
    private.has_business_permission(business_id,'activity.view')
    or private.has_business_permission(business_id,'activity.manage')
  );

create or replace function public.capture_business_activity_event()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) else null end;
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) else null end;
  v_business_id uuid; v_actor_id uuid; v_actor_name text;
  v_source_table text := tg_table_name; v_key_column text := 'id';
  v_entity_type text; v_entity_id text; v_action text;
  v_operation_type text; v_type text := 'settingsChanged';
  v_title text; v_description text; v_before jsonb; v_after jsonb;
  v_idempotency_key text; v_is_reversible boolean := false;
  v_undo_of_event_id uuid; v_operation_id uuid; v_status text;
begin
  if tg_table_name = 'appointment_audit_events' then
    v_source_table := 'appointments'; v_key_column := 'id';
    v_business_id := (v_new->>'business_id')::uuid;
    v_actor_id := coalesce((v_new->>'actor_id')::uuid,auth.uid());
    v_entity_type := 'appointments'; v_entity_id := v_new->>'appointment_id';
    v_action := coalesce(v_new->>'action','appointment_updated');
    v_before := v_new->'before_state'; v_after := v_new->'after_state';
    v_status := v_after->>'status';
    v_operation_type := case v_action
      when 'appointment_created' then 'appointment_create'
      when 'appointment_updated' then 'appointment_update'
      when 'appointment_rescheduled' then 'appointment_reschedule'
      when 'appointment_deleted' then 'appointment_delete'
      when 'appointment_status_changed' then case v_status
        when 'cancelled' then 'appointment_cancel' when 'rejected' then 'appointment_reject'
        when 'completed' then 'appointment_complete' when 'confirmed' then 'appointment_confirm'
        when 'no_show' then 'appointment_no_show' else 'appointment_update' end
      else 'appointment_update' end;
    v_type := case when v_action='appointment_created' then 'appointmentCreated'
      when v_action='appointment_deleted' then 'appointmentCancelled'
      when v_action='appointment_status_changed' and v_status='completed' then 'appointmentCompleted'
      when v_action='appointment_status_changed' and v_status in ('cancelled','rejected') then 'appointmentCancelled'
      else 'appointmentUpdated' end;
    v_title := case v_operation_type
      when 'appointment_create' then 'ثبت نوبت' when 'appointment_reschedule' then 'تغییر زمان نوبت'
      when 'appointment_delete' then 'حذف امن نوبت' when 'appointment_cancel' then 'لغو نوبت'
      when 'appointment_reject' then 'رد درخواست نوبت' when 'appointment_complete' then 'تکمیل نوبت'
      when 'appointment_confirm' then 'تأیید نوبت' when 'appointment_no_show' then 'ثبت عدم حضور'
      else 'ویرایش نوبت' end;
    v_is_reversible := v_before is not null and v_after is not null and (
      v_action in ('appointment_rescheduled','appointment_updated')
      or (v_action='appointment_status_changed' and v_status in ('cancelled','rejected','confirmed')
          and coalesce(v_before->>'status','') <> 'completed'));
    if v_before is not null and v_after is not null
       and (v_before-'updated_at')=(v_after-'updated_at') then return new; end if;
  else
    v_business_id := coalesce((v_new->>'business_id')::uuid,(v_old->>'business_id')::uuid);
    v_actor_id := coalesce(auth.uid(),(v_new->>'created_by')::uuid,(v_old->>'created_by')::uuid);
    v_before := v_old; v_after := v_new;
    if tg_table_name='app_records' then
      if coalesce(v_new->>'entity_type',v_old->>'entity_type')='activity_logs' then return coalesce(new,old); end if;
      v_entity_type := coalesce(v_new->>'entity_type',v_old->>'entity_type','record');
      v_entity_id := coalesce(v_new->>'record_id',v_old->>'record_id'); v_key_column := 'record_id';
    elsif tg_table_name='business_memberships' then
      v_entity_type := 'roles'; v_entity_id := coalesce(v_new->>'user_id',v_old->>'user_id'); v_key_column := 'user_id';
    elsif tg_table_name='business_settings' then
      v_entity_type := 'settings'; v_entity_id := v_business_id::text; v_key_column := 'business_id';
    else
      v_entity_type := case tg_table_name
        when 'customers' then 'customers' when 'employees' then 'employees'
        when 'services' then 'services' when 'service_categories' then 'service_categories'
        when 'business_holidays' then 'business_holidays' when 'appointment_payments' then 'finance'
        when 'business_expenses' then 'finance' when 'employee_finance_entries' then 'finance'
        when 'employee_settlements' then 'employee_wallets' when 'employee_wallet_transactions' then 'employee_wallets'
        when 'employee_pay_profiles' then 'payroll' when 'employee_working_hours' then 'employees'
        when 'employee_schedule_exceptions' then 'employees' when 'employee_leaves' then 'employees'
        when 'employee_services' then 'employee_services' when 'employee_commission_rules' then 'employee_services'
        when 'employee_service_compensation' then 'employee_services' else tg_table_name end;
      v_entity_id := coalesce(v_new->>'id',v_old->>'id',v_new->>'employee_id',v_old->>'employee_id');
    end if;
    v_action := lower(tg_op);
    v_operation_type := case tg_table_name
      when 'customers' then 'customer_'||lower(tg_op)
      when 'employees' then 'employee_'||lower(tg_op)
      when 'services' then 'service_'||lower(tg_op)
      when 'service_categories' then 'service_category_'||lower(tg_op)
      when 'business_memberships' then 'access_assignment'
      when 'business_settings' then 'settings_update'
      when 'business_holidays' then 'business_holiday_'||lower(tg_op)
      when 'appointment_payments' then case when v_new->>'reverses_payment_id' is not null then 'financial_refund' else 'financial_payment_create' end
      when 'business_expenses' then 'financial_expense_'||lower(tg_op)
      when 'employee_finance_entries' then 'financial_commission_entry'
      when 'employee_settlements' then 'financial_wallet_settlement'
      when 'employee_wallet_transactions' then 'financial_wallet_entry'
      when 'employee_pay_profiles' then 'financial_pay_profile_update'
      when 'employee_working_hours' then 'employee_schedule_update'
      when 'employee_schedule_exceptions' then 'employee_schedule_exception'
      when 'employee_leaves' then 'employee_leave_update'
      when 'employee_services' then 'employee_service_config_update'
      when 'employee_commission_rules' then 'employee_service_config_update'
      when 'employee_service_compensation' then 'employee_service_config_update'
      when 'app_records' then case v_entity_type when 'roles' then 'access_role_'||lower(tg_op)
        when 'settings' then 'settings_update' else v_entity_type||'_'||lower(tg_op) end
      else tg_table_name||'_'||lower(tg_op) end;
    v_type := case when tg_table_name='customers' and tg_op='INSERT' then 'customerRegistered'
      when tg_table_name='employees' and tg_op='INSERT' then 'employeeAdded'
      when tg_table_name in ('services','service_categories') then 'serviceModified'
      else 'settingsChanged' end;
    v_title := case
      when tg_table_name='customers' then case tg_op when 'INSERT' then 'ثبت مشتری' when 'UPDATE' then 'ویرایش مشتری' else 'حذف مشتری' end
      when tg_table_name='employees' then case tg_op when 'INSERT' then 'افزودن پرسنل' when 'UPDATE' then 'ویرایش پرسنل' else 'حذف پرسنل' end
      when tg_table_name in ('services','service_categories') then 'تغییر خدمات و دسته‌بندی'
      when tg_table_name='business_memberships' then 'تغییر نقش و دسترسی'
      when tg_table_name='business_settings' then 'تغییر تنظیمات مجموعه'
      when tg_table_name='business_holidays' then 'تغییر تعطیلات مجموعه'
      when tg_table_name='appointment_payments' then case when v_new->>'reverses_payment_id' is not null then 'برگشت وجه' else 'ثبت دریافت مشتری' end
      when tg_table_name='business_expenses' then 'ثبت یا اصلاح هزینه مجموعه'
      when tg_table_name='employee_finance_entries' then 'ثبت سند مالی پرسنل'
      when tg_table_name='employee_settlements' then 'تغییر وضعیت تسویه پرسنل'
      when tg_table_name='employee_wallet_transactions' then 'ثبت تراکنش کیف پول'
      when tg_table_name='employee_pay_profiles' then 'تغییر قرارداد مالی پرسنل'
      when tg_table_name in ('employee_working_hours','employee_schedule_exceptions','employee_leaves') then 'تغییر برنامه کاری پرسنل'
      when tg_table_name in ('employee_services','employee_commission_rules','employee_service_compensation') then 'تغییر تخصص و پورسانت خدمت'
      when tg_table_name='app_records' and v_entity_type='roles' then 'تغییر نقش دسترسی'
      when tg_table_name='app_records' and v_entity_type='settings' then 'تغییر تنظیمات'
      else 'ثبت تغییر در سامانه' end;
    v_is_reversible := tg_op='UPDATE' and tg_table_name in (
      'customers','employees','services','service_categories','business_settings','business_memberships',
      'app_records','employee_working_hours','employee_schedule_exceptions','employee_leaves',
      'employee_services','employee_commission_rules','employee_service_compensation','employee_pay_profiles');
    if tg_op='UPDATE' and v_old is not null and v_new is not null
       and (v_old-'updated_at')=(v_new-'updated_at') then return new; end if;
    if tg_op='INSERT' and v_new ? 'idempotency_key' then v_idempotency_key := nullif(v_new->>'idempotency_key',''); end if;
  end if;

  if v_business_id is null or v_actor_id is null or nullif(v_entity_id,'') is null then
    raise exception 'ACTIVITY_AUDIT_CONTEXT_MISSING' using errcode='23502';
  end if;
  select coalesce(nullif(p.display_name,''),'کاربر') into v_actor_name
    from public.profiles p where p.id=v_actor_id;
  v_actor_name := coalesce(v_actor_name,'کاربر');
  v_description := v_title || ' | شناسه: ' || v_entity_id;
  v_undo_of_event_id := nullif(current_setting('app.undo_of_event_id',true),'')::uuid;
  v_operation_id := nullif(current_setting('app.operation_id',true),'')::uuid;
  if v_operation_id is null then v_operation_id := gen_random_uuid(); end if;

  insert into public.business_activity_events (
    operation_id,business_id,actor_id,actor_name,source_table,entity_key_column,
    entity_type,entity_id,action,operation_type,type,title,description,before_state,
    after_state,idempotency_key,is_reversible,undo_of_event_id
  ) values (
    v_operation_id,v_business_id,v_actor_id,v_actor_name,v_source_table,v_key_column,
    v_entity_type,v_entity_id,v_action,v_operation_type,v_type,v_title,v_description,
    v_before,v_after,v_idempotency_key,v_is_reversible,v_undo_of_event_id
  ) on conflict do nothing;
  return coalesce(new,old);
end;
$function$;
revoke all on function public.capture_business_activity_event() from public,anon,authenticated;

drop trigger if exists activity_audit_app_records on public.app_records;
create trigger activity_audit_app_records after insert or update or delete on public.app_records for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_customers on public.customers;
create trigger activity_audit_customers after insert or update or delete on public.customers for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employees on public.employees;
create trigger activity_audit_employees after insert or update or delete on public.employees for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_services on public.services;
create trigger activity_audit_services after insert or update or delete on public.services for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_service_categories on public.service_categories;
create trigger activity_audit_service_categories after insert or update or delete on public.service_categories for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_business_settings on public.business_settings;
create trigger activity_audit_business_settings after insert or update or delete on public.business_settings for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_business_holidays on public.business_holidays;
create trigger activity_audit_business_holidays after insert or update or delete on public.business_holidays for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_business_memberships on public.business_memberships;
create trigger activity_audit_business_memberships after insert or update or delete on public.business_memberships for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_appointment_events on public.appointment_audit_events;
create trigger activity_audit_appointment_events after insert on public.appointment_audit_events for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_appointment_payments on public.appointment_payments;
create trigger activity_audit_appointment_payments after insert on public.appointment_payments for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_business_expenses on public.business_expenses;
create trigger activity_audit_business_expenses after insert or update or delete on public.business_expenses for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_finance_entries on public.employee_finance_entries;
create trigger activity_audit_employee_finance_entries after insert on public.employee_finance_entries for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_settlements on public.employee_settlements;
create trigger activity_audit_employee_settlements after insert or update on public.employee_settlements for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_wallet_transactions on public.employee_wallet_transactions;
create trigger activity_audit_employee_wallet_transactions after insert on public.employee_wallet_transactions for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_pay_profiles on public.employee_pay_profiles;
create trigger activity_audit_employee_pay_profiles after insert or update on public.employee_pay_profiles for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_working_hours on public.employee_working_hours;
create trigger activity_audit_employee_working_hours after insert or update or delete on public.employee_working_hours for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_schedule_exceptions on public.employee_schedule_exceptions;
create trigger activity_audit_employee_schedule_exceptions after insert or update or delete on public.employee_schedule_exceptions for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_leaves on public.employee_leaves;
create trigger activity_audit_employee_leaves after insert or update or delete on public.employee_leaves for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_services on public.employee_services;
create trigger activity_audit_employee_services after insert or update or delete on public.employee_services for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_commission_rules on public.employee_commission_rules;
create trigger activity_audit_employee_commission_rules after insert or update or delete on public.employee_commission_rules for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_service_compensation on public.employee_service_compensation;
create trigger activity_audit_employee_service_compensation after insert or update or delete on public.employee_service_compensation for each row execute function public.capture_business_activity_event();

create or replace function public.undo_business_activity_event(p_event_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
  v_event public.business_activity_events%rowtype; v_current jsonb; v_set_clause text;
  v_permission text; v_undo_event_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  select * into v_event from public.business_activity_events where id=p_event_id for update;
  if not found then raise exception 'ACTIVITY_EVENT_NOT_FOUND' using errcode='P0002'; end if;
  if v_event.undone_by_event_id is not null then return v_event.undone_by_event_id; end if;
  if not v_event.is_reversible or v_event.before_state is null or v_event.after_state is null then
    raise exception 'ACTIVITY_EVENT_NOT_REVERSIBLE' using errcode='22023'; end if;
  v_permission := case v_event.source_table
    when 'appointments' then 'appointments.manage' when 'customers' then 'customers.manage'
    when 'employees' then 'employees.manage' when 'services' then 'services.manage'
    when 'service_categories' then 'services.manage' when 'business_settings' then 'settings.manage'
    when 'business_memberships' then 'settings.roles.manage'
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
    'appointments','customers','employees','services','service_categories','business_settings',
    'business_memberships','app_records','employee_working_hours','employee_schedule_exceptions',
    'employee_leaves','employee_services','employee_commission_rules','employee_service_compensation','employee_pay_profiles'
  ) then raise exception 'ACTIVITY_UNDO_TABLE_NOT_ALLOWED' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where t.%I::text=$1 and t.business_id=$2 for update',
    v_event.source_table,v_event.entity_key_column) into v_current using v_event.entity_id,v_event.business_id;
  if v_current is null or (v_current-'updated_at') is distinct from (v_event.after_state-'updated_at') then
    raise exception 'ACTIVITY_UNDO_STALE_STATE' using errcode='40001'; end if;
  select string_agg(format('%1$I = src.%1$I',a.attname),', ' order by a.attnum) into v_set_clause
    from pg_attribute a where a.attrelid=format('public.%I',v_event.source_table)::regclass
      and a.attnum>0 and not a.attisdropped and a.attgenerated='' and a.attidentity=''
      and a.attname not in ('id','business_id','created_at','created_by','updated_at',v_event.entity_key_column);
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
  update public.business_activity_events set undone_by_event_id=v_undo_event_id where id=p_event_id and undone_by_event_id is null;
  perform set_config('app.undo_of_event_id','',true);
  perform set_config('app.operation_id','',true);
  return v_undo_event_id;
end;
$function$;
revoke all on function public.undo_business_activity_event(uuid) from public,anon;
grant execute on function public.undo_business_activity_event(uuid) to authenticated;
