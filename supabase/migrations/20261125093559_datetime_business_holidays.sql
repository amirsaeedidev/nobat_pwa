create table if not exists public.business_holidays (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  holiday_date date not null,
  title text not null,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (business_id, holiday_date)
);

create index if not exists business_holidays_business_date_idx
  on public.business_holidays (business_id, holiday_date);

alter table public.business_holidays enable row level security;

drop policy if exists business_holidays_read_scoped on public.business_holidays;
create policy business_holidays_read_scoped
on public.business_holidays for select to authenticated
using (
  private.has_business_permission(business_id, 'employees.schedule.view')
  or private.has_business_permission(business_id, 'employees.schedule.manage')
  or private.has_business_permission(business_id, 'appointments.view_all')
);

drop policy if exists business_holidays_insert_manager on public.business_holidays;
create policy business_holidays_insert_manager
on public.business_holidays for insert to authenticated
with check (private.has_business_permission(business_id, 'employees.schedule.manage'));

drop policy if exists business_holidays_update_manager on public.business_holidays;
create policy business_holidays_update_manager
on public.business_holidays for update to authenticated
using (private.has_business_permission(business_id, 'employees.schedule.manage'))
with check (private.has_business_permission(business_id, 'employees.schedule.manage'));

drop policy if exists business_holidays_delete_manager on public.business_holidays;
create policy business_holidays_delete_manager
on public.business_holidays for delete to authenticated
using (private.has_business_permission(business_id, 'employees.schedule.manage'));

revoke all on public.business_holidays from anon, public;
grant select, insert, update, delete on public.business_holidays to authenticated;
