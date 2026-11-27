-- Supabase migration: employee attendance event ledger and real performance projection.
create table if not exists public.employee_attendance_records (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  employee_id uuid not null,
  work_date date not null,
  event_type text not null check (event_type in ('check_in','check_out','absence','mission','manual_correction')),
  occurred_at timestamptz not null default now(),
  note text not null default '',
  late_minutes integer not null default 0 check (late_minutes >= 0),
  overtime_minutes integer not null default 0 check (overtime_minutes >= 0),
  early_leave_minutes integer not null default 0 check (early_leave_minutes >= 0),
  worked_minutes integer not null default 0 check (worked_minutes >= 0),
  correction_of_id uuid,
  idempotency_key text,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_attendance_scope_unique unique (business_id,employee_id,id),
  constraint employee_attendance_employee_fk foreign key (business_id,employee_id) references public.employees(business_id,id),
  constraint employee_attendance_creator_fk foreign key (created_by) references auth.users(id),
  constraint employee_attendance_correction_fk foreign key (business_id,employee_id,correction_of_id) references public.employee_attendance_records(business_id,employee_id,id),
  constraint employee_attendance_idempotency_check check (idempotency_key is null or length(btrim(idempotency_key)) between 1 and 180)
);
create unique index if not exists employee_attendance_idempotency_uidx on public.employee_attendance_records(business_id,idempotency_key) where idempotency_key is not null;
create index if not exists employee_attendance_employee_date_idx on public.employee_attendance_records(business_id,employee_id,work_date,occurred_at);
create index if not exists employee_attendance_correction_idx on public.employee_attendance_records(business_id,employee_id,correction_of_id) where correction_of_id is not null;

create table if not exists public.employee_attendance_payroll_policies (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  enabled boolean not null default false,
  late_deduction_per_minute_toman bigint not null default 0 check (late_deduction_per_minute_toman >= 0),
  absence_deduction_per_day_toman bigint not null default 0 check (absence_deduction_per_day_toman >= 0),
  overtime_payment_per_minute_toman bigint not null default 0 check (overtime_payment_per_minute_toman >= 0),
  early_leave_deduction_per_minute_toman bigint not null default 0 check (early_leave_deduction_per_minute_toman >= 0),
  updated_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now()
);

create or replace function private.validate_employee_attendance_event()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_last public.employee_attendance_records%rowtype; v_employee_business uuid;
begin
  select e.business_id into v_employee_business from public.employees e where e.id = new.employee_id for update;
  if v_employee_business is null or v_employee_business <> new.business_id then
    raise exception 'ATTENDANCE_EMPLOYEE_BUSINESS_MISMATCH' using errcode = '23503';
  end if;
  if new.event_type in ('absence','mission','manual_correction') and not private.has_business_permission(new.business_id,'employees.manage') then
    raise exception 'ATTENDANCE_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  if new.event_type in ('check_in','check_out') then
    select * into v_last from public.employee_attendance_records r
     where r.business_id=new.business_id and r.employee_id=new.employee_id and r.work_date=new.work_date
       and r.event_type in ('check_in','check_out')
     order by r.occurred_at desc,r.created_at desc limit 1 for update;
    if new.event_type='check_in' and found and v_last.event_type='check_in' then
      raise exception 'ATTENDANCE_SESSION_ALREADY_OPEN' using errcode='23505';
    end if;
    if new.event_type='check_out' then
      if not found or v_last.event_type<>'check_in' then
        raise exception 'ATTENDANCE_NO_OPEN_SESSION' using errcode='23514';
      end if;
      new.worked_minutes := greatest(0,floor(extract(epoch from (new.occurred_at-v_last.occurred_at))/60)::integer);
    end if;
  end if;
  if new.event_type<>'manual_correction' then
    new.worked_minutes := case when new.event_type='check_out' then new.worked_minutes else 0 end;
  end if;
  return new;
