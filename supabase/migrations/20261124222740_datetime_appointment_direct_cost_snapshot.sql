alter table public.appointment_services
  add column if not exists direct_cost_toman_snapshot bigint not null default 0;

alter table public.appointment_services
  add constraint appointment_services_direct_cost_snapshot_check
  check (direct_cost_toman_snapshot >= 0);

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
  v_old := 'description_snapshot,duration_minutes,price_toman,list_price_toman_snapshot,';
  v_new := 'description_snapshot,direct_cost_toman_snapshot,duration_minutes,price_toman,list_price_toman_snapshot,';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch create appointment snapshot columns'; end if;
  v_old := 'coalesce(s.description,''''),coalesce(es.custom_duration_minutes';
  v_new := 'coalesce(s.description,''''),coalesce(s.direct_cost_toman,0),coalesce(es.custom_duration_minutes';
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch create appointment snapshot values'; end if;
  execute v_updated;

  v_definition := pg_get_functiondef(
    'public.update_appointment(uuid,uuid,uuid,timestamp with time zone,uuid[],text)'::regprocedure
  );
  v_old := 'description_snapshot,duration_minutes,price_toman,list_price_toman_snapshot,';
  v_new := 'description_snapshot,direct_cost_toman_snapshot,duration_minutes,price_toman,list_price_toman_snapshot,';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch update appointment snapshot columns'; end if;
  v_old := 'coalesce(s.description,''''),coalesce(es.custom_duration_minutes';
  v_new := 'coalesce(s.description,''''),coalesce(s.direct_cost_toman,0),coalesce(es.custom_duration_minutes';
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch update appointment snapshot values'; end if;
  execute v_updated;
end;
$$;
