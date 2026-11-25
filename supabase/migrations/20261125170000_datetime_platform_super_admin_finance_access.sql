-- Platform-level administrator authorization for DateTime.
-- This user is intentionally granted global finance access through the
-- database permission helper; no client-side role bypass is used.

create table if not exists private.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'super_admin' check (role = 'super_admin'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

revoke all on table private.platform_admins from public, anon, authenticated;

-- The platform-admin membership is provisioned per Supabase environment;
-- do not commit a user identifier or email into the repository.

create or replace function private.has_business_permission(
  p_business_id uuid,
  p_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from private.platform_admins a
      where a.user_id = (select auth.uid())
        and a.is_active
    )
    or exists (
      select 1
      from public.business_memberships m
      where m.business_id = p_business_id
        and m.user_id = (select auth.uid())
        and m.is_active
        and (
          m.role = 'owner'
          or (m.permissions ->> p_permission) = 'true'
        )
    );
$function$;

revoke all on function private.has_business_permission(uuid, text) from public;
grant execute on function private.has_business_permission(uuid, text) to authenticated;
