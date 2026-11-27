do $$
declare
  v_definition text;
  v_updated text;
  v_old text;
  v_new text;
begin
  v_definition := pg_get_functiondef(
    'public.list_appointments(uuid,text,text,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,integer,boolean)'::regprocedure
  );
  v_old := $old$concat_ws(' ',a.reference,a.note,c.full_name,c.phone,e.full_name) ilike '%'||v_query||'%'$old$;
  v_new := $new$a.id::text=v_query
        or concat_ws(' ',a.reference,a.note,c.full_name,c.phone,e.full_name) ilike '%'||v_query||'%'$new$;
  v_updated := replace(v_definition,v_old,v_new);
  if length(v_updated)=length(v_definition) then
    raise exception 'Could not add appointment id lookup';
  end if;
  execute v_updated;
end;
$$;
