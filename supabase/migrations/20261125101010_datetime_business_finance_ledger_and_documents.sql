-- Stage 9: business finance ledger, audit events, linked document metadata and private storage.
alter table public.business_expenses
  alter column source_document_id drop not null,
  add column if not exists expense_date date not null default current_date,
  add column if not exists payment_method text,
  add column if not exists idempotency_key text,
  add column if not exists related_appointment_id uuid,
  add column if not exists related_customer_id uuid,
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid references auth.users(id),
  add column if not exists reversal_reason text;

alter table public.business_expenses
  add constraint business_expenses_payment_method_check
    check (payment_method is null or payment_method = any(array['cash','pos','bank_transfer','wallet','other'])),
  add constraint business_expenses_reversal_state_check
    check ((status <> 'reversed' and reversed_at is null and reversed_by is null)
       or (status = 'reversed' and reversed_at is not null and reversed_by is not null)),
  add constraint business_expenses_business_id_related_appointment_fkey
    foreign key (business_id, related_appointment_id)
    references public.appointments(business_id,id) on delete restrict,
  add constraint business_expenses_business_id_related_customer_fkey
    foreign key (business_id, related_customer_id)
    references public.customers(business_id,id) on delete restrict;

create unique index if not exists business_expenses_business_id_id_key on public.business_expenses(business_id,id);
create unique index if not exists business_expenses_idempotency_unique on public.business_expenses(business_id,idempotency_key) where idempotency_key is not null;
create index if not exists business_expenses_business_expense_date_idx on public.business_expenses(business_id,expense_date desc,status);

