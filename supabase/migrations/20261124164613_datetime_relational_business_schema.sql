-- DateTime relational business schema foundation.
-- Additive migration: preserves businesses, business_memberships, profiles and app_records.
-- No mock/demo records are inserted. All money amounts are integer toman values.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create extension if not exists btree_gist with schema extensions;

alter table public.businesses
  add column if not exists timezone text not null default 'Asia/Tehran';

alter table public.businesses
  add constraint businesses_timezone_not_blank
  check (length(trim(timezone)) between 1 and 80);

-- Customers
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 160),
  phone text not null check (length(trim(phone)) between 5 and 32),
  normalized_phone text generated always as (regexp_replace(phone, '[^0-9+]', '', 'g')) stored,
  email text,
  birth_date date,
  notes text not null default '',
  tags text[] not null default '{}',
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id),
  check (email is null or length(trim(email)) <= 254)
);
create unique index if not exists customers_business_phone_unique
  on public.customers (business_id, normalized_phone) where normalized_phone <> '';

-- Employees are linked to Auth identities only when an employee account is activated.
create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  auth_user_id uuid references auth.users(id) on delete set null,
  full_name text not null check (length(trim(full_name)) between 1 and 160),
  phone text,
  email text,
  is_active boolean not null default true,
  hired_on date,
  terminated_on date,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id),
  check (terminated_on is null or hired_on is null or terminated_on >= hired_on)
);
create unique index if not exists employees_business_auth_user_unique
  on public.employees (business_id, auth_user_id) where auth_user_id is not null;

-- Service catalog.
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  category text not null default '',
  description text not null default '',
  duration_minutes integer not null check (duration_minutes between 1 and 1440),
  price_toman bigint not null check (price_toman >= 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id)
);
create index if not exists services_business_active_sort_idx
  on public.services (business_id, is_active, sort_order);

-- Employee/service expertise and optional custom pricing/duration.
create table if not exists public.employee_services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  service_id uuid not null,
  custom_duration_minutes integer check (custom_duration_minutes between 1 and 1440),
  custom_price_toman bigint check (custom_price_toman >= 0),
  is_active boolean not null default true,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, employee_id, service_id),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete restrict,
  foreign key (business_id, service_id) references public.services(business_id, id) on delete restrict
);

-- Weekly working hours: one row per shift; multiple shifts per weekday are supported.
create table if not exists public.employee_working_hours (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  weekday smallint not null check (weekday between 0 and 6),
  starts_at time not null,
  ends_at time not null,
  break_starts_at time,
  break_ends_at time,
  is_active boolean not null default true,
  valid_from date,
  valid_until date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete cascade,
  check (starts_at < ends_at),
  check ((break_starts_at is null and break_ends_at is null) or
         (break_starts_at is not null and break_ends_at is not null and
          starts_at <= break_starts_at and break_starts_at < break_ends_at and break_ends_at <= ends_at)),
  check (valid_until is null or valid_from is null or valid_until >= valid_from)
);
create index if not exists employee_working_hours_lookup_idx
  on public.employee_working_hours (business_id, employee_id, weekday, is_active);

-- Dated exceptions can add/remove availability for a particular day.
create table if not exists public.employee_schedule_exceptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  work_date date not null,
  is_available boolean not null,
  starts_at time,
  ends_at time,
  reason text not null default '',
  created_at timestamptz not null default now(),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete cascade,
  check ((is_available = false and starts_at is null and ends_at is null) or
         (is_available = true and starts_at is not null and ends_at is not null and starts_at < ends_at))
);
create index if not exists employee_schedule_exceptions_lookup_idx
  on public.employee_schedule_exceptions (business_id, employee_id, work_date);

