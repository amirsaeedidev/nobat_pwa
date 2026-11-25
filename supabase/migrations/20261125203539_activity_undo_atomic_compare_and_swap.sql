-- Protect Undo from concurrent edits between snapshot validation and UPDATE.
do $migration$
declare
  v_definition text;
  v_original text := $old$'update public.%I as target set %s from jsonb_populate_record(null::public.%I, $1) as src where target.%I::text = $2 and target.business_id = $3'$old$;
  v_replacement text := $new$'update public.%I as target set %s from jsonb_populate_record(null::public.%I, $1) as src where target.%I::text = $2 and target.business_id = $3 and (to_jsonb(target) - ''updated_at'') = ($4::jsonb - ''updated_at'')'$new$;
begin
  select pg_get_functiondef('public.undo_business_activity_event(uuid)'::regprocedure)
    into v_definition;
  if position(v_original in v_definition)=0 then
    raise exception 'UNDO_FUNCTION_UPDATE_PATTERN_NOT_FOUND';
  end if;
  v_definition := replace(v_definition,v_original,v_replacement);
  v_definition := replace(
    v_definition,
    'using v_event.before_state, v_event.entity_id, v_event.business_id;',
    'using v_event.before_state, v_event.entity_id, v_event.business_id, v_event.after_state;'
  );
  if position('v_event.business_id, v_event.after_state' in v_definition)=0 then
    raise exception 'UNDO_FUNCTION_ARGUMENT_UPDATE_FAILED';
  end if;
  execute v_definition;
end;
$migration$;
