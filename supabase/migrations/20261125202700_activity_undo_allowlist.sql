
create or replace function public.enforce_business_activity_undo_allowlist()
returns trigger language plpgsql set search_path=''
as $function$
begin
  new.is_reversible := new.is_reversible and new.source_table in (
    'appointments','customers','employees','services','service_categories','business_settings',
    'app_records','employee_working_hours','employee_schedule_exceptions','employee_leaves',
    'employee_services','employee_commission_rules','employee_service_compensation','employee_pay_profiles'
  );
  return new;
end;
$function$;
revoke all on function public.enforce_business_activity_undo_allowlist() from public,anon,authenticated;
drop trigger if exists business_activity_events_enforce_undo_allowlist on public.business_activity_events;
create trigger business_activity_events_enforce_undo_allowlist before insert on public.business_activity_events
for each row execute function public.enforce_business_activity_undo_allowlist();
