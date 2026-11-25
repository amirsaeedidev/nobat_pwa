-- A retry of an expense replacement must match the complete replacement payload.
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
  v_existing public.business_expenses%rowtype;
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

  select * into v_existing
    from public.business_expenses
   where business_id=p_business_id and idempotency_key=p_idempotency_key;
  if found then
    if v_before.status='reversed'
       and v_existing.id<>p_expense_id
       and v_existing.status='posted'
       and v_existing.amount_toman=p_amount_toman
       and v_existing.category=p_category
       and v_existing.description=trim(p_description)
       and v_existing.expense_date=p_expense_date
       and v_existing.payment_method is not distinct from p_payment_method
       and v_existing.source_document_id is not distinct from nullif(trim(coalesce(p_source_document_id,'')),'')
       and v_existing.related_appointment_id is not distinct from p_related_appointment_id
       and v_existing.related_customer_id is not distinct from p_related_customer_id then
      return v_existing.id;
    end if;
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
