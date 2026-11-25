-- Resolve canonical linked references before idempotency comparison, so retries with a payment_id are stable.
create or replace function private.create_business_finance_document_impl(
 p_business_id uuid,p_document_type text,p_document_number text,p_appointment_id uuid,p_customer_id uuid,
 p_expense_id uuid,p_payment_id uuid,p_amount_toman bigint,p_storage_path text,p_file_name text,
 p_mime_type text,p_file_size_bytes bigint,p_notes text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=''
as $function$
declare
 v_actor uuid:=(select auth.uid()); v_payment public.appointment_payments%rowtype; v_expense public.business_expenses%rowtype;
 v_appointment_id uuid:=p_appointment_id; v_customer_id uuid:=p_customer_id; v_existing public.business_finance_documents%rowtype;
 v_appointment_customer_id uuid; v_id uuid;
begin
 if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage') then raise exception 'FINANCE_MANAGE_FORBIDDEN' using errcode='42501'; end if;
 if p_document_type not in ('receipt','refund','expense_receipt','invoice','discount_note','payment_proof','other') then raise exception 'FINANCE_DOCUMENT_TYPE_INVALID' using errcode='22023'; end if;
 if p_appointment_id is null and p_customer_id is null and p_expense_id is null and p_payment_id is null then raise exception 'FINANCE_DOCUMENT_REQUIRES_SOURCE' using errcode='22023'; end if;
 if p_payment_id is not null then
  select * into v_payment from public.appointment_payments where business_id=p_business_id and id=p_payment_id;
  if not found then raise exception 'FINANCE_PAYMENT_NOT_FOUND' using errcode='23503'; end if;
  if v_appointment_id is not null and v_appointment_id<>v_payment.appointment_id then raise exception 'FINANCE_DOCUMENT_APPOINTMENT_MISMATCH' using errcode='23503'; end if;
  if v_customer_id is not null and v_customer_id<>v_payment.customer_id then raise exception 'FINANCE_DOCUMENT_CUSTOMER_MISMATCH' using errcode='23503'; end if;
  v_appointment_id:=v_payment.appointment_id; v_customer_id:=v_payment.customer_id;
 end if;
 if p_expense_id is not null then
  select * into v_expense from public.business_expenses where business_id=p_business_id and id=p_expense_id;
  if not found then raise exception 'FINANCE_EXPENSE_NOT_FOUND' using errcode='23503'; end if;
  if v_appointment_id is null then v_appointment_id:=v_expense.related_appointment_id; end if;
  if v_customer_id is null then v_customer_id:=v_expense.related_customer_id; end if;
  if v_expense.related_appointment_id is not null and v_appointment_id<>v_expense.related_appointment_id then raise exception 'FINANCE_DOCUMENT_APPOINTMENT_MISMATCH' using errcode='23503'; end if;
  if v_expense.related_customer_id is not null and v_customer_id<>v_expense.related_customer_id then raise exception 'FINANCE_DOCUMENT_CUSTOMER_MISMATCH' using errcode='23503'; end if;
 end if;
 if v_appointment_id is not null then
  select a.customer_id into v_appointment_customer_id from public.appointments a where a.business_id=p_business_id and a.id=v_appointment_id;
  if not found then raise exception 'FINANCE_APPOINTMENT_NOT_FOUND' using errcode='23503'; end if;
  if v_customer_id is not null and v_customer_id<>v_appointment_customer_id then raise exception 'FINANCE_DOCUMENT_CUSTOMER_MISMATCH' using errcode='23503'; end if;
  v_customer_id:=v_appointment_customer_id;
 end if;
 if v_appointment_id is null and v_customer_id is null and p_expense_id is null then raise exception 'FINANCE_DOCUMENT_REQUIRES_SOURCE' using errcode='22023'; end if;
 if p_storage_path is not null and (
  p_storage_path not like p_business_id::text || '/%' or p_file_name is null or p_mime_type is null
  or p_mime_type not in ('application/pdf','image/jpeg','image/png','image/webp')
  or p_file_size_bytes is null or p_file_size_bytes<=0 or p_file_size_bytes>26214400
 ) then raise exception 'FINANCE_DOCUMENT_FILE_METADATA_INVALID' using errcode='22023'; end if;
 if p_idempotency_key is not null then
  select * into v_existing from public.business_finance_documents where business_id=p_business_id and idempotency_key=p_idempotency_key;
  if found then
   if v_existing.document_type<>p_document_type
    or v_existing.document_number is distinct from nullif(trim(coalesce(p_document_number,'')),'')
    or v_existing.appointment_id is distinct from v_appointment_id or v_existing.customer_id is distinct from v_customer_id
    or v_existing.expense_id is distinct from p_expense_id or v_existing.payment_id is distinct from p_payment_id
    or v_existing.amount_toman is distinct from p_amount_toman or v_existing.storage_path is distinct from p_storage_path
    or v_existing.file_name is distinct from p_file_name or v_existing.mime_type is distinct from p_mime_type
    or v_existing.file_size_bytes is distinct from p_file_size_bytes or v_existing.notes<>coalesce(p_notes,'') then
    raise exception 'FINANCE_IDEMPOTENCY_KEY_REUSED' using errcode='23505';
   end if;
   return v_existing.id;
  end if;
 end if;
 insert into public.business_finance_documents(
  business_id,document_type,document_number,appointment_id,customer_id,expense_id,payment_id,amount_toman,
  storage_path,file_name,mime_type,file_size_bytes,notes,idempotency_key,created_by
 ) values(
  p_business_id,p_document_type,nullif(trim(coalesce(p_document_number,'')),''),
  v_appointment_id,v_customer_id,p_expense_id,p_payment_id,p_amount_toman,p_storage_path,p_file_name,p_mime_type,
  p_file_size_bytes,coalesce(p_notes,''),p_idempotency_key,v_actor
 ) returning id into v_id;
 perform private.write_business_finance_audit(p_business_id,'document',v_id,'documented',null,
  to_jsonb((select d from public.business_finance_documents d where d.id=v_id)),null);
 return v_id;
exception when unique_violation then
 if p_idempotency_key is not null then
  select id into v_id from public.business_finance_documents where business_id=p_business_id and idempotency_key=p_idempotency_key;
  if found then return v_id; end if;
 end if;
 raise;
end;
$function$;
