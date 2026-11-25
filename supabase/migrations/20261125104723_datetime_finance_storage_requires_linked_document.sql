drop policy if exists business_finance_documents_storage_read on storage.objects;
create policy business_finance_documents_storage_read on storage.objects
for select to authenticated
using (
  bucket_id='business-finance-documents'
  and (storage.foldername(name))[1] is not null
  and (
    private.has_business_permission(((storage.foldername(name))[1])::uuid,'finance.view')
    or private.has_business_permission(((storage.foldername(name))[1])::uuid,'finance.manage')
  )
  and exists (
    select 1 from public.business_finance_documents d
    where d.business_id=((storage.foldername(name))[1])::uuid
      and d.storage_path=name
      and (d.status='active' or private.has_business_permission(d.business_id,'finance.manage'))
  )
);

drop policy if exists business_finance_documents_storage_insert on storage.objects;
create policy business_finance_documents_storage_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='business-finance-documents'
  and (storage.foldername(name))[1] is not null
  and private.has_business_permission(((storage.foldername(name))[1])::uuid,'finance.manage')
  and exists (
    select 1 from public.business_finance_documents d
    where d.business_id=((storage.foldername(name))[1])::uuid
      and d.storage_path=name
      and d.status='active'
      and d.created_by=(select auth.uid())
  )
);
