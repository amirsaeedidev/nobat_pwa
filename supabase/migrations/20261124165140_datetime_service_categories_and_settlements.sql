-- Add normalized service categories and employee settlement requests.
-- Additive migration: keeps the legacy services.category text intact.

create table if not exists public.service_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 100),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id),
  unique (business_id, name)
);

alter table public.services add column if not exists category_id uuid;
alter table public.services add constraint services_category_same_business_fkey
  foreign key (business_id, category_id)
  references public.service_categories(business_id, id) on delete restrict;
create index if not exists services_business_category_idx
  on public.services (business_id, category_id, is_active);
create trigger service_categories_touch_updated_at
before update on public.service_categories
for each row execute function private.touch_updated_at();

alter table public.employees
  add constraint employees_auth_membership_same_business_fkey
  foreign key (business_id, auth_user_id)
  references public.business_memberships(business_id, user_id)
  on delete restrict;

alter table public.employee_wallet_transactions
  add constraint employee_wallet_transactions_business_id_id_key unique (business_id,id);

create table if not exists public.employee_settlements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  period_type text not null check (period_type in ('daily','weekly','monthly','manual')),
  period_start date not null,
  period_end date not null,
  amount_toman bigint not null check (amount_toman > 0),
  status text not null default 'requested' check (status in ('requested','approved','paid','rejected','cancelled')),
  request_note text not null default '',
  review_note text not null default '',
  requested_by uuid not null references auth.users(id) default auth.uid(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  paid_at timestamptz,
  wallet_transaction_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,id),
  foreign key (business_id,employee_id) references public.employees(business_id,id) on delete restrict,
  foreign key (business_id,wallet_transaction_id) references public.employee_wallet_transactions(business_id,id) on delete restrict,
  check (period_start <= period_end),
  check ((status='paid' and paid_at is not null and wallet_transaction_id is not null) or status <> 'paid')
);
create index if not exists employee_settlements_employee_period_idx
  on public.employee_settlements (business_id,employee_id,period_start desc,status);
create trigger employee_settlements_touch_updated_at
before update on public.employee_settlements
for each row execute function private.touch_updated_at();

alter table public.service_categories enable row level security;
alter table public.employee_settlements enable row level security;
grant select,insert,update,delete on public.service_categories to authenticated;
grant select,insert,update on public.employee_settlements to authenticated;
revoke delete on public.employee_settlements from authenticated;

create policy service_categories_read on public.service_categories for select to authenticated
using (private.has_business_permission(business_id,'services.view') or private.has_business_permission(business_id,'appointments.view_self'));
create policy service_categories_manage on public.service_categories for all to authenticated
using (private.has_business_permission(business_id,'services.manage'))
with check (private.has_business_permission(business_id,'services.manage'));

create policy employee_settlements_read on public.employee_settlements for select to authenticated
using (private.has_business_permission(business_id,'finance.view') or
 (employee_id=private.current_employee_id(business_id) and private.has_business_permission(business_id,'finance.wallet.view_self')));
create policy employee_settlements_request on public.employee_settlements for insert to authenticated
with check (
 (employee_id=private.current_employee_id(business_id) and requested_by=(select auth.uid())
  and private.has_business_permission(business_id,'finance.settlement.request'))
 or private.has_business_permission(business_id,'finance.manage'));
create policy employee_settlements_review on public.employee_settlements for update to authenticated
using (private.has_business_permission(business_id,'finance.manage'))
with check (private.has_business_permission(business_id,'finance.manage'));
