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
case when private.has_business_permission(d.business_id,'finance.view') then coalesce(a.gross_revenue_toman,0) else 0 end gross_revenue_toman,
case when private.has_business_permission(d.business_id,'finance.view') then coalesce(a.net_revenue_toman,0) else 0 end net_revenue_toman,
case when private.has_business_permission(d.business_id,'finance.view')
  or (d.employee_id=private.current_employee_id(d.business_id) and private.has_business_permission(d.business_id,'finance.wallet.view_self'))
  then coalesce(a.commission_toman,0) else 0 end commission_toman,
case when private.has_business_permission(d.business_id,'finance.view') then coalesce(a.company_share_toman,0) else 0 end company_share_toman,
coalesce(a.booked_minutes,0) booked_minutes,
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
