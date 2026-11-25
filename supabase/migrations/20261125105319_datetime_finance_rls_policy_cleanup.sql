-- Direct DML on finance tables is revoked; all mutations go through audited RPCs.
-- Keep read access for both viewers and managers without redundant permissive ALL policies.
drop policy if exists appointment_payments_manage on public.appointment_payments;
drop policy if exists business_expenses_manage on public.business_expenses;

drop policy if exists appointment_payments_read_manager on public.appointment_payments;
create policy appointment_payments_read_manager
  on public.appointment_payments
  for select to authenticated
  using (
    private.has_business_permission(business_id,'finance.view')
    or private.has_business_permission(business_id,'finance.manage')
  );

drop policy if exists business_expenses_read on public.business_expenses;
create policy business_expenses_read
  on public.business_expenses
  for select to authenticated
  using (
    private.has_business_permission(business_id,'finance.view')
    or private.has_business_permission(business_id,'finance.manage')
  );

create index if not exists business_finance_documents_voided_by_fk_idx
  on public.business_finance_documents(voided_by)
  where voided_by is not null;
