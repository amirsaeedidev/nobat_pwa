create or replace function public.save_service_catalog_item(
  p_business_id uuid,
  p_service_id uuid,
  p_service jsonb,
  p_employee_configs jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_service_id uuid;
  v_category_id uuid;
  v_category_name text;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode='28000';
  end if;
  if not private.has_business_permission(p_business_id,'services.manage') then
    raise exception 'SERVICES_MANAGE_FORBIDDEN' using errcode='42501';
  end if;
  if jsonb_typeof(p_employee_configs) <> 'array' then
    raise exception 'INVALID_EMPLOYEE_SERVICE_CONFIGS' using errcode='22023';
  end if;

  v_category_name := nullif(trim(coalesce(p_service->>'category','')), '');
  if v_category_name is null then
    raise exception 'SERVICE_CATEGORY_REQUIRED' using errcode='22023';
  end if;

  insert into public.service_categories(business_id,name)
  values(p_business_id,v_category_name)
  on conflict(business_id,name) do update set is_active=true
  returning id into v_category_id;

  if p_service_id is null then
    insert into public.services(
      business_id,category_id,title,category,description,duration_minutes,
      price_toman,is_active,sort_order,direct_cost_toman,image_url,
      discount_price_toman,discount_starts_on,discount_ends_on,
      prep_minutes,buffer_minutes,max_per_day,advance_days,requires_confirmation
    ) values (
      p_business_id,v_category_id,trim(p_service->>'title'),v_category_name,
      coalesce(p_service->>'description',''),(p_service->>'duration_minutes')::integer,
      (p_service->>'price_toman')::bigint,coalesce((p_service->>'is_active')::boolean,true),
      coalesce((p_service->>'sort_order')::integer,0),
      nullif(p_service->>'direct_cost_toman','')::bigint,
      nullif(p_service->>'image_url',''),
      nullif(p_service->>'discount_price_toman','')::bigint,
      nullif(p_service->>'discount_starts_on','')::date,
      nullif(p_service->>'discount_ends_on','')::date,
      coalesce((p_service->>'prep_minutes')::integer,0),
      coalesce((p_service->>'buffer_minutes')::integer,0),
      nullif(p_service->>'max_per_day','')::integer,
      coalesce((p_service->>'advance_days')::integer,30),
      coalesce((p_service->>'requires_confirmation')::boolean,false)
    ) returning id into v_service_id;
  else
    update public.services set
      category_id=v_category_id,
      category=v_category_name,
      title=trim(p_service->>'title'),
      description=coalesce(p_service->>'description',''),
      duration_minutes=(p_service->>'duration_minutes')::integer,
      price_toman=(p_service->>'price_toman')::bigint,
      is_active=coalesce((p_service->>'is_active')::boolean,true),
      sort_order=coalesce((p_service->>'sort_order')::integer,0),
      direct_cost_toman=nullif(p_service->>'direct_cost_toman','')::bigint,
      image_url=nullif(p_service->>'image_url',''),
      discount_price_toman=nullif(p_service->>'discount_price_toman','')::bigint,
      discount_starts_on=nullif(p_service->>'discount_starts_on','')::date,
      discount_ends_on=nullif(p_service->>'discount_ends_on','')::date,
      prep_minutes=coalesce((p_service->>'prep_minutes')::integer,0),
      buffer_minutes=coalesce((p_service->>'buffer_minutes')::integer,0),
      max_per_day=nullif(p_service->>'max_per_day','')::integer,
      advance_days=coalesce((p_service->>'advance_days')::integer,30),
      requires_confirmation=coalesce((p_service->>'requires_confirmation')::boolean,false)
    where business_id=p_business_id and id=p_service_id
    returning id into v_service_id;
    if v_service_id is null then
      raise exception 'SERVICE_NOT_FOUND_OR_FORBIDDEN' using errcode='42501';
    end if;
  end if;

  delete from public.employee_services es
  where es.business_id=p_business_id and es.service_id=v_service_id
    and not exists (
      select 1 from jsonb_array_elements(p_employee_configs) cfg
      where (cfg->>'employee_id')::uuid=es.employee_id
    );

  insert into public.employee_services(
    business_id,employee_id,service_id,is_active,
    custom_price_toman,custom_duration_minutes,notes
  )
  select p_business_id,(cfg->>'employee_id')::uuid,v_service_id,
    coalesce((cfg->>'is_active')::boolean,true),
    nullif(cfg->>'custom_price_toman','')::bigint,
    nullif(cfg->>'custom_duration_minutes','')::integer,
    coalesce(cfg->>'notes','')
  from jsonb_array_elements(p_employee_configs) cfg
  on conflict(business_id,employee_id,service_id) do update set
    is_active=excluded.is_active,
    custom_price_toman=excluded.custom_price_toman,
    custom_duration_minutes=excluded.custom_duration_minutes,
    notes=excluded.notes;

  insert into public.employee_service_compensation(
    business_id,employee_id,service_id,commission_rate_bps,fixed_commission_amount_toman
  )
  select p_business_id,(cfg->>'employee_id')::uuid,v_service_id,
    nullif(cfg->>'commission_rate_bps','')::integer,
    nullif(cfg->>'fixed_commission_amount_toman','')::bigint
  from jsonb_array_elements(p_employee_configs) cfg
  on conflict(business_id,employee_id,service_id) do update set
    commission_rate_bps=excluded.commission_rate_bps,
    fixed_commission_amount_toman=excluded.fixed_commission_amount_toman;

  return v_service_id;
end;
$$;

revoke all on function public.save_service_catalog_item(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.save_service_catalog_item(uuid,uuid,jsonb,jsonb) to authenticated;

drop trigger if exists employee_service_compensation_touch_updated_at on public.employee_service_compensation;
create trigger employee_service_compensation_touch_updated_at
before update on public.employee_service_compensation
for each row execute function private.touch_updated_at();
