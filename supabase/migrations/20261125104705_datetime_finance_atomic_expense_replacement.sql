-- Atomic expense correction: keep the original immutable and replace it with a new posted row.
create or replace function private.replace_business_expense_impl(
  p_business_id uuid,
  p_expense_id uuid,
  p_amount_toman bigint,
  p_category text,
  p_description text,
  p_expense_date date,
  p_payment_method text,
  p_source_document_id text,
  p_related_appointment_id uuid,
  p_related_customer_id uuid,
  p_idempotency_key text,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_before public.business_expenses%rowtype;
  v_existing_id uuid;
  v_new_id uuid;
begin
  if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if not private.has_business_permission(p_business_id,'finance.manage') then
    raise exception 'FINANCE_MANAGE_FORBIDDEN' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'FINANCE_REPLACEMENT_REASON_REQUIRED' using errcode='22023';
  end if;

  select * into v_before
    from public.business_expenses
   where business_id=p_business_id and id=p_expense_id
   for update;
  if not found then raise exception 'FINANCE_EXPENSE_NOT_FOUND' using errcode='P0002'; end if;

  select id into v_existing_id
    from public.business_expenses
   where business_id=p_business_id and idempotency_key=p_idempotency_key;
  if found then
    if v_before.status='reversed' then return v_existing_id; end if;
    raise exception 'FINANCE_IDEMPOTENCY_KEY_REUSED' using errcode='23505';
  end if;

  if v_before.status='reversed' then
    raise exception 'FINANCE_EXPENSE_ALREADY_REVERSED' using errcode='22023';
  end if;

  v_new_id := private.record_business_expense_impl(
    p_business_id,p_amount_toman,p_category,p_description,p_expense_date,p_payment_method,
    p_source_document_id,p_related_appointment_id,p_related_customer_id,p_idempotency_key
  );

  perform private.reverse_business_expense_impl(
    p_business_id,p_expense_id,'اصلاح سند: ' || trim(p_reason)
  );

  return v_new_id;
end;
$function$;

create or replace function public.replace_business_expense(
  p_business_id uuid,
  p_expense_id uuid,
  p_amount_toman bigint,
  p_category text,
  p_description text,
  p_expense_date date,
  p_payment_method text,
  p_source_document_id text,
  p_related_appointment_id uuid,
  p_related_customer_id uuid,
  p_idempotency_key text,
  p_reason text
) returns uuid
language sql
security invoker
set search_path=''
as $function$
  select private.replace_business_expense_impl(
    p_business_id,p_expense_id,p_amount_toman,p_category,p_description,p_expense_date,
    p_payment_method,p_source_document_id,p_related_appointment_id,p_related_customer_id,
    p_idempotency_key,p_reason
  );
$function$;

revoke all on function public.replace_business_expense(uuid,uuid,bigint,text,text,date,text,text,uuid,uuid,text,text) from public,anon;
grant execute on function public.replace_business_expense(uuid,uuid,bigint,text,text,date,text,text,uuid,uuid,text,text) to authenticated;
