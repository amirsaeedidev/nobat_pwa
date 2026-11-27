-- DateTime multi-tenant data foundation.
-- Client access is authenticated and protected by RLS. Never use service_role
-- or sb_secret keys in Flutter, APKs, Web builds, or committed files.

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  created_by uuid not null references auth.users(id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_memberships (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'custom_limited',
  permissions jsonb not null default '{}'::jsonb check (jsonb_typeof(permissions) = 'object'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

create table if not exists public.app_records (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entity_type text not null check (entity_type in (
    'appointments', 'customers', 'employees', 'services', 'finance',
    'employee_wallets', 'reports', 'settings', 'activity_logs',
    'payroll', 'leave_requests', 'employee_services', 'roles'
  )),
  record_id text not null check (length(trim(record_id)) between 1 and 180),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  created_by uuid not null references auth.users(id) default auth.uid(),
  updated_by uuid not null references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, entity_type, record_id)
);

create index if not exists app_records_business_entity_updated_idx
  on public.app_records (business_id, entity_type, updated_at desc);
create index if not exists app_records_payload_gin_idx
  on public.app_records using gin (payload);

alter table public.businesses enable row level security;
alter table public.business_memberships enable row level security;
alter table public.app_records enable row level security;

grant select, insert, update, delete on public.businesses to authenticated;
grant select, insert on public.business_memberships to authenticated;
grant select, insert, update, delete on public.app_records to authenticated;

drop policy if exists businesses_read_member_or_creator on public.businesses;
create policy businesses_read_member_or_creator
  on public.businesses for select to authenticated
  using (
    created_by = (select auth.uid())
    or exists (
      select 1 from public.business_memberships m
      where m.business_id = businesses.id
        and m.user_id = (select auth.uid())
        and m.is_active
    )
  );

drop policy if exists businesses_create_self on public.businesses;
create policy businesses_create_self
  on public.businesses for insert to authenticated
  with check (created_by = (select auth.uid()));

drop policy if exists businesses_update_owner on public.businesses;
create policy businesses_update_owner
  on public.businesses for update to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

drop policy if exists businesses_delete_owner on public.businesses;
create policy businesses_delete_owner
  on public.businesses for delete to authenticated
  using (created_by = (select auth.uid()));

drop policy if exists memberships_read_self on public.business_memberships;
create policy memberships_read_self
  on public.business_memberships for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists memberships_create_owner_self on public.business_memberships;
create policy memberships_create_owner_self
  on public.business_memberships for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and role = 'owner'
    and exists (
      select 1 from public.businesses b
      where b.id = business_memberships.business_id
        and b.created_by = (select auth.uid())
    )
  );

drop policy if exists app_records_read_by_permission on public.app_records;
create policy app_records_read_by_permission
  on public.app_records for select to authenticated
  using (
    exists (
      select 1
      from public.business_memberships m
      where m.business_id = app_records.business_id
        and m.user_id = (select auth.uid())
        and m.is_active
        and (
          m.role = 'owner'
          or coalesce(
            (m.permissions ->>
              case app_records.entity_type
                when 'appointments' then 'appointments.view'
                when 'customers' then 'customers.view'
                when 'employees' then 'employees.view_list'
                when 'services' then 'services.view'
                when 'finance' then 'finance.view'
                when 'employee_wallets' then 'finance.employee_wallet.view'
                when 'reports' then 'reports.view'
                when 'settings' then 'settings.view'
                when 'activity_logs' then 'activity.view'
                when 'payroll' then 'finance.payroll.view'
                when 'leave_requests' then 'employees.leave.view'
                when 'employee_services' then 'employees.services.view'
                when 'roles' then 'settings.roles.view'
                else 'records.read'
              end
            ) = 'true',
            false
          )
        )
    )
  );

drop policy if exists app_records_insert_by_permission on public.app_records;
create policy app_records_insert_by_permission
  on public.app_records for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and updated_by = (select auth.uid())
    and exists (
      select 1
      from public.business_memberships m
      where m.business_id = app_records.business_id
        and m.user_id = (select auth.uid())
        and m.is_active
        and (
          m.role = 'owner'
          or coalesce(
            (m.permissions ->>
              case app_records.entity_type
                when 'appointments' then 'appointments.manage'
                when 'customers' then 'customers.manage'
                when 'employees' then 'employees.manage'
                when 'services' then 'services.manage'
                when 'finance' then 'finance.manage'
                when 'employee_wallets' then 'finance.employee_wallet.manage'
                when 'settings' then 'settings.manage'
                when 'activity_logs' then 'activity.manage'
                when 'payroll' then 'finance.payroll.manage'
                when 'leave_requests' then 'employees.leave.manage'
                when 'employee_services' then 'employees.services.manage'
                when 'roles' then 'settings.roles.manage'
                else 'records.write'
              end
            ) = 'true',
            false
          )
        )
    )
  );

