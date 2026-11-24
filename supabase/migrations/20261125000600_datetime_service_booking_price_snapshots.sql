-- Service managers may maintain the staff-service relation as part of the service catalog.
drop policy if exists employee_services_manage_all on public.employee_services;
create policy employee_services_manage_all on public.employee_services
for all to authenticated
using (
  private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'services.manage')
)
with check (
  private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'services.manage')
);

drop policy if exists employee_services_read_scoped on public.employee_services;
create policy employee_services_read_scoped on public.employee_services
for select to authenticated
using (
  private.has_business_permission(business_id,'employees.services.view')
  or private.has_business_permission(business_id,'services.view')
  or employee_id=private.current_employee_id(business_id)
);

-- The booking RPC remains the final authority for the effective employee-specific
-- duration and date-valid discount price; appointment_services stores immutable snapshots.
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

  v_old := 'coalesce(es.custom_duration_minutes,s.duration_minutes)';
  v_new := 'coalesce(es.custom_duration_minutes,s.duration_minutes+s.prep_minutes+s.buffer_minutes)';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated = v_definition then
    raise exception 'Could not locate appointment duration expressions for service snapshot update';
  end if;
  v_definition := v_updated;

  v_old := 'coalesce(es.custom_price_toman,s.price_toman)';
  v_new := $price$coalesce(es.custom_price_toman,
    case when s.discount_price_toman is not null
      and (p_starts_at at time zone coalesce((select b.timezone from public.businesses b where b.id=p_business_id),'UTC'))::date
        between coalesce(s.discount_starts_on,'-infinity'::date)
            and coalesce(s.discount_ends_on,'infinity'::date)
      then s.discount_price_toman else s.price_toman end)$price$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated = v_definition then
    raise exception 'Could not locate appointment price expressions for discount snapshot update';
  end if;
  execute v_updated;
end;
$$;
