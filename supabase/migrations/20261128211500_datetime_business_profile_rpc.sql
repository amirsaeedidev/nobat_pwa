-- Keep business identity/contact updates separate from booking rules,
-- schedules, and appearance preferences.
create or replace function public.save_business_profile(
  p_business_id uuid,
  p_name text,
  p_settings jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_profile jsonb;
  v_location jsonb;
begin
  if p_business_id is null
     or p_name is null
     or length(btrim(p_name)) not between 1 and 160
     or p_settings is null
     or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'Invalid business profile payload';
  end if;

  v_profile := coalesce(p_settings->'profile', '{}'::jsonb);
  v_location := coalesce(p_settings->'location', '{}'::jsonb);

  if jsonb_typeof(v_profile) <> 'object'
     or jsonb_typeof(v_location) <> 'object' then
    raise exception 'Invalid business profile sections';
  end if;

  update public.businesses
     set name = btrim(p_name),
         updated_at = now()
   where id = p_business_id;

  if not found then
    raise exception 'Business not found or update is not permitted';
  end if;

  insert into public.business_settings (
    business_id, settings, created_by, updated_by, created_at, updated_at
  ) values (
    p_business_id,
    jsonb_build_object('profile', v_profile, 'location', v_location),
    (select auth.uid()),
    (select auth.uid()),
    now(),
    now()
  )
  on conflict (business_id) do update
    set settings = public.business_settings.settings || excluded.settings,
        updated_by = (select auth.uid()),
        updated_at = now();
end;
$function$;

revoke all on function public.save_business_profile(uuid, text, jsonb) from public, anon;
grant execute on function public.save_business_profile(uuid, text, jsonb) to authenticated;

-- A delegated user with settings.manage may edit the business profile without
-- needing to be the original creator. Other business columns remain unchanged.
drop policy if exists businesses_update_settings_manager on public.businesses;
create policy businesses_update_settings_manager
  on public.businesses for update to authenticated
  using (private.has_business_permission(id, 'settings.manage'))
  with check (private.has_business_permission(id, 'settings.manage'));
