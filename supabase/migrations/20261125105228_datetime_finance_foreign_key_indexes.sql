-- Cover finance foreign keys to keep tenant-linked reads and FK checks efficient.
create index if not exists appointment_payments_business_appointment_fk_idx
  on public.appointment_payments(business_id,appointment_id);
create index if not exists appointment_payments_business_customer_fk_idx
  on public.appointment_payments(business_id,customer_id);
create index if not exists appointment_payments_business_reversal_fk_idx
  on public.appointment_payments(business_id,reverses_payment_id)
  where reverses_payment_id is not null;
create index if not exists appointment_payments_created_by_fk_idx
  on public.appointment_payments(created_by);

create index if not exists business_expenses_business_appointment_fk_idx
  on public.business_expenses(business_id,related_appointment_id)
  where related_appointment_id is not null;
create index if not exists business_expenses_business_customer_fk_idx
  on public.business_expenses(business_id,related_customer_id)
  where related_customer_id is not null;
create index if not exists business_expenses_created_by_fk_idx
  on public.business_expenses(created_by);
create index if not exists business_expenses_reversed_by_fk_idx
  on public.business_expenses(reversed_by)
  where reversed_by is not null;

create index if not exists business_finance_documents_business_payment_fk_idx
  on public.business_finance_documents(business_id,payment_id)
  where payment_id is not null;
create index if not exists business_finance_documents_created_by_fk_idx
  on public.business_finance_documents(created_by);
create index if not exists business_finance_audit_events_actor_fk_idx
  on public.business_finance_audit_events(actor_id);