create table if not exists public.business_finance_documents (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  document_type text not null check (document_type = any(array['receipt','refund','expense_receipt','invoice','discount_note','payment_proof','other'])),
  document_number text,
  appointment_id uuid,
  customer_id uuid,
  expense_id uuid,
  payment_id uuid,
  amount_toman bigint check (amount_toman is null or amount_toman >= 0),
  storage_path text,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  notes text not null default '',
  idempotency_key text,
  status text not null default 'active' check (status in ('active','void')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  voided_by uuid references auth.users(id),
  voided_at timestamptz,
  constraint business_finance_documents_has_source_check check (appointment_id is not null or customer_id is not null or expense_id is not null),
  constraint business_finance_documents_void_state_check check ((status='active' and voided_at is null and voided_by is null) or (status='void' and voided_at is not null and voided_by is not null)),
  constraint business_finance_documents_file_metadata_check check (
    (storage_path is null and file_name is null and mime_type is null and file_size_bytes is null)
    or (storage_path is not null and file_name is not null and mime_type is not null and file_size_bytes > 0 and file_size_bytes <= 26214400)
  ),
  constraint business_finance_documents_business_id_id_key unique (business_id,id),
  constraint business_finance_documents_appointment_fkey foreign key (business_id,appointment_id) references public.appointments(business_id,id) on delete restrict,
  constraint business_finance_documents_customer_fkey foreign key (business_id,customer_id) references public.customers(business_id,id) on delete restrict,
  constraint business_finance_documents_expense_fkey foreign key (business_id,expense_id) references public.business_expenses(business_id,id) on delete restrict,
  constraint business_finance_documents_payment_fkey foreign key (business_id,payment_id) references public.appointment_payments(business_id,id) on delete restrict
);
create unique index if not exists business_finance_documents_number_unique on public.business_finance_documents(business_id,document_number) where document_number is not null;
create unique index if not exists business_finance_documents_idempotency_unique on public.business_finance_documents(business_id,idempotency_key) where idempotency_key is not null;
create index if not exists business_finance_documents_appointment_idx on public.business_finance_documents(business_id,appointment_id,created_at desc);
create index if not exists business_finance_documents_customer_idx on public.business_finance_documents(business_id,customer_id,created_at desc);
create index if not exists business_finance_documents_expense_idx on public.business_finance_documents(business_id,expense_id,created_at desc);

create table if not exists public.business_finance_audit_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entity_type text not null check (entity_type in ('payment','expense','document')),
  entity_id uuid not null,
  action text not null check (action in ('created','refunded','reversed','documented','voided')),
  actor_id uuid not null references auth.users(id),
  before_state jsonb,
  after_state jsonb,
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists business_finance_audit_events_business_period_idx on public.business_finance_audit_events(business_id,created_at desc);
create index if not exists business_finance_audit_events_entity_idx on public.business_finance_audit_events(business_id,entity_type,entity_id,created_at desc);

alter table public.business_finance_documents enable row level security;
alter table public.business_finance_audit_events enable row level security;
create policy business_finance_documents_read on public.business_finance_documents for select to authenticated using (private.has_business_permission(business_id,'finance.view'));
create policy business_finance_audit_events_read on public.business_finance_audit_events for select to authenticated using (private.has_business_permission(business_id,'finance.view'));

revoke all on public.appointment_payments from anon,authenticated;
revoke all on public.business_expenses from anon,authenticated;
revoke all on public.business_finance_documents from anon,authenticated;
revoke all on public.business_finance_audit_events from anon,authenticated;
grant select on public.appointment_payments,public.business_expenses,public.business_finance_documents,public.business_finance_audit_events to authenticated;

create or replace function private.write_business_finance_audit(p_business_id uuid,p_entity_type text,p_entity_id uuid,p_action text,p_before jsonb,p_after jsonb,p_reason text default null)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_id uuid:=gen_random_uuid(); v_actor uuid:=(select auth.uid());
begin
  if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  insert into public.business_finance_audit_events(id,business_id,entity_type,entity_id,action,actor_id,before_state,after_state,reason)
  values(v_id,p_business_id,p_entity_type,p_entity_id,p_action,v_actor,p_before,p_after,p_reason);
  return v_id;
end;
$function$;

create or replace function private.record_appointment_payment_impl(
 p_business_id uuid,p_appointment_id uuid,p_amount_toman bigint,p_method text,p_payment_type text,
 p_description text,p_idempotency_key text,p_reverses_payment_id uuid default null
) returns uuid language plpgsql security definer set search_path=''
as $function$
declare
 v_actor uuid:=(select auth.uid()); v_appointment public.appointments%rowtype;
 v_original public.appointment_payments%rowtype; v_existing public.appointment_payments%rowtype;
 v_refunded bigint; v_id uuid;
begin
 if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage') then raise exception 'FINANCE_MANAGE_FORBIDDEN' using errcode='42501'; end if;
 if p_amount_toman is null or p_amount_toman<=0 then raise exception 'FINANCE_AMOUNT_INVALID' using errcode='22023'; end if;
 if p_method not in ('cash','pos','bank_transfer','wallet','other') then raise exception 'FINANCE_PAYMENT_METHOD_INVALID' using errcode='22023'; end if;
 if p_payment_type not in ('receipt','refund') then raise exception 'FINANCE_PAYMENT_TYPE_INVALID' using errcode='22023'; end if;
 if p_idempotency_key is null or length(trim(p_idempotency_key))<8 or length(p_idempotency_key)>160 then raise exception 'FINANCE_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
 select * into v_existing from public.appointment_payments where business_id=p_business_id and idempotency_key=p_idempotency_key;
 if found then
  if v_existing.appointment_id<>p_appointment_id or v_existing.amount_toman<>p_amount_toman or v_existing.method<>p_method
    or v_existing.payment_type<>p_payment_type or v_existing.reverses_payment_id is distinct from p_reverses_payment_id then
    raise exception 'FINANCE_IDEMPOTENCY_KEY_REUSED' using errcode='23505';
  end if;
  return v_existing.id;
 end if;
 select * into v_appointment from public.appointments where business_id=p_business_id and id=p_appointment_id and deleted_at is null for update;
 if not found then raise exception 'FINANCE_APPOINTMENT_NOT_FOUND' using errcode='23503'; end if;
 if p_payment_type='receipt' then
  if p_reverses_payment_id is not null then raise exception 'RECEIPT_CANNOT_REVERSE_PAYMENT' using errcode='22023'; end if;
 else
  if p_reverses_payment_id is null then raise exception 'REFUND_REQUIRES_ORIGINAL_RECEIPT' using errcode='22023'; end if;
  select * into v_original from public.appointment_payments where business_id=p_business_id and id=p_reverses_payment_id for update;
  if not found or v_original.payment_type<>'receipt' or v_original.appointment_id<>p_appointment_id or v_original.customer_id<>v_appointment.customer_id then
   raise exception 'REFUND_ORIGINAL_RECEIPT_INVALID' using errcode='23503';
  end if;
  select coalesce(sum(amount_toman),0) into v_refunded from public.appointment_payments where business_id=p_business_id and reverses_payment_id=v_original.id;
  if p_amount_toman>v_original.amount_toman-v_refunded then raise exception 'REFUND_EXCEEDS_REMAINING_RECEIPT' using errcode='22023'; end if;
 end if;
 insert into public.appointment_payments(business_id,appointment_id,customer_id,amount_toman,method,payment_type,description,reverses_payment_id,idempotency_key,created_by)
 values(p_business_id,p_appointment_id,v_appointment.customer_id,p_amount_toman,p_method,p_payment_type,coalesce(trim(p_description),''),p_reverses_payment_id,p_idempotency_key,v_actor)
 returning id into v_id;
 perform private.write_business_finance_audit(p_business_id,'payment',v_id,case when p_payment_type='refund' then 'refunded' else 'created' end,null,
  to_jsonb((select p from public.appointment_payments p where p.id=v_id)),null);
 return v_id;
exception when unique_violation then
 select * into v_existing from public.appointment_payments where business_id=p_business_id and idempotency_key=p_idempotency_key;
 if found and v_existing.appointment_id=p_appointment_id and v_existing.amount_toman=p_amount_toman and v_existing.method=p_method
  and v_existing.payment_type=p_payment_type and v_existing.reverses_payment_id is not distinct from p_reverses_payment_id then return v_existing.id; end if;
 raise;
end;
$function$;

create or replace function public.record_appointment_payment(p_business_id uuid,p_appointment_id uuid,p_amount_toman bigint,p_method text,p_payment_type text,p_description text,p_idempotency_key text,p_reverses_payment_id uuid default null)
returns uuid language sql security invoker set search_path=''
as $function$ select private.record_appointment_payment_impl(p_business_id,p_appointment_id,p_amount_toman,p_method,p_payment_type,p_description,p_idempotency_key,p_reverses_payment_id); $function$;

create or replace function private.record_business_expense_impl(
 p_business_id uuid,p_amount_toman bigint,p_category text,p_description text,p_expense_date date,p_payment_method text,
 p_source_document_id text,p_related_appointment_id uuid,p_related_customer_id uuid,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_actor uuid:=(select auth.uid()); v_existing public.business_expenses%rowtype; v_id uuid;
begin
 if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage') then raise exception 'FINANCE_MANAGE_FORBIDDEN' using errcode='42501'; end if;
 if p_amount_toman is null or p_amount_toman<=0 then raise exception 'FINANCE_AMOUNT_INVALID' using errcode='22023'; end if;
 if p_category not in ('operating','rent','supplies','utilities','marketing','maintenance','other') then raise exception 'FINANCE_EXPENSE_CATEGORY_INVALID' using errcode='22023'; end if;
 if p_payment_method is not null and p_payment_method not in ('cash','pos','bank_transfer','wallet','other') then raise exception 'FINANCE_PAYMENT_METHOD_INVALID' using errcode='22023'; end if;
 if p_expense_date is null then raise exception 'FINANCE_EXPENSE_DATE_REQUIRED' using errcode='22023'; end if;
 if length(trim(coalesce(p_description,'')))=0 or length(p_description)>500 then raise exception 'FINANCE_EXPENSE_DESCRIPTION_REQUIRED' using errcode='22023'; end if;
 if p_idempotency_key is null or length(trim(p_idempotency_key))<8 or length(p_idempotency_key)>160 then raise exception 'FINANCE_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
 select * into v_existing from public.business_expenses where business_id=p_business_id and idempotency_key=p_idempotency_key;
 if found then
  if v_existing.amount_toman<>p_amount_toman or v_existing.category<>p_category or v_existing.description<>trim(p_description)
   or v_existing.expense_date<>p_expense_date or v_existing.payment_method is distinct from p_payment_method
   or v_existing.related_appointment_id is distinct from p_related_appointment_id or v_existing.related_customer_id is distinct from p_related_customer_id then
   raise exception 'FINANCE_IDEMPOTENCY_KEY_REUSED' using errcode='23505';
  end if;
  return v_existing.id;
 end if;
 if p_related_appointment_id is not null then
  perform 1 from public.appointments a where a.business_id=p_business_id and a.id=p_related_appointment_id and a.deleted_at is null;
  if not found then raise exception 'FINANCE_APPOINTMENT_NOT_FOUND' using errcode='23503'; end if;
  if p_related_customer_id is not null and not exists(select 1 from public.appointments a where a.business_id=p_business_id and a.id=p_related_appointment_id and a.customer_id=p_related_customer_id) then
   raise exception 'FINANCE_APPOINTMENT_CUSTOMER_MISMATCH' using errcode='23503';
  end if;
 elsif p_related_customer_id is not null then
  perform 1 from public.customers c where c.business_id=p_business_id and c.id=p_related_customer_id;
  if not found then raise exception 'FINANCE_CUSTOMER_NOT_FOUND' using errcode='23503'; end if;
 end if;
 insert into public.business_expenses(business_id,amount_toman,category,description,source_document_id,status,created_by,expense_date,payment_method,idempotency_key,related_appointment_id,related_customer_id)
 values(p_business_id,p_amount_toman,p_category,trim(p_description),nullif(trim(coalesce(p_source_document_id,'')),''),'posted',v_actor,p_expense_date,p_payment_method,p_idempotency_key,p_related_appointment_id,p_related_customer_id)
 returning id into v_id;
 perform private.write_business_finance_audit(p_business_id,'expense',v_id,'created',null,to_jsonb((select e from public.business_expenses e where e.id=v_id)),null);
 return v_id;
exception when unique_violation then
 select * into v_existing from public.business_expenses where business_id=p_business_id and idempotency_key=p_idempotency_key;
 if found and v_existing.amount_toman=p_amount_toman and v_existing.category=p_category and v_existing.description=trim(p_description)
  and v_existing.expense_date=p_expense_date and v_existing.payment_method is not distinct from p_payment_method
  and v_existing.related_appointment_id is not distinct from p_related_appointment_id and v_existing.related_customer_id is not distinct from p_related_customer_id then return v_existing.id; end if;
 raise;
end;
$function$;

create or replace function public.record_business_expense(p_business_id uuid,p_amount_toman bigint,p_category text,p_description text,p_expense_date date,p_payment_method text,p_source_document_id text,p_related_appointment_id uuid,p_related_customer_id uuid,p_idempotency_key text)
returns uuid language sql security invoker set search_path=''
as $function$ select private.record_business_expense_impl(p_business_id,p_amount_toman,p_category,p_description,p_expense_date,p_payment_method,p_source_document_id,p_related_appointment_id,p_related_customer_id,p_idempotency_key); $function$;

create or replace function private.reverse_business_expense_impl(p_business_id uuid,p_expense_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_actor uuid:=(select auth.uid()); v_before public.business_expenses%rowtype; v_after public.business_expenses%rowtype;
begin
 if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage') then raise exception 'FINANCE_MANAGE_FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'FINANCE_REVERSAL_REASON_REQUIRED' using errcode='22023'; end if;
 select * into v_before from public.business_expenses where business_id=p_business_id and id=p_expense_id for update;
 if not found then raise exception 'FINANCE_EXPENSE_NOT_FOUND' using errcode='P0002'; end if;
 if v_before.status='reversed' then return v_before.id; end if;
 update public.business_expenses set status='reversed',reversed_at=now(),reversed_by=v_actor,reversal_reason=trim(p_reason),updated_at=now()
 where business_id=p_business_id and id=p_expense_id returning * into v_after;
 perform private.write_business_finance_audit(p_business_id,'expense',p_expense_id,'reversed',to_jsonb(v_before),to_jsonb(v_after),trim(p_reason));
 return p_expense_id;
end;
$function$;
create or replace function public.reverse_business_expense(p_business_id uuid,p_expense_id uuid,p_reason text)
returns uuid language sql security invoker set search_path=''
as $function$ select private.reverse_business_expense_impl(p_business_id,p_expense_id,p_reason); $function$;


create or replace function private.create_business_finance_document_impl(
 p_business_id uuid,p_document_type text,p_document_number text,p_appointment_id uuid,p_customer_id uuid,
 p_expense_id uuid,p_payment_id uuid,p_amount_toman bigint,p_storage_path text,p_file_name text,p_mime_type text,
 p_file_size_bytes bigint,p_notes text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=''
as $function$
declare
 v_actor uuid:=(select auth.uid()); v_payment public.appointment_payments%rowtype; v_expense public.business_expenses%rowtype;
 v_appointment_id uuid:=p_appointment_id; v_customer_id uuid:=p_customer_id;
 v_existing public.business_finance_documents%rowtype; v_id uuid;
begin
 if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage') then raise exception 'FINANCE_MANAGE_FORBIDDEN' using errcode='42501'; end if;
 if p_document_type not in ('receipt','refund','expense_receipt','invoice','discount_note','payment_proof','other') then raise exception 'FINANCE_DOCUMENT_TYPE_INVALID' using errcode='22023'; end if;
 if p_appointment_id is null and p_customer_id is null and p_expense_id is null and p_payment_id is null then raise exception 'FINANCE_DOCUMENT_REQUIRES_SOURCE' using errcode='22023'; end if;
 if p_idempotency_key is not null then
  select * into v_existing from public.business_finance_documents where business_id=p_business_id and idempotency_key=p_idempotency_key;
  if found then return v_existing.id; end if;
 end if;
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
 end if;
 if v_appointment_id is null and v_customer_id is null and p_expense_id is null then raise exception 'FINANCE_DOCUMENT_REQUIRES_SOURCE' using errcode='22023'; end if;
 if p_storage_path is not null and p_storage_path not like p_business_id::text || '/%' then raise exception 'FINANCE_DOCUMENT_STORAGE_PATH_INVALID' using errcode='22023'; end if;
 insert into public.business_finance_documents(
  business_id,document_type,document_number,appointment_id,customer_id,expense_id,payment_id,amount_toman,
  storage_path,file_name,mime_type,file_size_bytes,notes,idempotency_key,created_by
 ) values (
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

create or replace function public.create_business_finance_document(
 p_business_id uuid,p_document_type text,p_document_number text default null,p_appointment_id uuid default null,
 p_customer_id uuid default null,p_expense_id uuid default null,p_payment_id uuid default null,p_amount_toman bigint default null,
 p_storage_path text default null,p_file_name text default null,p_mime_type text default null,p_file_size_bytes bigint default null,
 p_notes text default '',p_idempotency_key text default null
) returns uuid language sql security invoker set search_path=''
as $function$
 select private.create_business_finance_document_impl(p_business_id,p_document_type,p_document_number,p_appointment_id,
  p_customer_id,p_expense_id,p_payment_id,p_amount_toman,p_storage_path,p_file_name,p_mime_type,p_file_size_bytes,p_notes,p_idempotency_key);
$function$;

create or replace function private.void_business_finance_document_impl(p_business_id uuid,p_document_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_actor uuid:=(select auth.uid()); v_before public.business_finance_documents%rowtype; v_after public.business_finance_documents%rowtype;
begin
 if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if not private.has_business_permission(p_business_id,'finance.manage') then raise exception 'FINANCE_MANAGE_FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'FINANCE_VOID_REASON_REQUIRED' using errcode='22023'; end if;
 select * into v_before from public.business_finance_documents where business_id=p_business_id and id=p_document_id for update;
 if not found then raise exception 'FINANCE_DOCUMENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_before.status='void' then return v_before.id; end if;
 update public.business_finance_documents set status='void',voided_at=now(),voided_by=v_actor
  where business_id=p_business_id and id=p_document_id returning * into v_after;
 perform private.write_business_finance_audit(p_business_id,'document',p_document_id,'voided',to_jsonb(v_before),to_jsonb(v_after),trim(p_reason));
 return p_document_id;
end;
$function$;

create or replace function public.void_business_finance_document(p_business_id uuid,p_document_id uuid,p_reason text)
returns uuid language sql security invoker set search_path=''
as $function$ select private.void_business_finance_document_impl(p_business_id,p_document_id,p_reason); $function$;

revoke all on function private.write_business_finance_audit(uuid,text,uuid,text,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function private.record_appointment_payment_impl(uuid,uuid,bigint,text,text,text,text,uuid) from public,anon,authenticated;
revoke all on function private.record_business_expense_impl(uuid,bigint,text,text,date,text,text,uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.reverse_business_expense_impl(uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.create_business_finance_document_impl(uuid,text,text,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,text,text) from public,anon,authenticated;
revoke all on function private.void_business_finance_document_impl(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.record_appointment_payment_impl(uuid,uuid,bigint,text,text,text,text,uuid) to authenticated;
grant execute on function private.record_business_expense_impl(uuid,bigint,text,text,date,text,text,uuid,uuid,text) to authenticated;
grant execute on function private.reverse_business_expense_impl(uuid,uuid,text) to authenticated;
grant execute on function private.create_business_finance_document_impl(uuid,text,text,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,text,text) to authenticated;
grant execute on function private.void_business_finance_document_impl(uuid,uuid,text) to authenticated;

revoke all on function public.record_appointment_payment(uuid,uuid,bigint,text,text,text,text,uuid) from public,anon;
revoke all on function public.record_business_expense(uuid,bigint,text,text,date,text,text,uuid,uuid,text) from public,anon;
revoke all on function public.reverse_business_expense(uuid,uuid,text) from public,anon;
revoke all on function public.create_business_finance_document(uuid,text,text,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,text,text) from public,anon;
revoke all on function public.void_business_finance_document(uuid,uuid,text) from public,anon;
grant execute on function public.record_appointment_payment(uuid,uuid,bigint,text,text,text,text,uuid) to authenticated;
grant execute on function public.record_business_expense(uuid,bigint,text,text,date,text,text,uuid,uuid,text) to authenticated;
grant execute on function public.reverse_business_expense(uuid,uuid,text) to authenticated;
grant execute on function public.create_business_finance_document(uuid,text,text,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,text,text) to authenticated;
grant execute on function public.void_business_finance_document(uuid,uuid,text) to authenticated;
\n-- Later migrations harden expense and document idempotency/link validation.
create or replace view public.business_finance_ledger with (security_invoker=true) as
 select p.id as entry_id,p.business_id,p.created_at as occurred_at,
  case when p.payment_type='refund' then 'refund' else 'receipt' end as entry_type,
  case when p.payment_type='refund' then -p.amount_toman else p.amount_toman end as signed_amount_toman,
  p.method as payment_method,p.appointment_id,p.customer_id,null::uuid as expense_id,p.description,'posted'::text as status
 from public.appointment_payments p
 union all
 select e.id,e.business_id,(e.expense_date::timestamp at time zone 'UTC'),'expense'::text,-e.amount_toman,
  e.payment_method,e.related_appointment_id,e.related_customer_id,e.id,e.description,e.status
 from public.business_expenses e where e.status='posted';
grant select on public.business_finance_ledger to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('business-finance-documents','business-finance-documents',false,26214400,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy business_finance_documents_storage_read on storage.objects for select to authenticated
using(bucket_id='business-finance-documents' and (storage.foldername(name))[1] is not null
 and private.has_business_permission(((storage.foldername(name))[1])::uuid,'finance.view'));
create policy business_finance_documents_storage_insert on storage.objects for insert to authenticated
with check(bucket_id='business-finance-documents' and (storage.foldername(name))[1] is not null
 and private.has_business_permission(((storage.foldername(name))[1])::uuid,'finance.manage'));