-- Leave/absence requests. Approved periods cannot overlap for the same employee.
create table if not exists public.employee_leaves (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  leave_type text not null check (leave_type in ('hourly','daily','multi_day','emergency','other')),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  description text not null default '',
  requested_by uuid not null references auth.users(id) default auth.uid(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete restrict,
  check (starts_at < ends_at),
  check ((status = 'pending' and reviewed_at is null) or status <> 'pending')
);
alter table public.employee_leaves
  add constraint employee_leaves_approved_no_overlap
  exclude using gist (
    business_id with =,
    employee_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status = 'approved');
create index if not exists employee_leaves_employee_period_idx
  on public.employee_leaves (business_id, employee_id, starts_at, ends_at);

-- Appointments. The exclusion constraint is the final concurrency guard:
-- two simultaneous requests cannot reserve overlapping time for one employee.
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  reference text not null,
  customer_id uuid not null,
  employee_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending','confirmed','completed','cancelled','rejected','no_show')),
  note text not null default '',
  price_toman bigint not null default 0 check (price_toman >= 0),
  discount_toman bigint not null default 0 check (discount_toman >= 0 and discount_toman <= price_toman),
  reschedule_count integer not null default 0 check (reschedule_count >= 0),
  cancel_reason text,
  idempotency_key text,
  created_by uuid not null references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  unique (business_id, id),
  unique (business_id, reference),
  foreign key (business_id, customer_id) references public.customers(business_id, id) on delete restrict,
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete restrict,
  check (starts_at < ends_at),
  check (length(trim(reference)) between 1 and 64),
  check (idempotency_key is null or length(trim(idempotency_key)) between 1 and 180)
);
create unique index if not exists appointments_idempotency_unique
  on public.appointments (business_id, idempotency_key) where idempotency_key is not null;
alter table public.appointments
  add constraint appointments_employee_no_overlap
  exclude using gist (
    business_id with =,
    employee_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status in ('pending','confirmed'));
create index if not exists appointments_business_start_idx
  on public.appointments (business_id, starts_at desc);
create index if not exists appointments_employee_start_idx
  on public.appointments (business_id, employee_id, starts_at);
create index if not exists appointments_customer_start_idx
  on public.appointments (business_id, customer_id, starts_at desc);
create index if not exists appointments_status_start_idx
  on public.appointments (business_id, status, starts_at);

-- Immutable appointment-time service/price snapshots.
create table if not exists public.appointment_services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  appointment_id uuid not null,
  service_id uuid not null,
  title_snapshot text not null,
  duration_minutes integer not null check (duration_minutes between 1 and 1440),
  price_toman bigint not null check (price_toman >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  foreign key (business_id, appointment_id) references public.appointments(business_id, id) on delete cascade,
  foreign key (business_id, service_id) references public.services(business_id, id) on delete restrict,
  unique (business_id, appointment_id, service_id)
);
create index if not exists appointment_services_appointment_idx
  on public.appointment_services (business_id, appointment_id);

-- Payment receipts/refunds tied to real appointments.
create table if not exists public.appointment_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  appointment_id uuid not null,
  customer_id uuid not null,
  amount_toman bigint not null check (amount_toman > 0),
  method text not null check (method in ('cash','pos','bank_transfer','wallet','other')),
  payment_type text not null check (payment_type in ('receipt','refund')),
  description text not null default '',
  reverses_payment_id uuid,
  idempotency_key text,
  created_by uuid not null references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  foreign key (business_id, appointment_id) references public.appointments(business_id, id) on delete restrict,
  foreign key (business_id, customer_id) references public.customers(business_id, id) on delete restrict,
  foreign key (business_id, reverses_payment_id) references public.appointment_payments(business_id, id) on delete restrict,
  unique (business_id, id),
  check ((payment_type = 'receipt' and reverses_payment_id is null) or
         (payment_type = 'refund' and reverses_payment_id is not null))
);
create unique index if not exists appointment_payments_idempotency_unique
  on public.appointment_payments (business_id, idempotency_key) where idempotency_key is not null;
