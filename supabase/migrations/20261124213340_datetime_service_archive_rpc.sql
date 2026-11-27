create or replace function public.archive_service(
  p_business_id uuid,
  p_service_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode='28000';
  end if;
  if not private.has_business_permission(p_business_id,'services.manage') then
    raise exception 'SERVICES_MANAGE_FORBIDDEN' using errcode='42501';
  end if;
  update public.services
  set is_active=false,archived_at=now(),archived_by=auth.uid()
  where business_id=p_business_id and id=p_service_id;
  if not found then raise exception 'SERVICE_NOT_FOUND_OR_FORBIDDEN' using errcode='42501'; end if;
end;
$$;
revoke all on function public.archive_service(uuid,uuid) from public,anon;
grant execute on function public.archive_service(uuid,uuid) to authenticated;
