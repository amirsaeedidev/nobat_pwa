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
);