create index if not exists appointment_payments_period_idx
  on public.appointment_payments (business_id, created_at desc);

-- Business expenses and employee pay configuration.
create table if not exists public.business_expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  amount_toman bigint not null check (amount_toman > 0),
  category text not null check (category in ('operating','rent','supplies','utilities','marketing','maintenance','other')),
  description text not null check (length(trim(description)) between 1 and 500),
  source_document_id text not null check (length(trim(source_document_id)) between 1 and 180),
  status text not null default 'posted' check (status in ('posted','pending','reversed')),
  created_by uuid not null references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists business_expenses_period_idx
  on public.business_expenses (business_id, created_at desc, status);

create table if not exists public.employee_pay_profiles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  payment_method text not null check (payment_method in ('commissionOnly','fixedMonthly','fixedPlusCommission','fixedPerService','hybrid')),
  monthly_salary_toman bigint not null default 0 check (monthly_salary_toman >= 0),
  general_rate_bps integer not null default 0 check (general_rate_bps between 0 and 10000),
  commission_basis text not null default 'afterDiscount' check (commission_basis in ('gross','afterDiscount','netReceived')),
  effective_from date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, employee_id),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete restrict
);

create table if not exists public.employee_commission_rules (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  service_id uuid,
  category text,
  rate_bps integer not null default 0 check (rate_bps between 0 and 10000),
  fixed_amount_toman bigint not null default 0 check (fixed_amount_toman >= 0),
  effective_from date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete cascade,
  foreign key (business_id, service_id) references public.services(business_id, id) on delete restrict,
  check (service_id is not null or nullif(trim(category), '') is not null)
);
create index if not exists employee_commission_rules_lookup_idx
  on public.employee_commission_rules (business_id, employee_id, is_active, effective_from desc);

-- Immutable calculated earnings and wallet ledger.
create table if not exists public.employee_finance_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  appointment_id uuid,
  service_id uuid,
  entry_type text not null check (entry_type in ('commission','refund','correction','salary')),
  method_snapshot text not null,
  basis_snapshot text not null,
  gross_amount_toman bigint not null default 0 check (gross_amount_toman >= 0),
  discount_amount_toman bigint not null default 0 check (discount_amount_toman >= 0),
  received_amount_toman bigint not null default 0 check (received_amount_toman >= 0),
  calculation_base_toman bigint not null default 0 check (calculation_base_toman >= 0),
  rate_bps integer not null default 0 check (rate_bps between 0 and 10000),
  fixed_amount_toman bigint not null default 0 check (fixed_amount_toman >= 0),
  commission_amount_toman bigint not null default 0 check (commission_amount_toman >= 0),
  company_share_toman bigint not null default 0 check (company_share_toman >= 0),
  reverses_entry_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) default auth.uid(),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete restrict,
  foreign key (business_id, appointment_id) references public.appointments(business_id, id) on delete restrict,
  foreign key (business_id, service_id) references public.services(business_id, id) on delete restrict,
  foreign key (business_id, reverses_entry_id) references public.employee_finance_entries(business_id, id) on delete restrict,
  unique (business_id, id),
  check (discount_amount_toman <= gross_amount_toman)
);
create index if not exists employee_finance_entries_employee_period_idx
  on public.employee_finance_entries (business_id, employee_id, created_at desc);

create table if not exists public.employee_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_id uuid not null,
  finance_entry_id uuid,
  transaction_type text not null check (transaction_type in
    ('service_commission','salary','salary_payment','advance','bonus','penalty','deduction','refund','adjustment','settlement')),
  amount_toman bigint not null check (amount_toman > 0),
  direction text not null check (direction in ('credit','debit')),
  description text not null default '',
  status text not null default 'posted' check (status in ('pending','posted','reversed')),
  period_start date,
  period_end date,
  created_by uuid not null references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  foreign key (business_id, employee_id) references public.employees(business_id, id) on delete restrict,
  foreign key (business_id, finance_entry_id) references public.employee_finance_entries(business_id, id) on delete restrict,
  check (period_end is null or period_start is null or period_end >= period_start)
);
create index if not exists employee_wallet_transactions_period_idx
  on public.employee_wallet_transactions (business_id, employee_id, created_at desc);

