do $$
declare
  v_definition text;
  v_updated text;
  v_insert text;
begin
  v_definition := pg_get_functiondef(
    'private.validate_appointment_slot(uuid,uuid,uuid,timestamptz,uuid[],uuid,integer)'::regprocedure
  );
  if position('BUSINESS_WEEKLY_HOLIDAY' in v_definition) = 0 then
    v_insert := $fragment$
  if exists (
    select 1
    from public.app_records r
    where r.business_id=p_business_id
      and r.entity_type='settings'
      and r.record_id='business_settings'
      and jsonb_typeof(r.payload->'holidays')='array'
      and exists (
        select 1
        from jsonb_array_elements_text(r.payload->'holidays') h(value)
        where h.value ~ '^[0-6]$'
          and h.value::integer=((v_weekday+1)%7)
      )
  ) then
    raise exception 'BUSINESS_WEEKLY_HOLIDAY' using errcode='22023';
  end if;
$fragment$;
    v_updated := replace(
      v_definition,
      '  v_end_time := v_local_end::time;',
      '  v_end_time := v_local_end::time;' || E'\n\n' || v_insert
    );
    if v_updated = v_definition then
      raise exception 'Could not safely add weekly holiday guard to appointment slot validator';
    end if;
    execute v_updated;
  end if;
end;
$$;
