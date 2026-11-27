-- Harden the finance ledger view and make document idempotency race-safe.
-- The view is security_invoker, so authenticated reads remain constrained by
-- the underlying tenant-scoped RLS policies on payments, expenses and appointments.
revoke all privileges on table public.business_finance_ledger from public, anon;
grant select on table public.business_finance_ledger to authenticated;

do $$
declare
  v_def text;
  v_new text;
  v_old text;
  v_replacement text;
begin
  v_def := pg_get_functiondef(
    'private.create_business_finance_document_impl(uuid,text,text,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,text,text)'::regprocedure
  );

  v_old := $old$
    select id into v_id from public.business_finance_documents
      where business_id=p_business_id and idempotency_key=p_idempotency_key;
    if found then return v_id; end if;
  $old$;

  v_replacement := $new$
    select * into v_existing from public.business_finance_documents
      where business_id=p_business_id and idempotency_key=p_idempotency_key;
    if found then
      if v_existing.document_type<>p_document_type
         or v_existing.document_number is distinct from nullif(trim(coalesce(p_document_number,'')),'')
         or v_existing.appointment_id is distinct from v_appointment_id
         or v_existing.customer_id is distinct from v_customer_id
         or v_existing.expense_id is distinct from p_expense_id
         or v_existing.payment_id is distinct from p_payment_id
         or v_existing.amount_toman is distinct from p_amount_toman
         or v_existing.storage_path is distinct from p_storage_path
         or v_existing.file_name is distinct from p_file_name
         or v_existing.mime_type is distinct from p_mime_type
         or v_existing.file_size_bytes is distinct from p_file_size_bytes
         or v_existing.notes<>coalesce(p_notes,'') then
        raise exception 'FINANCE_IDEMPOTENCY_KEY_REUSED' using errcode='23505';
      end if;
      return v_existing.id;
    end if;
  $new$;

  v_new := replace(v_def, v_old, v_replacement);
  if v_new = v_def then
    raise exception 'Could not harden finance document idempotency race handler';
  end if;
  execute v_new;
end;
$$;