-- Tenant and permission helpers run with a fixed search_path and are not exposed to anon.
create or replace function private.has_business_permission(p_business_id uuid, p_permission text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_memberships m
    where m.business_id = p_business_id
      and m.user_id = (select auth.uid())
      and m.is_active
      and (
        m.role = 'owner'
        or (m.permissions ->> p_permission) = 'true'
      )
  );
$$;

create or replace function private.current_employee_id(p_business_id uuid)
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select e.id
  from public.employees e
  where e.business_id = p_business_id
    and e.auth_user_id = (select auth.uid())
    and e.is_active
  limit 1;
$$;

revoke all on function private.has_business_permission(uuid,text) from public, anon;
revoke all on function private.current_employee_id(uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.has_business_permission(uuid,text) to authenticated;
grant execute on function private.current_employee_id(uuid) to authenticated;

-- Keep updated_at consistent for all mutable business records.
create or replace function private.touch_updated_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at = now(); return new; end; $$;
revoke all on function private.touch_updated_at() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'customers','employees','services','employee_services','employee_working_hours',
    'employee_leaves','appointments','business_expenses','employee_pay_profiles',
    'employee_commission_rules'
  ] loop
    execute format('drop trigger if exists %I_touch_updated_at on public.%I', t, t);
    execute format('create trigger %I_touch_updated_at before update on public.%I for each row execute function private.touch_updated_at()', t, t);
  end loop;
end $$;

