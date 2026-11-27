create or replace view public.business_finance_ledger
with (security_invoker=true)
as
  select p.id as entry_id,p.business_id,p.created_at as occurred_at,
    case when p.payment_type='refund' then 'refund' else 'receipt' end as entry_type,
    case when p.payment_type='refund' then -p.amount_toman else p.amount_toman end as signed_amount_toman,
    p.method as payment_method,p.appointment_id,p.customer_id,null::uuid as expense_id,
    p.description,'posted'::text as status
  from public.appointment_payments p
  union all
  select e.id,e.business_id,(e.expense_date::timestamp at time zone 'UTC'),
    'expense'::text,-e.amount_toman,e.payment_method,e.related_appointment_id,
    e.related_customer_id,e.id,e.description,e.status
  from public.business_expenses e
  where e.status='posted'
  union all
  select a.id,a.business_id,a.created_at,'discount'::text,-a.discount_toman,
    null::text,a.id,a.customer_id,null::uuid,'تخفیف نوبت'::text,'posted'::text
  from public.appointments a
  where a.status='completed' and a.discount_toman>0;
grant select on public.business_finance_ledger to authenticated;