drop policy if exists app_records_update_by_permission on public.app_records;
create policy app_records_update_by_permission
  on public.app_records for update to authenticated
  using (
    exists (
      select 1
      from public.business_memberships m
      where m.business_id = app_records.business_id
        and m.user_id = (select auth.uid())
        and m.is_active
        and (
          m.role = 'owner'
          or coalesce(
            (m.permissions ->>
              case app_records.entity_type
                when 'appointments' then 'appointments.manage'
                when 'customers' then 'customers.manage'
                when 'employees' then 'employees.manage'
                when 'services' then 'services.manage'
                when 'finance' then 'finance.manage'
                when 'employee_wallets' then 'finance.employee_wallet.manage'
                when 'settings' then 'settings.manage'
                when 'activity_logs' then 'activity.manage'
                when 'payroll' then 'finance.payroll.manage'
                when 'leave_requests' then 'employees.leave.manage'
                when 'employee_services' then 'employees.services.manage'
                when 'roles' then 'settings.roles.manage'
                else 'records.write'
              end
            ) = 'true',
            false
          )
        )
    )
  )
  with check (
    updated_by = (select auth.uid())
    and exists (
      select 1
      from public.business_memberships m
      where m.business_id = app_records.business_id
        and m.user_id = (select auth.uid())
        and m.is_active
        and (
          m.role = 'owner'
          or coalesce(
            (m.permissions ->>
              case app_records.entity_type
                when 'appointments' then 'appointments.manage'
                when 'customers' then 'customers.manage'
                when 'employees' then 'employees.manage'
                when 'services' then 'services.manage'
                when 'finance' then 'finance.manage'
                when 'employee_wallets' then 'finance.employee_wallet.manage'
                when 'settings' then 'settings.manage'
                when 'activity_logs' then 'activity.manage'
                when 'payroll' then 'finance.payroll.manage'
                when 'leave_requests' then 'employees.leave.manage'
                when 'employee_services' then 'employees.services.manage'
                when 'roles' then 'settings.roles.manage'
                else 'records.write'
              end
            ) = 'true',
            false
          )
        )
    )
  );

drop policy if exists app_records_delete_by_permission on public.app_records;
create policy app_records_delete_by_permission
  on public.app_records for delete to authenticated
  using (
    exists (
      select 1
      from public.business_memberships m
      where m.business_id = app_records.business_id
        and m.user_id = (select auth.uid())
        and m.is_active
        and (
          m.role = 'owner'
          or coalesce(
            (m.permissions ->>
              case app_records.entity_type
                when 'appointments' then 'appointments.manage'
                when 'customers' then 'customers.manage'
                when 'employees' then 'employees.manage'
                when 'services' then 'services.manage'
                when 'finance' then 'finance.manage'
                when 'employee_wallets' then 'finance.employee_wallet.manage'
                when 'settings' then 'settings.manage'
                when 'activity_logs' then 'activity.manage'
                when 'payroll' then 'finance.payroll.manage'
                when 'leave_requests' then 'employees.leave.manage'
                when 'employee_services' then 'employees.services.manage'
                when 'roles' then 'settings.roles.manage'
                else 'records.write'
              end
            ) = 'true',
            false
          )
        )
    )
  );

-- Keep updated_at authoritative even when writes come from a direct API client.
create or replace function public.set_app_record_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists app_records_set_updated_at on public.app_records;
create trigger app_records_set_updated_at
before update on public.app_records
for each row execute function public.set_app_record_updated_at();

-- Supporting indexes for tenant lookups and foreign-key maintenance.
create index if not exists businesses_created_by_idx on public.businesses (created_by);
create index if not exists business_memberships_user_id_idx on public.business_memberships (user_id);
create index if not exists app_records_created_by_idx on public.app_records (created_by);
create index if not exists app_records_updated_by_idx on public.app_records (updated_by);


-- Authentication profile foundation (migration 20261123203907_auth_profile_foundation.sql).
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (
    display_name is null or char_length(btrim(display_name)) between 1 and 120
  )
);
alter table public.profiles enable row level security;
grant select, insert, update on public.profiles to authenticated;
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using ((select auth.uid()) = id);
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create or replace function private.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (new.id, nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '')), ''), nullif(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_auth_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users for each row execute function private.handle_new_auth_user();
create or replace function private.set_profile_updated_at()
returns trigger language plpgsql set search_path = '' as $$ begin new.updated_at = now(); return new; end; $$;
revoke all on function private.set_profile_updated_at() from public, anon, authenticated;
drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function private.set_profile_updated_at();
