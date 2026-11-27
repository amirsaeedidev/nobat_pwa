-- Tighten personnel self-scope and schedule integrity after initial relational foundation.

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
    and exists (
      select 1 from public.business_memberships m
      where m.business_id = e.business_id
        and m.user_id = (select auth.uid())
        and m.is_active
    )
  limit 1;
$$;

drop policy if exists employees_read_scoped on public.employees;
create policy employees_read_scoped on public.employees
for select to authenticated
using (
  private.has_business_permission(business_id,'employees.view_list')
  or (auth_user_id = (select auth.uid())
      and exists (
        select 1 from public.business_memberships m
        where m.business_id = employees.business_id
          and m.user_id = (select auth.uid())
          and m.is_active
      ))
);

drop policy if exists employee_pay_profiles_read on public.employee_pay_profiles;
create policy employee_pay_profiles_read on public.employee_pay_profiles
for select to authenticated
using (
  private.has_business_permission(business_id,'finance.payroll.view')
  or (employee_id = private.current_employee_id(business_id)
      and private.has_business_permission(business_id,'finance.wallet.view_self'))
);

drop policy if exists employee_commission_rules_read on public.employee_commission_rules;
create policy employee_commission_rules_read on public.employee_commission_rules
for select to authenticated
using (
  private.has_business_permission(business_id,'finance.payroll.view')
  or (employee_id = private.current_employee_id(business_id)
      and private.has_business_permission(business_id,'finance.wallet.view_self'))
);

-- Prevent overlapping weekly shifts and overlapping date-specific availability windows.
alter table public.employee_working_hours
  add constraint employee_working_hours_no_overlap
  exclude using gist (
    business_id with =,
    employee_id with =,
    weekday with =,
    int4range(
      extract(hour from starts_at)::integer * 60 + extract(minute from starts_at)::integer,
      extract(hour from ends_at)::integer * 60 + extract(minute from ends_at)::integer,
      '[)'
    ) with &&
  ) where (is_active);

alter table public.employee_schedule_exceptions
  add constraint employee_schedule_exceptions_no_overlap
  exclude using gist (
    business_id with =,
    employee_id with =,
    work_date with =,
    int4range(
      extract(hour from starts_at)::integer * 60 + extract(minute from starts_at)::integer,
      extract(hour from ends_at)::integer * 60 + extract(minute from ends_at)::integer,
      '[)'
    ) with &&
  ) where (is_available);

-- Re-scheduling must pass the same weekly/exception schedule checks as initial booking.
create or replace function public.reschedule_appointment(
  p_appointment_id uuid,
  p_new_starts_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_employee_id uuid;
  v_duration interval;
  v_timezone text;
  v_local_start timestamp;
  v_start_time time;
  v_end_time time;
  v_weekday integer;
begin
  select a.business_id, a.employee_id, a.ends_at - a.starts_at
    into v_business_id, v_employee_id, v_duration
  from public.appointments a
  where a.id = p_appointment_id and a.status in ('pending','confirmed');

  if v_business_id is null then
    raise exception 'ACTIVE_APPOINTMENT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (private.current_employee_id(v_business_id) = v_employee_id
        and private.has_business_permission(v_business_id,'appointments.manage_self'))
  ) then
    raise exception 'APPOINTMENT_UPDATE_FORBIDDEN' using errcode = '42501';
  end if;

  select b.timezone into v_timezone from public.businesses b where b.id = v_business_id;
  v_local_start := p_new_starts_at at time zone v_timezone;
  v_start_time := v_local_start::time;
  v_end_time := ((p_new_starts_at + v_duration) at time zone v_timezone)::time;
  v_weekday := extract(dow from v_local_start)::integer;

  if exists (
    select 1 from public.employee_schedule_exceptions x
    where x.business_id = v_business_id and x.employee_id = v_employee_id
      and x.work_date = v_local_start::date and x.is_available = false
  ) then
    raise exception 'EMPLOYEE_NOT_AVAILABLE_ON_DATE' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.employee_schedule_exceptions x
    where x.business_id = v_business_id and x.employee_id = v_employee_id
      and x.work_date = v_local_start::date and x.is_available = true
  ) then
    if not exists (
      select 1 from public.employee_schedule_exceptions x
      where x.business_id = v_business_id and x.employee_id = v_employee_id
        and x.work_date = v_local_start::date and x.is_available = true
        and x.starts_at <= v_start_time and x.ends_at >= v_end_time
    ) then
      raise exception 'OUTSIDE_EXCEPTION_WORKING_HOURS' using errcode = '22023';
    end if;
  elsif not exists (
    select 1 from public.employee_working_hours h
    where h.business_id = v_business_id and h.employee_id = v_employee_id
      and h.weekday = v_weekday and h.is_active
      and (h.valid_from is null or h.valid_from <= v_local_start::date)
      and (h.valid_until is null or h.valid_until >= v_local_start::date)
      and h.starts_at <= v_start_time and h.ends_at >= v_end_time
      and not (
        h.break_starts_at is not null and h.break_ends_at is not null
        and h.break_starts_at < v_end_time and h.break_ends_at > v_start_time
      )
  ) then
    raise exception 'OUTSIDE_EMPLOYEE_WORKING_HOURS' using errcode = '22023';
  end if;

  update public.appointments
  set starts_at = p_new_starts_at,
      ends_at = p_new_starts_at + v_duration,
      reschedule_count = reschedule_count + 1
  where id = p_appointment_id;
exception
  when exclusion_violation then
    raise exception 'APPOINTMENT_TIME_CONFLICT' using errcode = '23P01';
end;
$$;

revoke all on function public.reschedule_appointment(uuid,timestamptz) from public, anon;
grant execute on function public.reschedule_appointment(uuid,timestamptz) to authenticated;

-- Wallet and calculated earnings are ledgers: corrections are new entries, not row rewrites.
revoke update, delete on public.employee_finance_entries from authenticated;
revoke update, delete on public.employee_wallet_transactions from authenticated;