end;
$$;
drop trigger if exists employee_attendance_validate_event on public.employee_attendance_records;
create trigger employee_attendance_validate_event before insert on public.employee_attendance_records for each row execute function private.validate_employee_attendance_event();
drop trigger if exists employee_attendance_touch_updated_at on public.employee_attendance_payroll_policies;
create trigger employee_attendance_touch_updated_at before update on public.employee_attendance_payroll_policies for each row execute function private.touch_updated_at();
drop trigger if exists activity_audit_employee_attendance on public.employee_attendance_records;
create trigger activity_audit_employee_attendance after insert on public.employee_attendance_records for each row execute function public.capture_business_activity_event();
drop trigger if exists activity_audit_employee_attendance_policy on public.employee_attendance_payroll_policies;
create trigger activity_audit_employee_attendance_policy after insert or update on public.employee_attendance_payroll_policies for each row execute function public.capture_business_activity_event();

alter table public.employee_attendance_records enable row level security;
alter table public.employee_attendance_payroll_policies enable row level security;
drop policy if exists employee_attendance_read_scoped on public.employee_attendance_records;
create policy employee_attendance_read_scoped on public.employee_attendance_records for select to authenticated
using (private.has_business_permission(business_id,'employees.view_list') or employee_id=private.current_employee_id(business_id));
drop policy if exists employee_attendance_insert_self_or_manager on public.employee_attendance_records;
create policy employee_attendance_insert_self_or_manager on public.employee_attendance_records for insert to authenticated
with check (created_by=(select auth.uid()) and (private.has_business_permission(business_id,'employees.manage') or (employee_id=private.current_employee_id(business_id) and private.has_business_permission(business_id,'employees.view_profile') and event_type in ('check_in','check_out'))));
drop policy if exists employee_attendance_policy_read on public.employee_attendance_payroll_policies;
create policy employee_attendance_policy_read on public.employee_attendance_payroll_policies for select to authenticated
using (private.has_business_permission(business_id,'employees.manage') or private.has_business_permission(business_id,'finance.payroll.view'));
drop policy if exists employee_attendance_policy_manage on public.employee_attendance_payroll_policies;
create policy employee_attendance_policy_manage on public.employee_attendance_payroll_policies for all to authenticated
using (private.has_business_permission(business_id,'employees.manage') or private.has_business_permission(business_id,'finance.payroll.manage'))
with check (private.has_business_permission(business_id,'employees.manage') or private.has_business_permission(business_id,'finance.payroll.manage'));

grant select,insert on public.employee_attendance_records to authenticated;
grant select,insert,update on public.employee_attendance_payroll_policies to authenticated;

