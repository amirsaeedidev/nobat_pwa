do $$
declare
  v_definition text;
  v_updated text;
  v_old text;
  v_new text;
begin
  v_definition := pg_get_functiondef(
    'public.update_appointment(uuid,uuid,uuid,timestamp with time zone,uuid[],text)'::regprocedure
  );
  v_old := '  v_current_status text;';
  v_new := '  v_current_status text;'||E'\n'||'  v_reschedule_count integer;';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not add update reschedule counter variable'; end if;
  v_old := $old$select a.business_id,a.customer_id,a.employee_id,a.starts_at,a.status
    into v_business_id,v_current_customer_id,v_current_employee_id,v_current_start,v_current_status$old$;
  v_new := $new$select a.business_id,a.customer_id,a.employee_id,a.starts_at,a.status,a.reschedule_count
    into v_business_id,v_current_customer_id,v_current_employee_id,v_current_start,v_current_status,v_reschedule_count$new$;
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not add update reschedule counter select'; end if;
  v_old := $old$  if v_business_id is null or v_current_status not in ('pending','confirmed') then
    raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;$old$;
  v_new := $new$  if v_business_id is null or v_current_status not in ('pending','confirmed') then
    raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;
  if v_current_start is distinct from p_starts_at and coalesce(v_reschedule_count,0)>=1 then
    raise exception 'APPOINTMENT_RESCHEDULE_LIMIT_REACHED' using errcode='22023';
  end if;$new$;
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not add update reschedule limit guard'; end if;
  execute v_updated;

  v_definition := pg_get_functiondef(
    'public.reschedule_appointment(uuid,timestamp with time zone)'::regprocedure
  );
  v_old := '  v_employee_id uuid;';
  v_new := '  v_employee_id uuid;'||E'\n'||'  v_reschedule_count integer;';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not add reschedule counter variable'; end if;
  v_old := $old$select a.business_id,a.customer_id,a.employee_id
    into v_business_id,v_customer_id,v_employee_id$old$;
  v_new := $new$select a.business_id,a.customer_id,a.employee_id,a.reschedule_count
    into v_business_id,v_customer_id,v_employee_id,v_reschedule_count$new$;
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not add reschedule counter select'; end if;
  v_old := $old$  if v_business_id is null then
    raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;$old$;
  v_new := $new$  if v_business_id is null then
    raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode='P0002';
  end if;
  if coalesce(v_reschedule_count,0)>=1 then
    raise exception 'APPOINTMENT_RESCHEDULE_LIMIT_REACHED' using errcode='22023';
  end if;$new$;
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not add reschedule limit guard'; end if;
  execute v_updated;
end;
$$;
