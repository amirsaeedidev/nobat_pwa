do $$
declare
  v_definition text;
  v_updated text;
begin
  v_definition := pg_get_functiondef(
    'private.validate_appointment_slot(uuid,uuid,uuid,timestamptz,uuid[],uuid,integer)'::regprocedure
  );
  if position('BUSINESS_HOLIDAY' in v_definition) = 0 then
    v_updated := replace(
      v_definition,
      '  v_end_time := v_local_end::time;',
      $replace$  v_end_time := v_local_end::time;

  if exists (
    select 1 from public.business_holidays h
    where h.business_id=p_business_id
      and h.holiday_date=v_local_start::date
  ) then
    raise exception 'BUSINESS_HOLIDAY' using errcode='22023';
  end if;$replace$
    );
    if v_updated = v_definition then
      raise exception 'Could not safely add business holiday guard to appointment slot validator';
    end if;
    execute v_updated;
  end if;
end;
$$;
