do $$
declare v_def text; v_new text; v_marker text; v_insert text;
begin
  v_def := pg_get_functiondef('private.record_appointment_payment_impl(uuid,uuid,bigint,text,text,text,text,uuid)'::regprocedure);
  v_new := replace(v_def,'  v_refunded bigint;',E'  v_refunded bigint;\n  v_paid bigint;\n  v_due bigint;');
  if v_new=v_def then raise exception 'Could not add appointment balance variables'; end if;

  v_marker := E'    if p_reverses_payment_id is not null then\n      raise exception ''RECEIPT_CANNOT_REVERSE_PAYMENT'' using errcode=''22023'';\n    end if;\n  else';
  v_insert := E'    if p_reverses_payment_id is not null then\n      raise exception ''RECEIPT_CANNOT_REVERSE_PAYMENT'' using errcode=''22023'';\n    end if;\n    v_due := greatest(0,coalesce(v_appointment.price_toman,0)-coalesce(v_appointment.discount_toman,0));\n    select coalesce(sum(case when payment_type=''refund'' then -amount_toman else amount_toman end),0)\n      into v_paid\n      from public.appointment_payments\n      where business_id=p_business_id and appointment_id=p_appointment_id;\n    if p_amount_toman > v_due-v_paid then\n      raise exception ''PAYMENT_EXCEEDS_APPOINTMENT_BALANCE'' using errcode=''22023'';\n    end if;\n  else';
  v_new := replace(v_new,v_marker,v_insert);
  if v_new=v_def then raise exception 'Could not add appointment balance guard'; end if;
  execute v_new;
end;
$$;
