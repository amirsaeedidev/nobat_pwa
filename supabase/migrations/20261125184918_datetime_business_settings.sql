-- Commercial settings are tenant-scoped and never stored in device preferences.
create table if not exists public.business_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb
    check (jsonb_typeof(settings) = 'object'),
  booking_form jsonb not null default '{"theme_id":"pastel_pink"}'::jsonb
    check (jsonb_typeof(booking_form) = 'object'),
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.business_settings enable row level security;

drop policy if exists business_settings_read on public.business_settings;
create policy business_settings_read
  on public.business_settings for select to authenticated
  using (
    private.has_business_permission(business_id, 'settings.view')
    or private.has_business_permission(business_id, 'settings.manage')
  );

drop policy if exists business_settings_insert on public.business_settings;
create policy business_settings_insert
  on public.business_settings for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and updated_by = (select auth.uid())
    and private.has_business_permission(business_id, 'settings.manage')
  );

drop policy if exists business_settings_update on public.business_settings;
create policy business_settings_update
  on public.business_settings for update to authenticated
  using (private.has_business_permission(business_id, 'settings.manage'))
  with check (
    updated_by = (select auth.uid())
    and private.has_business_permission(business_id, 'settings.manage')
  );

-- New public-schema tables require explicit Data API grants on current Supabase projects.
grant select, insert, update on public.business_settings to authenticated;

-- One transaction updates the canonical business name and its commercial settings.
create or replace function public.save_business_settings(
  p_business_id uuid,
  p_name text,
  p_settings jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if p_business_id is null
     or p_name is null
     or length(btrim(p_name)) not between 1 and 160
     or p_settings is null
     or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'Invalid business settings payload';
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
    p_business_id, p_settings, (select auth.uid()), (select auth.uid()), now(), now()
  )
  on conflict (business_id) do update
    set settings = excluded.settings,
        updated_by = (select auth.uid()),
        updated_at = now();
end;
$function$;

-- The public booking form has its own shared appearance/configuration payload.
create or replace function public.save_business_booking_form(
  p_business_id uuid,
  p_booking_form jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if p_business_id is null
     or p_booking_form is null
     or jsonb_typeof(p_booking_form) <> 'object' then
    raise exception 'Invalid booking form settings payload';
  end if;

  insert into public.business_settings (
    business_id, settings, booking_form, created_by, updated_by, created_at, updated_at
  ) values (
    p_business_id, '{}'::jsonb, p_booking_form,
    (select auth.uid()), (select auth.uid()), now(), now()
  )
  on conflict (business_id) do update
    set booking_form = excluded.booking_form,
        updated_by = (select auth.uid()),
        updated_at = now();
end;
$function$;

revoke all on function public.save_business_settings(uuid, text, jsonb) from public, anon;
revoke all on function public.save_business_booking_form(uuid, jsonb) from public, anon;
grant execute on function public.save_business_settings(uuid, text, jsonb) to authenticated;
grant execute on function public.save_business_booking_form(uuid, jsonb) to authenticated;