-- Prevent direct appointment writes from bypassing leave validation.
create or replace function private.prevent_appointment_during_approved_leave()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status in ('pending','confirmed') and exists (
    select 1 from public.employee_leaves l
    where l.business_id = new.business_id
      and l.employee_id = new.employee_id
      and l.status = 'approved'
      and tstzrange(l.starts_at, l.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
  ) then
    raise exception 'EMPLOYEE_ON_APPROVED_LEAVE' using errcode = '23P01';
  end if;
  return new;
end;
$$;
revoke all on function private.prevent_appointment_during_approved_leave() from public, anon, authenticated;
drop trigger if exists appointments_check_approved_leave on public.appointments;
create trigger appointments_check_approved_leave
before insert or update of employee_id, starts_at, ends_at, status on public.appointments
for each row execute function private.prevent_appointment_during_approved_leave();

-- RLS: all business records are tenant-scoped; personnel access is self-scoped.
alter table public.customers enable row level security;
alter table public.employees enable row level security;
alter table public.services enable row level security;
alter table public.employee_services enable row level security;
alter table public.employee_working_hours enable row level security;
alter table public.employee_schedule_exceptions enable row level security;
alter table public.employee_leaves enable row level security;
alter table public.appointments enable row level security;
alter table public.appointment_services enable row level security;
alter table public.appointment_payments enable row level security;
alter table public.business_expenses enable row level security;
alter table public.employee_pay_profiles enable row level security;
alter table public.employee_commission_rules enable row level security;
alter table public.employee_finance_entries enable row level security;
alter table public.employee_wallet_transactions enable row level security;

grant select, insert, update, delete on
  public.customers, public.employees, public.services, public.employee_services,
  public.employee_working_hours, public.employee_schedule_exceptions,
  public.employee_leaves, public.appointments, public.appointment_services,
  public.appointment_payments, public.business_expenses,
  public.employee_pay_profiles, public.employee_commission_rules,
  public.employee_finance_entries, public.employee_wallet_transactions
to authenticated;

-- Customers: managers with customer permissions; personnel only when linked to their own appointment.
create policy customers_read_scoped on public.customers for select to authenticated
using (
  private.has_business_permission(business_id,'customers.view')
  or exists (
    select 1 from public.appointments a
    where a.business_id = customers.business_id
      and a.customer_id = customers.id
      and a.employee_id = private.current_employee_id(customers.business_id)
  )
);
create policy customers_insert_manage on public.customers for insert to authenticated
with check (private.has_business_permission(business_id,'customers.manage'));
create policy customers_update_manage on public.customers for update to authenticated
using (private.has_business_permission(business_id,'customers.manage'))
with check (private.has_business_permission(business_id,'customers.manage'));
create policy customers_delete_manage on public.customers for delete to authenticated
using (private.has_business_permission(business_id,'customers.manage'));

-- Employees: manager list access, or the authenticated employee's own record.
create policy employees_read_scoped on public.employees for select to authenticated
using (
  private.has_business_permission(business_id,'employees.view_list')
  or auth_user_id = (select auth.uid())
);
create policy employees_manage_all on public.employees for all to authenticated
using (private.has_business_permission(business_id,'employees.manage'))
with check (private.has_business_permission(business_id,'employees.manage'));

create policy services_read_scoped on public.services for select to authenticated
using (
  private.has_business_permission(business_id,'services.view')
  or private.has_business_permission(business_id,'appointments.view_self')
);
create policy services_manage_all on public.services for all to authenticated
using (private.has_business_permission(business_id,'services.manage'))
with check (private.has_business_permission(business_id,'services.manage'));

create policy employee_services_read_scoped on public.employee_services for select to authenticated
using (
  private.has_business_permission(business_id,'employees.services.view')
  or employee_id = private.current_employee_id(business_id)
);
create policy employee_services_manage_all on public.employee_services for all to authenticated
using (private.has_business_permission(business_id,'employees.services.manage'))
with check (private.has_business_permission(business_id,'employees.services.manage'));

create policy employee_working_hours_read_scoped on public.employee_working_hours for select to authenticated
using (
  private.has_business_permission(business_id,'employees.schedule.view')
  or employee_id = private.current_employee_id(business_id)
);
create policy employee_working_hours_manage_all on public.employee_working_hours for all to authenticated
using (private.has_business_permission(business_id,'employees.schedule.manage'))
with check (private.has_business_permission(business_id,'employees.schedule.manage'));

create policy employee_schedule_exceptions_read_scoped on public.employee_schedule_exceptions for select to authenticated
using (
  private.has_business_permission(business_id,'employees.schedule.view')
  or employee_id = private.current_employee_id(business_id)
);
create policy employee_schedule_exceptions_manage_all on public.employee_schedule_exceptions for all to authenticated
using (private.has_business_permission(business_id,'employees.schedule.manage'))
with check (private.has_business_permission(business_id,'employees.schedule.manage'));

create policy employee_leaves_read_scoped on public.employee_leaves for select to authenticated
using (
  private.has_business_permission(business_id,'employees.leave.view')
  or employee_id = private.current_employee_id(business_id)
);
create policy employee_leaves_insert_self_or_manager on public.employee_leaves for insert to authenticated
with check (
  (employee_id = private.current_employee_id(business_id)
    and requested_by = (select auth.uid())
    and private.has_business_permission(business_id,'employees.leave.request'))
  or private.has_business_permission(business_id,'employees.leave.manage')
);
create policy employee_leaves_update_manager on public.employee_leaves for update to authenticated
using (private.has_business_permission(business_id,'employees.leave.manage'))
with check (private.has_business_permission(business_id,'employees.leave.manage'));
create policy employee_leaves_delete_manager on public.employee_leaves for delete to authenticated
using (private.has_business_permission(business_id,'employees.leave.manage'));

-- Appointments: managers can see all; personnel can see only their own.
create policy appointments_read_scoped on public.appointments for select to authenticated
using (
  private.has_business_permission(business_id,'appointments.view_all')
  or (employee_id = private.current_employee_id(business_id)
      and private.has_business_permission(business_id,'appointments.view_self'))
);
-- Mutations are performed through validated RPCs only.
revoke insert, update, delete on public.appointments from authenticated;

create policy appointment_services_read_scoped on public.appointment_services for select to authenticated
using (
  exists (
    select 1 from public.appointments a
    where a.business_id = appointment_services.business_id
      and a.id = appointment_services.appointment_id
  )
);

create policy appointment_payments_read_manager on public.appointment_payments for select to authenticated
using (private.has_business_permission(business_id,'finance.view'));
create policy appointment_payments_manage on public.appointment_payments for all to authenticated
using (private.has_business_permission(business_id,'finance.manage'))
with check (private.has_business_permission(business_id,'finance.manage'));

create policy business_expenses_read on public.business_expenses for select to authenticated
using (private.has_business_permission(business_id,'finance.view'));
create policy business_expenses_manage on public.business_expenses for all to authenticated
using (private.has_business_permission(business_id,'finance.manage'))
with check (private.has_business_permission(business_id,'finance.manage'));

create policy employee_pay_profiles_read on public.employee_pay_profiles for select to authenticated
using (
  private.has_business_permission(business_id,'finance.payroll.view')
  or employee_id = private.current_employee_id(business_id)
);
create policy employee_pay_profiles_manage on public.employee_pay_profiles for all to authenticated
using (private.has_business_permission(business_id,'finance.payroll.manage'))
with check (private.has_business_permission(business_id,'finance.payroll.manage'));

create policy employee_commission_rules_read on public.employee_commission_rules for select to authenticated
using (
  private.has_business_permission(business_id,'finance.payroll.view')
  or employee_id = private.current_employee_id(business_id)
);
create policy employee_commission_rules_manage on public.employee_commission_rules for all to authenticated
using (private.has_business_permission(business_id,'finance.payroll.manage'))
with check (private.has_business_permission(business_id,'finance.payroll.manage'));

create policy employee_finance_entries_read on public.employee_finance_entries for select to authenticated
using (
  private.has_business_permission(business_id,'finance.view')
  or (employee_id = private.current_employee_id(business_id)
      and private.has_business_permission(business_id,'finance.wallet.view_self'))
);
create policy employee_finance_entries_manage on public.employee_finance_entries for all to authenticated
using (private.has_business_permission(business_id,'finance.manage'))
with check (private.has_business_permission(business_id,'finance.manage'));

create policy employee_wallet_transactions_read on public.employee_wallet_transactions for select to authenticated
using (
  private.has_business_permission(business_id,'finance.view')
  or (employee_id = private.current_employee_id(business_id)
      and private.has_business_permission(business_id,'finance.wallet.view_self'))
);
create policy employee_wallet_transactions_manage on public.employee_wallet_transactions for all to authenticated
using (private.has_business_permission(business_id,'finance.manage'))
with check (private.has_business_permission(business_id,'finance.manage'));

-- Atomic booking RPC. Duration/price snapshots are calculated from active services
-- and employee-specific overrides. Exclusion constraint resolves concurrent races.
create or replace function public.create_appointment(
  p_business_id uuid,
  p_customer_id uuid,
  p_employee_id uuid,
  p_starts_at timestamptz,
  p_service_ids uuid[],
  p_reference text,
  p_note text default '',
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appointment_id uuid;
  v_duration integer;
  v_price bigint;
  v_end_at timestamptz;
  v_service_count integer;
  v_business_timezone text;
  v_local_start timestamp;
  v_weekday integer;
  v_local_start_time time;
  v_local_end_time time;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not (
    private.has_business_permission(p_business_id,'appointments.manage')
    or (private.current_employee_id(p_business_id) = p_employee_id
        and private.has_business_permission(p_business_id,'appointments.manage_self'))
  ) then
    raise exception 'APPOINTMENT_CREATE_FORBIDDEN' using errcode = '42501';
  end if;
  if p_service_ids is null or cardinality(p_service_ids) = 0 then
    raise exception 'APPOINTMENT_REQUIRES_SERVICES' using errcode = '22023';
  end if;
  if p_idempotency_key is not null then
    select id into v_appointment_id
    from public.appointments
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if v_appointment_id is not null then return v_appointment_id; end if;
  end if;

  select count(*), coalesce(sum(coalesce(es.custom_duration_minutes,s.duration_minutes)),0),
         coalesce(sum(coalesce(es.custom_price_toman,s.price_toman)),0)
    into v_service_count, v_duration, v_price
  from public.services s
  join public.employee_services es
    on es.business_id = s.business_id and es.service_id = s.id
   and es.employee_id = p_employee_id and es.is_active
  where s.business_id = p_business_id and s.id = any(p_service_ids) and s.is_active;

  if v_service_count <> cardinality(p_service_ids) then
    raise exception 'SERVICE_NOT_AVAILABLE_FOR_EMPLOYEE' using errcode = '22023';
  end if;

  v_end_at := p_starts_at + make_interval(mins => v_duration);

  select timezone into v_business_timezone from public.businesses where id = p_business_id;
  if v_business_timezone is null then
    raise exception 'BUSINESS_NOT_FOUND' using errcode = '23503';
  end if;
  v_local_start := p_starts_at at time zone v_business_timezone;
  v_weekday := extract(dow from v_local_start)::integer;
  v_local_start_time := v_local_start::time;
  v_local_end_time := (v_end_at at time zone v_business_timezone)::time;

  -- A booking must fit completely inside one active weekly shift or a dated override.
  if exists (
    select 1 from public.employee_schedule_exceptions x
    where x.business_id = p_business_id and x.employee_id = p_employee_id
      and x.work_date = v_local_start::date and x.is_available = false
  ) then
    raise exception 'EMPLOYEE_NOT_AVAILABLE_ON_DATE' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.employee_schedule_exceptions x
    where x.business_id = p_business_id and x.employee_id = p_employee_id
      and x.work_date = v_local_start::date and x.is_available = true
  ) then
    if not exists (
      select 1 from public.employee_schedule_exceptions x
      where x.business_id = p_business_id and x.employee_id = p_employee_id
        and x.work_date = v_local_start::date and x.is_available = true
        and x.starts_at <= v_local_start_time and x.ends_at >= v_local_end_time
    ) then
      raise exception 'OUTSIDE_EXCEPTION_WORKING_HOURS' using errcode = '22023';
    end if;
  elsif not exists (
    select 1 from public.employee_working_hours h
    where h.business_id = p_business_id and h.employee_id = p_employee_id
      and h.weekday = v_weekday and h.is_active
      and (h.valid_from is null or h.valid_from <= v_local_start::date)
      and (h.valid_until is null or h.valid_until >= v_local_start::date)
      and h.starts_at <= v_local_start_time and h.ends_at >= v_local_end_time
      and not (
        h.break_starts_at is not null and h.break_ends_at is not null
        and h.break_starts_at < v_local_end_time and h.break_ends_at > v_local_start_time
      )
  ) then
    raise exception 'OUTSIDE_EMPLOYEE_WORKING_HOURS' using errcode = '22023';
  end if;

  insert into public.appointments (
    business_id, reference, customer_id, employee_id, starts_at, ends_at,
    status, note, price_toman, idempotency_key, created_by
  ) values (
    p_business_id, p_reference, p_customer_id, p_employee_id, p_starts_at, v_end_at,
    'pending', coalesce(p_note,''), v_price, p_idempotency_key, auth.uid()
  ) returning id into v_appointment_id;

  insert into public.appointment_services (
    business_id, appointment_id, service_id, title_snapshot, duration_minutes, price_toman, sort_order
  )
  select p_business_id, v_appointment_id, s.id, s.title,
         coalesce(es.custom_duration_minutes,s.duration_minutes),
         coalesce(es.custom_price_toman,s.price_toman),
         array_position(p_service_ids,s.id)
  from public.services s
  join public.employee_services es
    on es.business_id=s.business_id and es.service_id=s.id
   and es.employee_id=p_employee_id and es.is_active
  where s.business_id=p_business_id and s.id=any(p_service_ids) and s.is_active;

  return v_appointment_id;
exception
  when exclusion_violation then
    raise exception 'APPOINTMENT_TIME_CONFLICT' using errcode = '23P01';
end;
$$;

create or replace function public.set_appointment_status(
  p_appointment_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_business_id uuid; v_employee_id uuid;
begin
  if p_status not in ('pending','confirmed','completed','cancelled','rejected','no_show') then
    raise exception 'INVALID_APPOINTMENT_STATUS' using errcode = '22023';
  end if;
  select business_id, employee_id into v_business_id, v_employee_id
  from public.appointments where id = p_appointment_id;
  if v_business_id is null then raise exception 'APPOINTMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (private.current_employee_id(v_business_id) = v_employee_id
        and private.has_business_permission(v_business_id,'appointments.manage_self'))
  ) then raise exception 'APPOINTMENT_UPDATE_FORBIDDEN' using errcode = '42501'; end if;

  update public.appointments
  set status = p_status,
      cancel_reason = case when p_status in ('cancelled','rejected') then p_reason else cancel_reason end,
      cancelled_at = case when p_status in ('cancelled','rejected') then now() else null end
  where id = p_appointment_id;
