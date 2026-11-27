drop policy if exists business_finance_documents_read on public.business_finance_documents;
create policy business_finance_documents_read on public.business_finance_documents
for select to authenticated
using (
 private.has_business_permission(business_id,'finance.view')
 or private.has_business_permission(business_id,'finance.manage')
);

drop policy if exists business_finance_audit_events_read on public.business_finance_audit_events;
create policy business_finance_audit_events_read on public.business_finance_audit_events
for select to authenticated
using (
 private.has_business_permission(business_id,'finance.view')
 or private.has_business_permission(business_id,'finance.manage')
);
