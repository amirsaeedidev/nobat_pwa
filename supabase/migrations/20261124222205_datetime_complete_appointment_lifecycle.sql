-- Stage 7: full Supabase-backed appointment lifecycle, validation and audit.

alter table public.appointments
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id);

alter table public.appointment_services
  add column if not exists category_snapshot text not null default '',
  add column if not exists description_snapshot text not null default '',
  add column if not exists list_price_toman_snapshot bigint not null default 0,
  add column if not exists discount_toman_snapshot bigint not null default 0,
  add column if not exists commission_rate_bps_snapshot integer not null default 0,
  add column if not exists fixed_commission_amount_toman_snapshot bigint not null default 0;

alter table public.appointment_services
  add constraint appointment_services_list_price_snapshot_check check (list_price_toman_snapshot >= 0),
  add constraint appointment_services_discount_snapshot_check check (discount_toman_snapshot >= 0 and discount_toman_snapshot <= list_price_toman_snapshot),
  add constraint appointment_services_commission_rate_snapshot_check check (commission_rate_bps_snapshot between 0 and 10000),
  add constraint appointment_services_fixed_commission_snapshot_check check (fixed_commission_amount_toman_snapshot >= 0);

create index if not exists appointments_active_deleted_idx
  on public.appointments (business_id, starts_at desc) where deleted_at is null;

create table if not exists public.appointment_audit_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  appointment_id uuid not null,
  action text not null check (action in (
    'appointment_created','appointment_updated','appointment_rescheduled',
    'appointment_status_changed','appointment_deleted',
    'service_snapshot_added','service_snapshot_removed'
  )),
  actor_id uuid not null references auth.users(id),
  reason text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now(),
  constraint appointment_audit_events_appointment_fk
    foreign key (business_id, appointment_id) references public.appointments(business_id, id) on delete restrict
);
create index if not exists appointment_audit_events_timeline_idx
  on public.appointment_audit_events (business_id, appointment_id, created_at desc);
create index if not exists appointment_audit_events_business_created_idx
  on public.appointment_audit_events (business_id, created_at desc);

alter table public.appointment_audit_events enable row level security;
revoke all on public.appointment_audit_events from anon, public;
grant select on public.appointment_audit_events to authenticated;
create policy appointment_audit_events_read_scoped
  on public.appointment_audit_events for select to authenticated
  using (
    private.has_business_permission(business_id,'appointments.view_all')
    or exists (
      select 1 from public.appointments a
      where a.business_id=appointment_audit_events.business_id
        and a.id=appointment_audit_events.appointment_id
        and a.employee_id=private.current_employee_id(appointment_audit_events.business_id)
        and private.has_business_permission(appointment_audit_events.business_id,'appointments.view_self')
    )
  );

