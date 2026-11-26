-- JSONB subtraction by object key is only valid for object snapshots.
-- Appointment audit snapshots can be scalar/null during lifecycle transitions.
do $migration$
declare
  v_definition text;
  v_original text := $old$
    if v_before is not null and v_after is not null
       and (v_before - 'updated_at') = (v_after - 'updated_at') then
      return new;
    end if;
$old$;
  v_replacement text := $new$
    if jsonb_typeof(v_before) = 'object'
       and jsonb_typeof(v_after) = 'object'
       and (v_before - 'updated_at') = (v_after - 'updated_at') then
      return new;
    end if;
$new$;
begin
  select pg_get_functiondef('public.capture_business_activity_event()'::regprocedure)
    into v_definition;
  if position(v_original in v_definition) = 0 then
    raise exception 'ACTIVITY_AUDIT_JSONB_COMPARISON_PATTERN_NOT_FOUND';
  end if;
  v_definition := replace(v_definition, v_original, v_replacement);
  execute v_definition;
end;
$migration$;
