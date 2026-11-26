-- Every finance document must have a stable idempotency key, including metadata-only records.
do $$
declare
  v_def text;
  v_new text;
  v_marker text;
  v_replacement text;
begin
  v_def := pg_get_functiondef(
    'private.create_business_finance_document_impl(uuid,text,text,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,text,text)'::regprocedure
  );
  v_marker := $marker$
  if p_document_type not in ('receipt','refund','expense_receipt','invoice','discount_note','payment_proof','other') then
    raise exception 'FINANCE_DOCUMENT_TYPE_INVALID' using errcode='22023';
  end if;
  $marker$;
  v_replacement := v_marker || E'\n  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 160 then\n    raise exception ''FINANCE_IDEMPOTENCY_KEY_REQUIRED'' using errcode=''22023'';\n  end if;';
  v_new := replace(v_def,v_marker,v_replacement);
  if v_new=v_def then raise exception 'Could not enforce finance document idempotency key'; end if;
  execute v_new;
end;
$$;
