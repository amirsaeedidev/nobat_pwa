-- A disabled staff schedule must block new and rescheduled bookings at the database boundary.
do $$
declare
  v_definition text;
  v_updated text;
begin
  v_definition := pg_get_functiondef(
    'public.create_appointment(uuid,uuid,uuid,timestamptz,uuid[],text,text,text)'::regprocedure
  );
  if position('EMPLOYEE_SCHEDULE_DISABLED' in v_definition) = 0 then
    v_updated := replace(
      v_definition,
      ' if p_service_ids is null',
      $replace$ if not exists (
  select 1 from public.employees e
  where e.business_id = p_business_id
    and e.id = p_employee_id
    and e.is_active
    and e.schedule_enabled
 ) then
  raise exception 'EMPLOYEE_SCHEDULE_DISABLED' using errcode = '22023';
 end if;
 if p_service_ids is null$replace$
    );
    if v_updated = v_definition then
      raise exception 'Could not safely locate create_appointment guard insertion point';
    end if;
    execute v_updated;
  end if;

  v_definition := pg_get_functiondef(
    'public.reschedule_appointment(uuid,timestamptz)'::regprocedure
  );
  if position('EMPLOYEE_SCHEDULE_DISABLED' in v_definition) = 0 then
    v_updated := replace(
      v_definition,
      '  update public.appointments',
      $replace$  if not exists (
    select 1 from public.employees e
    where e.business_id = v_business_id
      and e.id = v_employee_id
      and e.is_active
      and e.schedule_enabled
  ) then
    raise exception 'EMPLOYEE_SCHEDULE_DISABLED' using errcode = '22023';
  end if;

  update public.appointments$replace$
    );
    if v_updated = v_definition then
      raise exception 'Could not safely locate reschedule_appointment guard insertion point';
    end if;
    execute v_updated;
  end if;
end;
$$;