create or replace view public.employee_performance_daily with (security_invoker=true) as
with day_keys as (
 select business_id,employee_id,starts_at::date work_date from public.appointments
 union select business_id,employee_id,work_date from public.employee_attendance_records
 union select business_id,employee_id,starts_at::date from public.employee_leaves
 union select business_id,employee_id,created_at::date from public.employee_wallet_transactions
),
finance_by_appointment as (
 select appointment_id,sum(gross_amount_toman)::bigint gross_amount_toman,sum(received_amount_toman)::bigint received_amount_toman,
 sum(commission_amount_toman)::bigint commission_amount_toman,sum(company_share_toman)::bigint company_share_toman
 from public.employee_finance_entries where appointment_id is not null group by appointment_id
),
appointments_by_day as (
 select a.business_id,a.employee_id,a.starts_at::date work_date,count(*)::integer appointment_count,
 count(*) filter(where a.status='completed')::integer completed_count,
 count(*) filter(where a.status='cancelled')::integer cancelled_count,
 count(*) filter(where a.status='no_show')::integer no_show_count,
 count(distinct a.customer_id) filter(where a.status='completed')::integer unique_customers,
 coalesce(sum(case when a.status='completed' then coalesce(f.gross_amount_toman,a.price_toman) else 0 end),0)::bigint gross_revenue_toman,
 coalesce(sum(case when a.status='completed' then coalesce(f.received_amount_toman,a.price_toman-a.discount_toman) else 0 end),0)::bigint net_revenue_toman,
 coalesce(sum(case when a.status='completed' then coalesce(f.commission_amount_toman,0) else 0 end),0)::bigint commission_toman,
 coalesce(sum(case when a.status='completed' then coalesce(f.company_share_toman,a.price_toman-a.discount_toman) else 0 end),0)::bigint company_share_toman,
 coalesce(sum(case when a.status not in ('cancelled','rejected','no_show') then floor(extract(epoch from (a.ends_at-a.starts_at))/60) else 0 end),0)::integer booked_minutes
 from public.appointments a left join finance_by_appointment f on f.appointment_id=a.id
 group by a.business_id,a.employee_id,a.starts_at::date
),
attendance_by_day as (
 select r.business_id,r.employee_id,r.work_date,
 count(*) filter(where r.event_type in ('check_in','check_out','manual_correction'))::integer attendance_event_count,
 count(*) filter(where r.event_type='absence')::integer absence_count,
 coalesce(sum(r.worked_minutes),0)::integer worked_minutes,coalesce(sum(r.late_minutes),0)::integer late_minutes,
 coalesce(sum(r.overtime_minutes),0)::integer overtime_minutes,coalesce(sum(r.early_leave_minutes),0)::integer early_leave_minutes
 from public.employee_attendance_records r group by r.business_id,r.employee_id,r.work_date
),
leaves_by_day as (
 select l.business_id,l.employee_id,l.starts_at::date work_date,count(*) filter(where l.status='approved')::integer approved_leave_count
 from public.employee_leaves l group by l.business_id,l.employee_id,l.starts_at::date
),
wallet_by_day as (
 select w.business_id,w.employee_id,w.created_at::date work_date,
 coalesce(sum(case when w.transaction_type in ('salary','service_commission') and w.direction='credit' and w.status='posted' then w.amount_toman else 0 end),0)::bigint earned_toman,
 coalesce(sum(case when w.transaction_type='bonus' and w.direction='credit' and w.status='posted' then w.amount_toman else 0 end),0)::bigint bonus_toman,
 coalesce(sum(case when w.transaction_type in ('penalty','deduction') and w.direction='debit' and w.status='posted' then w.amount_toman else 0 end),0)::bigint deduction_toman,
 coalesce(sum(case when w.transaction_type='advance' and w.direction='debit' and w.status='posted' then w.amount_toman else 0 end),0)::bigint advance_toman,
 coalesce(sum(case when w.transaction_type in ('salary_payment','settlement') and w.direction='debit' and w.status='posted' then w.amount_toman else 0 end),0)::bigint salary_paid_toman,
 coalesce(sum(case when w.status='posted' then case when w.direction='credit' then w.amount_toman else -w.amount_toman end else 0 end),0)::bigint wallet_delta_toman
 from public.employee_wallet_transactions w group by w.business_id,w.employee_id,w.created_at::date
)
select d.business_id,d.employee_id,d.work_date,coalesce(a.appointment_count,0) appointment_count,coalesce(a.completed_count,0) completed_count,
coalesce(a.cancelled_count,0) cancelled_count,coalesce(a.no_show_count,0) no_show_count,coalesce(a.unique_customers,0) unique_customers,
coalesce(a.gross_revenue_toman,0) gross_revenue_toman,coalesce(a.net_revenue_toman,0) net_revenue_toman,
coalesce(a.commission_toman,0) commission_toman,coalesce(a.company_share_toman,0) company_share_toman,coalesce(a.booked_minutes,0) booked_minutes,
coalesce(at.attendance_event_count,0)>0 attendance_data_available,coalesce(at.absence_count,0) absence_count,
coalesce(at.worked_minutes,0) worked_minutes,coalesce(at.late_minutes,0) late_minutes,coalesce(at.overtime_minutes,0) overtime_minutes,
coalesce(at.early_leave_minutes,0) early_leave_minutes,coalesce(l.approved_leave_count,0) approved_leave_count,
coalesce(w.earned_toman,0) earned_toman,coalesce(w.bonus_toman,0) bonus_toman,coalesce(w.deduction_toman,0) deduction_toman,
coalesce(w.advance_toman,0) advance_toman,coalesce(w.salary_paid_toman,0) salary_paid_toman,coalesce(w.wallet_delta_toman,0) wallet_delta_toman
from day_keys d left join appointments_by_day a using(business_id,employee_id,work_date)
left join attendance_by_day at using(business_id,employee_id,work_date)
left join leaves_by_day l using(business_id,employee_id,work_date)
left join wallet_by_day w using(business_id,employee_id,work_date);
grant select on public.employee_performance_daily to authenticated;