CREATE OR REPLACE FUNCTION private.write_appointment_audit(p_business_id uuid, p_appointment_id uuid, p_action text, p_before jsonb, p_after jsonb, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_event_id uuid := gen_random_uuid();
  v_actor uuid := auth.uid();
  v_type text;
  v_title text;
  v_operation text;
  v_description text;
begin
  if v_actor is null then
    select coalesce((p_after->>'created_by')::uuid,(p_before->>'created_by')::uuid)
      into v_actor;
  end if;
  if v_actor is null then
    raise exception 'AUTH_REQUIRED_FOR_APPOINTMENT_AUDIT' using errcode='42501';
  end if;

  v_operation := case p_action
    when 'appointment_created' then 'appointment_create'
    when 'appointment_updated' then 'appointment_update'
    when 'appointment_rescheduled' then 'appointment_reschedule'
    when 'appointment_deleted' then 'appointment_delete'
    when 'service_snapshot_added' then 'appointment_update'
    when 'service_snapshot_removed' then 'appointment_update'
    when 'appointment_status_changed' then
      case coalesce(p_after->>'status','')
        when 'rejected' then 'appointment_reject'
        when 'cancelled' then 'appointment_cancel'
        when 'completed' then 'appointment_complete'
        when 'confirmed' then 'appointment_confirm'
        when 'no_show' then 'appointment_no_show'
        else 'appointment_update'
      end
    else 'appointment_update'
  end;

  v_type := case
    when p_action='appointment_created' then 'appointmentCreated'
    when p_action='appointment_deleted' then 'appointmentCancelled'
    when p_action='appointment_status_changed' and p_after->>'status'='completed' then 'appointmentCompleted'
    when p_action='appointment_status_changed' and p_after->>'status' in ('cancelled','rejected') then 'appointmentCancelled'
    when p_action='appointment_rescheduled' or p_action='appointment_updated'
      or p_action in ('service_snapshot_added','service_snapshot_removed')
      or p_action='appointment_status_changed' then 'appointmentUpdated'
    else 'appointmentUpdated'
  end;

  v_title := case p_action
    when 'appointment_created' then 'ثبت نوبت'
    when 'appointment_updated' then 'ویرایش نوبت'
    when 'appointment_rescheduled' then 'تغییر زمان نوبت'
    when 'appointment_deleted' then 'حذف امن نوبت'
    when 'service_snapshot_added' then 'ثبت Snapshot خدمت نوبت'
    when 'service_snapshot_removed' then 'ثبت سابقه Snapshot خدمت'
    when 'appointment_status_changed' then
      case coalesce(p_after->>'status','')
        when 'confirmed' then 'تأیید نوبت'
        when 'rejected' then 'رد نوبت'
        when 'cancelled' then 'لغو نوبت'
        when 'completed' then 'تکمیل نوبت'
        when 'no_show' then 'ثبت عدم حضور'
        else 'تغییر وضعیت نوبت'
      end
    else 'تغییر نوبت'
  end;

  v_description := coalesce(nullif(p_reason,''), v_title);
  if p_action like 'service_snapshot_%' then
    v_description := v_title || ': ' || coalesce(p_after->>'title_snapshot',p_before->>'title_snapshot','خدمت');
  end if;

  insert into public.appointment_audit_events(
    id,business_id,appointment_id,action,actor_id,reason,before_state,after_state
  ) values (
    v_event_id,p_business_id,p_appointment_id,p_action,v_actor,p_reason,p_before,p_after
  );

  insert into public.app_records(
    business_id,entity_type,record_id,payload,created_by,updated_by
  ) values (
    p_business_id,
    'activity_logs',
    v_event_id::text,
    jsonb_build_object(
      'id',v_event_id::text,
      'type',v_type,
      'title',v_title,
      'description',v_description,
      'actor',v_actor::text,
      'created_at',now(),
      'entity_name','نوبت',
      'entity_id',p_appointment_id::text,
      'operation_type',v_operation,
      'is_reversible',false,
      'undo_action',null,
      'undo_data',null,
      'idempotency_key',null
    ),
    v_actor,
    v_actor
  );
  return v_event_id;
end;
$function$


CREATE OR REPLACE FUNCTION private.capture_appointment_row_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_action text;
  v_reason text;
begin
  if tg_op='INSERT' then
    v_action := 'appointment_created';
    perform private.write_appointment_audit(new.business_id,new.id,v_action,null,to_jsonb(new),null);
    return new;
  end if;

  if old.deleted_at is null and new.deleted_at is not null then
    v_action := 'appointment_deleted';
  elsif old.status is distinct from new.status then
    v_action := 'appointment_status_changed';
  elsif old.starts_at is distinct from new.starts_at or old.ends_at is distinct from new.ends_at then
    v_action := 'appointment_rescheduled';
  else
    v_action := 'appointment_updated';
  end if;
  v_reason := coalesce(new.cancel_reason,case when new.deleted_at is not null then 'حذف امن نوبت' else null end);
  perform private.write_appointment_audit(new.business_id,new.id,v_action,to_jsonb(old),to_jsonb(new),v_reason);
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION private.capture_appointment_service_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row record;
  v_action text;
begin
  if tg_op='INSERT' then
    v_row := new;
    v_action := 'service_snapshot_added';
    perform private.write_appointment_audit(
      new.business_id,new.appointment_id,v_action,null,to_jsonb(new),null
    );
    return new;
  end if;
  v_row := old;
  v_action := 'service_snapshot_removed';
  perform private.write_appointment_audit(
    old.business_id,old.appointment_id,v_action,to_jsonb(old),null,'نسخه قبلی Snapshot حفظ شد'
  );
  return old;
end;
$function$


CREATE OR REPLACE FUNCTION private.validate_appointment_slot(p_business_id uuid, p_customer_id uuid, p_employee_id uuid, p_starts_at timestamp with time zone, p_service_ids uuid[], p_ignore_appointment_id uuid DEFAULT NULL::uuid, p_duration_override integer DEFAULT NULL::integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_timezone text;
  v_local_start timestamp;
  v_local_end timestamp;
  v_weekday integer;
  v_start_time time;
  v_end_time time;
  v_duration integer;
  v_service_count integer;
  v_employee_buffer integer;
  v_service record;
  v_existing_count integer;
  v_end_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  if p_service_ids is null or cardinality(p_service_ids)=0 then
    raise exception 'APPOINTMENT_REQUIRES_SERVICES' using errcode='22023';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.business_id=p_business_id and c.id=p_customer_id and c.is_active
  ) then
    raise exception 'CUSTOMER_NOT_ACTIVE_OR_NOT_FOUND' using errcode='23503';
  end if;

  select b.timezone into v_timezone
  from public.businesses b where b.id=p_business_id;
  if v_timezone is null or not exists(select 1 from pg_timezone_names where name=v_timezone) then
    raise exception 'BUSINESS_TIMEZONE_INVALID' using errcode='22023';
  end if;

  select e.buffer_minutes into v_employee_buffer
  from public.employees e
  where e.business_id=p_business_id and e.id=p_employee_id
    and e.is_active and e.schedule_enabled;
  if not found then
    raise exception 'EMPLOYEE_SCHEDULE_DISABLED_OR_NOT_FOUND' using errcode='23503';
  end if;
  v_employee_buffer := greatest(coalesce(v_employee_buffer,0),0);

  -- Serialize all slot validations for one employee; the GiST exclusion
  -- constraint remains the final race-safe guard against concurrent overlap.
  perform pg_advisory_xact_lock(hashtextextended(
    p_business_id::text || ':employee:' || p_employee_id::text,0
  ));

  select count(*),coalesce(sum(coalesce(es.custom_duration_minutes,
      s.duration_minutes+s.prep_minutes+s.buffer_minutes)),0)
    into v_service_count,v_duration
  from public.services s
  join public.employee_services es
    on es.business_id=s.business_id and es.service_id=s.id
   and es.employee_id=p_employee_id and es.is_active
  where s.business_id=p_business_id and s.id=any(p_service_ids)
    and s.is_active and s.archived_at is null;
  if v_service_count<>cardinality(p_service_ids) then
    raise exception 'SERVICE_NOT_ACTIVE_OR_NOT_ASSIGNED_TO_EMPLOYEE' using errcode='23503';
  end if;

  if p_duration_override is not null then
    v_duration := p_duration_override;
  end if;
  if v_duration<1 or v_duration>1440 then
    raise exception 'APPOINTMENT_DURATION_INVALID' using errcode='22023';
  end if;

  v_end_at := p_starts_at + make_interval(mins=>v_duration);
  v_local_start := p_starts_at at time zone v_timezone;
  v_local_end := v_end_at at time zone v_timezone;
  if v_local_start::date<>v_local_end::date then
    raise exception 'APPOINTMENT_CANNOT_CROSS_BUSINESS_DAY' using errcode='22023';
  end if;
  v_weekday := extract(dow from v_local_start)::integer;
  v_start_time := v_local_start::time;
  v_end_time := v_local_end::time;

  -- Serialize daily service capacity checks so two concurrent bookings cannot
  -- both consume the final service slot.
  for v_service in
    select s.id,s.max_per_day,s.advance_days
    from public.services s
    where s.business_id=p_business_id and s.id=any(p_service_ids)
    order by s.id
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      p_business_id::text || ':service:' || v_service.id::text || ':' || v_local_start::date::text,0
    ));

    if v_local_start::date > (now() at time zone v_timezone)::date + v_service.advance_days then
      raise exception 'SERVICE_ADVANCE_BOOKING_LIMIT' using errcode='22023';
    end if;

    if v_service.max_per_day is not null then
      select count(*) into v_existing_count
      from public.appointment_services aps
      join public.appointments a
        on a.business_id=aps.business_id and a.id=aps.appointment_id
      where aps.business_id=p_business_id and aps.service_id=v_service.id
        and (a.starts_at at time zone v_timezone)::date=v_local_start::date
        and a.status not in ('cancelled','rejected')
        and a.deleted_at is null
        and (p_ignore_appointment_id is null or a.id<>p_ignore_appointment_id);
      if v_existing_count>=v_service.max_per_day then
        raise exception 'SERVICE_DAILY_CAPACITY_REACHED' using errcode='22023';
      end if;
    end if;
  end loop;

  if exists (
    select 1 from public.employee_leaves l
    where l.business_id=p_business_id and l.employee_id=p_employee_id
      and l.status='approved'
      and tstzrange(l.starts_at,l.ends_at,'[)') && tstzrange(p_starts_at,v_end_at,'[)')
  ) then
    raise exception 'EMPLOYEE_ON_APPROVED_LEAVE' using errcode='23P01';
  end if;

  if exists (
    select 1 from public.employee_schedule_exceptions x
    where x.business_id=p_business_id and x.employee_id=p_employee_id
      and x.work_date=v_local_start::date and x.is_available=false
  ) then
    raise exception 'EMPLOYEE_NOT_AVAILABLE_ON_DATE' using errcode='22023';
  end if;

  if exists (
    select 1 from public.employee_schedule_exceptions x
    where x.business_id=p_business_id and x.employee_id=p_employee_id
      and x.work_date=v_local_start::date and x.is_available=true
  ) then
    if not exists (
      select 1 from public.employee_schedule_exceptions x
      where x.business_id=p_business_id and x.employee_id=p_employee_id
        and x.work_date=v_local_start::date and x.is_available=true
        and x.starts_at<=v_start_time and x.ends_at>=v_end_time
    ) then
      raise exception 'OUTSIDE_EXCEPTION_WORKING_HOURS' using errcode='22023';
    end if;
  elsif not exists (
    select 1 from public.employee_working_hours h
    where h.business_id=p_business_id and h.employee_id=p_employee_id
      and h.weekday=v_weekday and h.is_active
      and (h.valid_from is null or h.valid_from<=v_local_start::date)
      and (h.valid_until is null or h.valid_until>=v_local_start::date)
      and h.starts_at<=v_start_time and h.ends_at>=v_end_time
      and not (
        h.break_starts_at is not null and h.break_ends_at is not null
        and h.break_starts_at<v_end_time and h.break_ends_at>v_start_time
      )
  ) then
    raise exception 'OUTSIDE_EMPLOYEE_WORKING_HOURS' using errcode='22023';
  end if;

  -- One active appointment per employee at a time, with the configured
  -- employee buffer applied on both sides of the slot.
  if exists (
    select 1
    from public.appointments a
    where a.business_id=p_business_id and a.employee_id=p_employee_id
      and a.status in ('pending','confirmed')
      and a.deleted_at is null
      and (p_ignore_appointment_id is null or a.id<>p_ignore_appointment_id)
      and tstzrange(
        a.starts_at,
        a.ends_at+make_interval(mins=>v_employee_buffer),
        '[)'
      ) && tstzrange(
        p_starts_at,
        v_end_at+make_interval(mins=>v_employee_buffer),
        '[)'
      )
  ) then
    raise exception 'APPOINTMENT_TIME_CONFLICT' using errcode='23P01';
  end if;

  return v_end_at;
