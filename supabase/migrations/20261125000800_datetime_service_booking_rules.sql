-- Enforce service-level advance booking limits, daily capacity and confirmation mode.
do $$
declare
  v_definition text;
  v_updated text;
  v_old text;
  v_new text;
begin
  v_definition := pg_get_functiondef(
    'public.create_appointment(uuid,uuid,uuid,timestamp with time zone,uuid[],text,text,text)'::regprocedure
  );

  v_old := ' v_local_start:=p_starts_at at time zone v_business_timezone;';
  v_new := $guard$ v_local_start:=p_starts_at at time zone v_business_timezone;
 if exists (
   select 1 from public.services s
   where s.business_id=p_business_id and s.id=any(p_service_ids)
     and v_local_start::date > (now() at time zone v_business_timezone)::date + s.advance_days
 ) then
   raise exception 'SERVICE_ADVANCE_BOOKING_LIMIT' using errcode='22023';
 end if;
 if exists (
   select 1 from public.services s
   where s.business_id=p_business_id and s.id=any(p_service_ids)
     and s.max_per_day is not null
     and (
       select count(*)
       from public.appointment_services aps
       join public.appointments a on a.business_id=aps.business_id and a.id=aps.appointment_id
       where aps.business_id=p_business_id and aps.service_id=s.id
         and (a.starts_at at time zone v_business_timezone)::date=v_local_start::date
         and a.status not in ('cancelled','rejected')
     ) >= s.max_per_day
 ) then
   raise exception 'SERVICE_DAILY_CAPACITY_REACHED' using errcode='22023';
 end if;$guard$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then
    raise exception 'Could not locate local start calculation for service booking limits';
  end if;

  v_old := $old$values(p_business_id,p_reference,p_customer_id,p_employee_id,p_starts_at,v_end_at,'pending',coalesce(p_note,''),v_price,p_idempotency_key,auth.uid())$old$;
  v_new := $status$values(p_business_id,p_reference,p_customer_id,p_employee_id,p_starts_at,v_end_at,
    case when exists (
      select 1 from public.services s
      where s.business_id=p_business_id and s.id=any(p_service_ids) and s.requires_confirmation
    ) then 'pending' else 'confirmed' end,
    coalesce(p_note,''),v_price,p_idempotency_key,auth.uid())$status$;
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then
    raise exception 'Could not locate appointment insert status expression';
  end if;
  execute v_updated;
end;
$$;
