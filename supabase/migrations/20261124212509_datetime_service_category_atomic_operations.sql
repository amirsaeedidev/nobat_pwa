create or replace function public.rename_service_category(
  p_business_id uuid,
  p_category_id uuid,
  p_new_name text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode='28000'; end if;
  if not private.has_business_permission(p_business_id,'services.manage') then
    raise exception 'SERVICES_MANAGE_FORBIDDEN' using errcode='42501';
  end if;
  if length(trim(coalesce(p_new_name,''))) not between 1 and 100 then
    raise exception 'INVALID_CATEGORY_NAME' using errcode='22023';
  end if;
  update public.service_categories
  set name=trim(p_new_name)
  where business_id=p_business_id and id=p_category_id;
  if not found then raise exception 'CATEGORY_NOT_FOUND' using errcode='P0002'; end if;
  update public.services
  set category=trim(p_new_name)
  where business_id=p_business_id and category_id=p_category_id;
end;
$$;

create or replace function public.delete_service_category(
  p_business_id uuid,
  p_category_id uuid,
  p_target_category_id uuid default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode='28000'; end if;
  if not private.has_business_permission(p_business_id,'services.manage') then
    raise exception 'SERVICES_MANAGE_FORBIDDEN' using errcode='42501';
  end if;
  select count(*) into v_count from public.services
  where business_id=p_business_id and category_id=p_category_id;
  if v_count>0 then
    if p_target_category_id is null or p_target_category_id=p_category_id then
      raise exception 'CATEGORY_HAS_SERVICES_REQUIRES_TARGET' using errcode='23503';
    end if;
    if not exists(select 1 from public.service_categories
      where business_id=p_business_id and id=p_target_category_id and is_active) then
      raise exception 'TARGET_CATEGORY_NOT_FOUND' using errcode='23503';
    end if;
    update public.services s
    set category_id=p_target_category_id,
        category=c.name
    from public.service_categories c
    where c.business_id=p_business_id and c.id=p_target_category_id
      and s.business_id=p_business_id and s.category_id=p_category_id;
  end if;
  delete from public.service_categories
  where business_id=p_business_id and id=p_category_id;
end;
$$;

revoke all on function public.rename_service_category(uuid,uuid,text) from public,anon;
revoke all on function public.delete_service_category(uuid,uuid,uuid) from public,anon;
grant execute on function public.rename_service_category(uuid,uuid,text) to authenticated;
grant execute on function public.delete_service_category(uuid,uuid,uuid) to authenticated;