end;
$function$


CREATE OR REPLACE FUNCTION public.create_appointment(p_business_id uuid, p_customer_id uuid, p_employee_id uuid, p_starts_at timestamp with time zone, p_service_ids uuid[], p_reference text, p_note text DEFAULT ''::text, p_idempotency_key text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_appointment_id uuid;
  v_end_at timestamptz;
  v_duration integer;
  v_price bigint;
  v_discount bigint;
  v_service_count integer;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  if not (
    private.has_business_permission(p_business_id,'appointments.manage')
    or (
      private.current_employee_id(p_business_id)=p_employee_id
      and private.has_business_permission(p_business_id,'appointments.manage_self')
    )
  ) then
    raise exception 'APPOINTMENT_CREATE_FORBIDDEN' using errcode='42501';
  end if;

  if p_idempotency_key is not null then
    select a.id into v_appointment_id
    from public.appointments a
    where a.business_id=p_business_id and a.idempotency_key=p_idempotency_key;
    if v_appointment_id is not null then
      return v_appointment_id;
    end if;
  end if;

  v_end_at := private.validate_appointment_slot(
    p_business_id,p_customer_id,p_employee_id,p_starts_at,p_service_ids,null,null
  );

  select count(*),
    coalesce(sum(coalesce(es.custom_duration_minutes,s.duration_minutes+s.prep_minutes+s.buffer_minutes)),0),
    coalesce(sum(coalesce(es.custom_price_toman,
      case when s.discount_price_toman is not null
        and (p_starts_at at time zone b.timezone)::date
          between coalesce(s.discount_starts_on,'-infinity'::date)
              and coalesce(s.discount_ends_on,'infinity'::date)
        then s.discount_price_toman else s.price_toman end)),0),
    coalesce(sum(case when es.custom_price_toman is null
      then greatest(s.price_toman-case when s.discount_price_toman is not null
        and (p_starts_at at time zone b.timezone)::date
          between coalesce(s.discount_starts_on,'-infinity'::date)
              and coalesce(s.discount_ends_on,'infinity'::date)
        then s.discount_price_toman else s.price_toman end,0)
      else 0 end),0)
  into v_service_count,v_duration,v_price,v_discount
  from public.services s
  join public.employee_services es
    on es.business_id=s.business_id and es.service_id=s.id
   and es.employee_id=p_employee_id and es.is_active
  join public.businesses b on b.id=p_business_id
  where s.business_id=p_business_id and s.id=any(p_service_ids)
    and s.is_active and s.archived_at is null;
  if v_service_count<>cardinality(p_service_ids) then
    raise exception 'SERVICE_NOT_ACTIVE_OR_NOT_ASSIGNED_TO_EMPLOYEE' using errcode='23503';
  end if;

  select case when bool_or(s.requires_confirmation) then 'pending' else 'confirmed' end
    into v_status
  from public.services s
  where s.business_id=p_business_id and s.id=any(p_service_ids);

  insert into public.appointments(
    business_id,reference,customer_id,employee_id,starts_at,ends_at,status,note,
    price_toman,discount_toman,idempotency_key,created_by
  ) values (
    p_business_id,p_reference,p_customer_id,p_employee_id,p_starts_at,v_end_at,
    coalesce(v_status,'confirmed'),coalesce(p_note,''),v_price,v_discount,
    p_idempotency_key,auth.uid()
  ) returning id into v_appointment_id;

  insert into public.appointment_services(
    business_id,appointment_id,service_id,title_snapshot,category_snapshot,
    description_snapshot,duration_minutes,price_toman,list_price_toman_snapshot,
    discount_toman_snapshot,commission_rate_bps_snapshot,
    fixed_commission_amount_toman_snapshot,sort_order
  )
  select p_business_id,v_appointment_id,s.id,s.title,coalesce(s.category,''),
    coalesce(s.description,''),coalesce(es.custom_duration_minutes,s.duration_minutes+s.prep_minutes+s.buffer_minutes),
    coalesce(es.custom_price_toman,
      case when s.discount_price_toman is not null
        and (p_starts_at at time zone b.timezone)::date
          between coalesce(s.discount_starts_on,'-infinity'::date)
              and coalesce(s.discount_ends_on,'infinity'::date)
        then s.discount_price_toman else s.price_toman end),
    coalesce(es.custom_price_toman,s.price_toman),
    case when es.custom_price_toman is null then greatest(s.price_toman-
      case when s.discount_price_toman is not null
        and (p_starts_at at time zone b.timezone)::date
          between coalesce(s.discount_starts_on,'-infinity'::date)
              and coalesce(s.discount_ends_on,'infinity'::date)
        then s.discount_price_toman else s.price_toman end,0) else 0 end,
    coalesce(c.commission_rate_bps,0),
    coalesce(c.fixed_commission_amount_toman,0),
    array_position(p_service_ids,s.id)
  from public.services s
  join public.employee_services es
    on es.business_id=s.business_id and es.service_id=s.id
   and es.employee_id=p_employee_id and es.is_active
  join public.businesses b on b.id=p_business_id
  left join public.employee_service_compensation c
    on c.business_id=s.business_id and c.employee_id=p_employee_id and c.service_id=s.id
  where s.business_id=p_business_id and s.id=any(p_service_ids)
    and s.is_active and s.archived_at is null;

  return v_appointment_id;
exception
  when exclusion_violation then
    raise exception 'APPOINTMENT_TIME_CONFLICT' using errcode='23P01';
end;
$function$


CREATE OR REPLACE FUNCTION public.update_appointment(p_appointment_id uuid, p_customer_id uuid, p_employee_id uuid, p_starts_at timestamp with time zone, p_service_ids uuid[], p_note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_business_id uuid;
  v_current_customer_id uuid;
  v_current_employee_id uuid;
  v_current_start timestamptz;
  v_current_status text;
  v_old_service_ids uuid[];
  v_old_duration integer;
  v_same_assignment boolean;
  v_end_at timestamptz;
  v_price bigint;
  v_discount bigint;
  v_service_count integer;
begin
  select a.business_id,a.customer_id,a.employee_id,a.starts_at,a.status
    into v_business_id,v_current_customer_id,v_current_employee_id,v_current_start,v_current_status
  from public.appointments a
  where a.id=p_appointment_id and a.deleted_at is null
  for update;
  if v_business_id is null or v_current_status not in ('pending','confirmed') then
    raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;

  if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (
      private.current_employee_id(v_business_id)=v_current_employee_id
      and p_employee_id=v_current_employee_id
      and private.has_business_permission(v_business_id,'appointments.manage_self')
    )
  ) then
    raise exception 'APPOINTMENT_UPDATE_FORBIDDEN' using errcode='42501';
  end if;

  select coalesce(array_agg(aps.service_id order by aps.sort_order),array[]::uuid[]),
         coalesce(sum(aps.duration_minutes),0)
    into v_old_service_ids,v_old_duration
  from public.appointment_services aps
  where aps.business_id=v_business_id and aps.appointment_id=p_appointment_id;

  v_same_assignment := v_current_employee_id=p_employee_id and v_old_service_ids=p_service_ids;
  v_end_at := private.validate_appointment_slot(
    v_business_id,p_customer_id,p_employee_id,p_starts_at,p_service_ids,
    p_appointment_id,case when v_same_assignment then v_old_duration else null end
  );

  if not v_same_assignment then
    select count(*),
      coalesce(sum(coalesce(es.custom_price_toman,
        case when s.discount_price_toman is not null
          and (p_starts_at at time zone b.timezone)::date
            between coalesce(s.discount_starts_on,'-infinity'::date)
                and coalesce(s.discount_ends_on,'infinity'::date)
          then s.discount_price_toman else s.price_toman end)),0),
      coalesce(sum(case when es.custom_price_toman is null
        then greatest(s.price_toman-case when s.discount_price_toman is not null
          and (p_starts_at at time zone b.timezone)::date
            between coalesce(s.discount_starts_on,'-infinity'::date)
                and coalesce(s.discount_ends_on,'infinity'::date)
          then s.discount_price_toman else s.price_toman end,0)
        else 0 end),0)
    into v_service_count,v_price,v_discount
    from public.services s
    join public.employee_services es
      on es.business_id=s.business_id and es.service_id=s.id
     and es.employee_id=p_employee_id and es.is_active
    join public.businesses b on b.id=v_business_id
    where s.business_id=v_business_id and s.id=any(p_service_ids)
      and s.is_active and s.archived_at is null;
    if v_service_count<>cardinality(p_service_ids) then
      raise exception 'SERVICE_NOT_ACTIVE_OR_NOT_ASSIGNED_TO_EMPLOYEE' using errcode='23503';
    end if;

    delete from public.appointment_services
    where business_id=v_business_id and appointment_id=p_appointment_id;

    insert into public.appointment_services(
      business_id,appointment_id,service_id,title_snapshot,category_snapshot,
      description_snapshot,duration_minutes,price_toman,list_price_toman_snapshot,
      discount_toman_snapshot,commission_rate_bps_snapshot,
      fixed_commission_amount_toman_snapshot,sort_order
    )
    select v_business_id,p_appointment_id,s.id,s.title,coalesce(s.category,''),
      coalesce(s.description,''),coalesce(es.custom_duration_minutes,s.duration_minutes+s.prep_minutes+s.buffer_minutes),
      coalesce(es.custom_price_toman,
        case when s.discount_price_toman is not null
          and (p_starts_at at time zone b.timezone)::date
            between coalesce(s.discount_starts_on,'-infinity'::date)
                and coalesce(s.discount_ends_on,'infinity'::date)
          then s.discount_price_toman else s.price_toman end),
      coalesce(es.custom_price_toman,s.price_toman),
      case when es.custom_price_toman is null then greatest(s.price_toman-
        case when s.discount_price_toman is not null
          and (p_starts_at at time zone b.timezone)::date
            between coalesce(s.discount_starts_on,'-infinity'::date)
                and coalesce(s.discount_ends_on,'infinity'::date)
          then s.discount_price_toman else s.price_toman end,0) else 0 end,
      coalesce(c.commission_rate_bps,0),coalesce(c.fixed_commission_amount_toman,0),
      array_position(p_service_ids,s.id)
    from public.services s
    join public.employee_services es
      on es.business_id=s.business_id and es.service_id=s.id
     and es.employee_id=p_employee_id and es.is_active
    join public.businesses b on b.id=v_business_id
    left join public.employee_service_compensation c
      on c.business_id=s.business_id and c.employee_id=p_employee_id and c.service_id=s.id
    where s.business_id=v_business_id and s.id=any(p_service_ids)
      and s.is_active and s.archived_at is null;
  else
    select a.price_toman,a.discount_toman into v_price,v_discount
    from public.appointments a where a.id=p_appointment_id;
  end if;

  update public.appointments
  set customer_id=p_customer_id,
      employee_id=p_employee_id,
      starts_at=p_starts_at,
      ends_at=v_end_at,
      note=coalesce(p_note,''),
      price_toman=coalesce(v_price,price_toman),
      discount_toman=coalesce(v_discount,discount_toman),
      reschedule_count=reschedule_count+case when starts_at is distinct from p_starts_at then 1 else 0 end
  where id=p_appointment_id;
exception
  when exclusion_violation then
    raise exception 'APPOINTMENT_TIME_CONFLICT' using errcode='23P01';
end;
$function$


CREATE OR REPLACE FUNCTION public.reschedule_appointment(p_appointment_id uuid, p_new_starts_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_business_id uuid;
  v_customer_id uuid;
  v_employee_id uuid;
  v_service_ids uuid[];
  v_duration integer;
  v_end_at timestamptz;
begin
  select a.business_id,a.customer_id,a.employee_id
    into v_business_id,v_customer_id,v_employee_id
  from public.appointments a
  where a.id=p_appointment_id and a.deleted_at is null
    and a.status in ('pending','confirmed')
  for update;
  if v_business_id is null then
    raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;

  if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (
      private.current_employee_id(v_business_id)=v_employee_id
      and private.has_business_permission(v_business_id,'appointments.manage_self')
    )
  ) then
    raise exception 'APPOINTMENT_UPDATE_FORBIDDEN' using errcode='42501';
  end if;

  select coalesce(array_agg(aps.service_id order by aps.sort_order),array[]::uuid[]),
         coalesce(sum(aps.duration_minutes),0)
    into v_service_ids,v_duration
  from public.appointment_services aps
  where aps.business_id=v_business_id and aps.appointment_id=p_appointment_id;

  v_end_at := private.validate_appointment_slot(
    v_business_id,v_customer_id,v_employee_id,p_new_starts_at,
    v_service_ids,p_appointment_id,v_duration
  );

  update public.appointments
  set starts_at=p_new_starts_at,
      ends_at=v_end_at,
      reschedule_count=reschedule_count+1
  where id=p_appointment_id;
exception
  when exclusion_violation then
    raise exception 'APPOINTMENT_TIME_CONFLICT' using errcode='23P01';
end;
$function$


CREATE OR REPLACE FUNCTION public.set_appointment_status(p_appointment_id uuid, p_status text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_business_id uuid;
  v_employee_id uuid;
  v_current_status text;
  v_deleted_at timestamptz;
begin
  if p_status not in ('pending','confirmed','completed','cancelled','rejected','no_show') then
    raise exception 'INVALID_APPOINTMENT_STATUS' using errcode='22023';
  end if;

  select a.business_id,a.employee_id,a.status,a.deleted_at
    into v_business_id,v_employee_id,v_current_status,v_deleted_at
  from public.appointments a
  where a.id=p_appointment_id
  for update;
  if v_business_id is null or v_deleted_at is not null then
    raise exception 'APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;

  if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (
      private.current_employee_id(v_business_id)=v_employee_id
      and private.has_business_permission(v_business_id,'appointments.manage_self')
    )
  ) then
    raise exception 'APPOINTMENT_UPDATE_FORBIDDEN' using errcode='42501';
  end if;

  if v_current_status=p_status then
    return;
  end if;

  if not (
    (v_current_status='pending' and p_status in ('confirmed','cancelled','rejected'))
    or (v_current_status='confirmed' and p_status in ('completed','cancelled','no_show'))
  ) then
    raise exception 'INVALID_APPOINTMENT_STATUS_TRANSITION' using errcode='22023';
  end if;

  update public.appointments
  set status=p_status,
      cancel_reason=case when p_status in ('cancelled','rejected') then nullif(trim(coalesce(p_reason,'')),'') else cancel_reason end,
      cancelled_at=case when p_status in ('cancelled','rejected') then now() else cancelled_at end
  where id=p_appointment_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.delete_appointment(p_appointment_id uuid, p_reason text DEFAULT 'حذف امن از پنل مدیریت'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_business_id uuid;
  v_employee_id uuid;
begin
  select a.business_id,a.employee_id into v_business_id,v_employee_id
  from public.appointments a
  where a.id=p_appointment_id and a.deleted_at is null
  for update;
  if v_business_id is null then
    raise exception 'APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;
  if not private.has_business_permission(v_business_id,'appointments.manage') then
    raise exception 'APPOINTMENT_DELETE_FORBIDDEN' using errcode='42501';
  end if;

  update public.appointments
  set status=case when status in ('pending','confirmed') then 'cancelled' else status end,
      cancel_reason=coalesce(nullif(trim(p_reason),''),'حذف امن نوبت'),
      cancelled_at=case when status in ('pending','confirmed') then now() else cancelled_at end,
      deleted_at=now(),
      deleted_by=auth.uid()
  where id=p_appointment_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.list_appointments(p_business_id uuid, p_query text DEFAULT ''::text, p_status text DEFAULT NULL::text, p_service_id uuid DEFAULT NULL::uuid, p_employee_id uuid DEFAULT NULL::uuid, p_customer_id uuid DEFAULT NULL::uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20, p_ascending boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_total bigint;
  v_items jsonb;
  v_employee_id uuid;
  v_query text := trim(coalesce(p_query,''));
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  if not (
    private.has_business_permission(p_business_id,'appointments.view_all')
    or private.has_business_permission(p_business_id,'appointments.view_self')
  ) then
    raise exception 'APPOINTMENT_READ_FORBIDDEN' using errcode='42501';
  end if;
  if p_page<1 or p_page_size<1 or p_page_size>100 then
    raise exception 'APPOINTMENT_PAGE_INVALID' using errcode='22023';
  end if;
  v_employee_id := private.current_employee_id(p_business_id);

  with filtered as (
    select a.*,c.full_name as customer_full_name,c.phone as customer_phone,
      e.full_name as employee_full_name
    from public.appointments a
    join public.customers c on c.business_id=a.business_id and c.id=a.customer_id
    join public.employees e on e.business_id=a.business_id and e.id=a.employee_id
    where a.business_id=p_business_id
      and a.deleted_at is null
      and (
        private.has_business_permission(p_business_id,'appointments.view_all')
        or (private.has_business_permission(p_business_id,'appointments.view_self') and a.employee_id=v_employee_id)
      )
      and (p_status is null or
        (p_status='cancelled' and a.status in ('cancelled','rejected')) or a.status=p_status)
      and (p_employee_id is null or a.employee_id=p_employee_id)
      and (p_customer_id is null or a.customer_id=p_customer_id)
      and (p_from is null or a.starts_at>=p_from)
      and (p_to is null or a.starts_at<p_to)
      and (p_service_id is null or exists (
        select 1 from public.appointment_services sf
        where sf.business_id=a.business_id and sf.appointment_id=a.id and sf.service_id=p_service_id
      ))
      and (v_query='' or
        concat_ws(' ',a.reference,a.note,c.full_name,c.phone,e.full_name) ilike '%'||v_query||'%'
        or exists (
          select 1 from public.appointment_services sq
          where sq.business_id=a.business_id and sq.appointment_id=a.id
            and sq.title_snapshot ilike '%'||v_query||'%'
        ))
  )
  select count(*) into v_total from filtered;

  with filtered as (
    select a.*,c.full_name as customer_full_name,c.phone as customer_phone,
      e.full_name as employee_full_name
    from public.appointments a
    join public.customers c on c.business_id=a.business_id and c.id=a.customer_id
    join public.employees e on e.business_id=a.business_id and e.id=a.employee_id
    where a.business_id=p_business_id
      and a.deleted_at is null
      and (
        private.has_business_permission(p_business_id,'appointments.view_all')
        or (private.has_business_permission(p_business_id,'appointments.view_self') and a.employee_id=v_employee_id)
      )
      and (p_status is null or
        (p_status='cancelled' and a.status in ('cancelled','rejected')) or a.status=p_status)
      and (p_employee_id is null or a.employee_id=p_employee_id)
      and (p_customer_id is null or a.customer_id=p_customer_id)
      and (p_from is null or a.starts_at>=p_from)
      and (p_to is null or a.starts_at<p_to)
      and (p_service_id is null or exists (
        select 1 from public.appointment_services sf
        where sf.business_id=a.business_id and sf.appointment_id=a.id and sf.service_id=p_service_id
      ))
      and (v_query='' or
        concat_ws(' ',a.reference,a.note,c.full_name,c.phone,e.full_name) ilike '%'||v_query||'%'
        or exists (
          select 1 from public.appointment_services sq
          where sq.business_id=a.business_id and sq.appointment_id=a.id
            and sq.title_snapshot ilike '%'||v_query||'%'
        ))
  )
  select coalesce(jsonb_agg(page_rows.item),'[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'id',a.id,
      'reference',a.reference,
      'customer_id',a.customer_id,
      'employee_id',a.employee_id,
      'starts_at',a.starts_at,
      'ends_at',a.ends_at,
      'status',a.status,
      'note',a.note,
      'price_toman',a.price_toman,
      'discount_toman',a.discount_toman,
      'reschedule_count',a.reschedule_count,
      'cancel_reason',a.cancel_reason,
      'created_by',a.created_by,
      'created_at',a.created_at,
      'updated_at',a.updated_at,
      'customers',jsonb_build_object('full_name',a.customer_full_name,'phone',a.customer_phone),
      'employees',jsonb_build_object('full_name',a.employee_full_name),
      'appointment_services',coalesce((
        select jsonb_agg(jsonb_build_object(
          'service_id',aps.service_id,
          'title_snapshot',aps.title_snapshot,
          'category_snapshot',aps.category_snapshot,
          'description_snapshot',aps.description_snapshot,
          'duration_minutes',aps.duration_minutes,
          'price_toman',aps.price_toman,
          'list_price_toman_snapshot',aps.list_price_toman_snapshot,
          'discount_toman_snapshot',aps.discount_toman_snapshot,
          'commission_rate_bps_snapshot',aps.commission_rate_bps_snapshot,
          'fixed_commission_amount_toman_snapshot',aps.fixed_commission_amount_toman_snapshot,
          'sort_order',aps.sort_order
        ) order by aps.sort_order)
        from public.appointment_services aps
        where aps.business_id=a.business_id and aps.appointment_id=a.id
      ),'[]'::jsonb)
    ) as item,
    a.starts_at
    from filtered a
    order by
      case when p_ascending then a.starts_at end asc,
      case when not p_ascending then a.starts_at end desc,
      a.id
    limit p_page_size offset (p_page-1)*p_page_size
  ) page_rows;

  return jsonb_build_object(
    'items',v_items,
    'total',v_total,
    'page',p_page,
    'page_size',p_page_size
  );
end;
$function$



drop trigger if exists appointments_capture_audit on public.appointments;
create trigger appointments_capture_audit after insert or update on public.appointments
for each row execute function private.capture_appointment_row_audit();

drop trigger if exists appointment_services_capture_audit on public.appointment_services;
create trigger appointment_services_capture_audit after insert or delete on public.appointment_services
for each row execute function private.capture_appointment_service_audit();

revoke all on function private.write_appointment_audit(uuid,uuid,text,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function private.capture_appointment_row_audit() from public,anon,authenticated;
revoke all on function private.capture_appointment_service_audit() from public,anon,authenticated;
revoke all on function private.validate_appointment_slot(uuid,uuid,uuid,timestamptz,uuid[],uuid,integer) from public,anon,authenticated;

revoke all on function public.create_appointment(uuid,uuid,uuid,timestamptz,uuid[],text,text,text) from public,anon;
revoke all on function public.update_appointment(uuid,uuid,uuid,timestamptz,uuid[],text) from public,anon;
revoke all on function public.reschedule_appointment(uuid,timestamptz) from public,anon;
revoke all on function public.set_appointment_status(uuid,text,text) from public,anon;
revoke all on function public.delete_appointment(uuid,text) from public,anon;
revoke all on function public.list_appointments(uuid,text,text,uuid,uuid,uuid,timestamptz,timestamptz,integer,integer,boolean) from public,anon;

grant execute on function public.create_appointment(uuid,uuid,uuid,timestamptz,uuid[],text,text,text) to authenticated;
grant execute on function public.update_appointment(uuid,uuid,uuid,timestamptz,uuid[],text) to authenticated;
grant execute on function public.reschedule_appointment(uuid,timestamptz) to authenticated;
grant execute on function public.set_appointment_status(uuid,text,text) to authenticated;
grant execute on function public.delete_appointment(uuid,text) to authenticated;
grant execute on function public.list_appointments(uuid,text,text,uuid,uuid,uuid,timestamptz,timestamptz,integer,integer,boolean) to authenticated;

revoke insert,update,delete on public.appointments from authenticated;
revoke insert,update,delete on public.appointment_services from authenticated;

comment on table public.appointment_audit_events is
  'Append-only audit trail for appointment lifecycle and immutable service snapshots.';
comment on function public.list_appointments(uuid,text,text,uuid,uuid,uuid,timestamptz,timestamptz,integer,integer,boolean) is
  'Tenant- and permission-scoped server-side search, filtering and pagination for appointments.';
comment on function public.update_appointment(uuid,uuid,uuid,timestamptz,uuid[],text) is
  'Atomic appointment edit with live entity validation and historical service snapshots.';