end;
$$;

create or replace function public.reschedule_appointment(
  p_appointment_id uuid,
  p_new_starts_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_business_id uuid; v_employee_id uuid; v_duration interval;
begin
  select a.business_id,a.employee_id,a.ends_at-a.starts_at
    into v_business_id,v_employee_id,v_duration
  from public.appointments a where a.id=p_appointment_id and a.status in ('pending','confirmed');
  if v_business_id is null then raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (private.current_employee_id(v_business_id)=v_employee_id
        and private.has_business_permission(v_business_id,'appointments.manage_self'))
  ) then raise exception 'APPOINTMENT_UPDATE_FORBIDDEN' using errcode = '42501'; end if;
  update public.appointments
  set starts_at=p_new_starts_at, ends_at=p_new_starts_at+v_duration,
      reschedule_count=reschedule_count+1
  where id=p_appointment_id;
exception
  when exclusion_violation then
    raise exception 'APPOINTMENT_TIME_CONFLICT' using errcode = '23P01';
end;
$$;

revoke all on function public.create_appointment(uuid,uuid,uuid,timestamptz,uuid[],text,text,text) from public, anon;
revoke all on function public.set_appointment_status(uuid,text,text) from public, anon;
revoke all on function public.reschedule_appointment(uuid,timestamptz) from public, anon;
grant execute on function public.create_appointment(uuid,uuid,uuid,timestamptz,uuid[],text,text,text) to authenticated;
grant execute on function public.set_appointment_status(uuid,text,text) to authenticated;
grant execute on function public.reschedule_appointment(uuid,timestamptz) to authenticated;

-- The authenticated client may only read appointments directly; all writes go through RPC.
grant select on public.appointments to authenticated;
grant select on public.appointment_services to authenticated;

comment on table public.appointments is 'Tenant-scoped appointments; overlap protected by GiST exclusion and writes validated through RPC.';
comment on table public.appointment_services is 'Immutable service title, duration and price snapshots captured when an appointment is booked.';
comment on table public.employee_wallet_transactions is 'Append-oriented employee wallet ledger; monetary amounts are integer toman.';
comment on function public.create_appointment(uuid,uuid,uuid,timestamptz,uuid[],text,text,text) is 'Atomically validates employee availability and creates an appointment with service snapshots.';
