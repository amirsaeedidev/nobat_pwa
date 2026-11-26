do $$
declare
  v_definition text;
  v_updated text;
  v_old text := $old$concat_ws(' ',a.reference,a.note,c.full_name,c.phone,e.full_name) ilike '%'||v_query||'%'
        or exists ($old$;
  v_new text := $new$concat_ws(' ',a.reference,a.note,c.full_name,c.phone,e.full_name) ilike '%'||v_query||'%'
        or (regexp_replace(v_query,'[^0-9+]','','g')<>'' and c.normalized_phone ilike '%'||regexp_replace(v_query,'[^0-9+]','','g')||'%')
        or exists ($new$;
begin
  v_definition := pg_get_functiondef(
    'public.list_appointments(uuid,text,text,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,integer,boolean)'::regprocedure
  );
  v_updated := replace(v_definition,v_old,v_new);
  if length(v_updated)=length(v_definition) then
    raise exception 'Could not add normalized phone search to appointment listing';
  end if;
  execute v_updated;
end;
$$;
