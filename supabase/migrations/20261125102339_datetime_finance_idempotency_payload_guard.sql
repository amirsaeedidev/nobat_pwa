do $$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('private.record_appointment_payment_impl(uuid,uuid,bigint,text,text,text,text,uuid)'::regprocedure);
  v_new := replace(v_def,
    '       or v_existing.reverses_payment_id is distinct from p_reverses_payment_id then',
    '       or v_existing.description<>coalesce(trim(p_description),'''')' || E'\n' ||
    '       or v_existing.reverses_payment_id is distinct from p_reverses_payment_id then');
  if v_new=v_def then raise exception 'Could not harden receipt idempotency comparison'; end if;
  v_new := replace(v_new,
    '     and v_existing.reverses_payment_id is not distinct from p_reverses_payment_id then',
    '     and v_existing.description=coalesce(trim(p_description),'''')' || E'\n' ||
    '     and v_existing.reverses_payment_id is not distinct from p_reverses_payment_id then');
  execute v_new;

  v_def := pg_get_functiondef('private.record_business_expense_impl(uuid,bigint,text,text,date,text,text,uuid,uuid,text)'::regprocedure);
  v_new := replace(v_def,
    '       or v_existing.related_customer_id is distinct from p_related_customer_id then',
    '       or v_existing.related_customer_id is distinct from p_related_customer_id' || E'\n' ||
    '       or v_existing.source_document_id is distinct from nullif(trim(coalesce(p_source_document_id,'''')),'''') then');
  if v_new=v_def then raise exception 'Could not harden expense idempotency comparison'; end if;
  v_new := replace(v_new,
    '     and v_existing.related_customer_id is not distinct from p_related_customer_id then',
    '     and v_existing.related_customer_id is not distinct from p_related_customer_id' || E'\n' ||
    '     and v_existing.source_document_id is not distinct from nullif(trim(coalesce(p_source_document_id,'''')),'''') then');
  execute v_new;
end;
$$;
