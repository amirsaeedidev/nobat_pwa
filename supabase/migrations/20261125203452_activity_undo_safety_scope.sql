-- Never offer Undo for finance ledgers, role memberships or partial appointment edits.
create or replace function public.enforce_business_activity_undo_allowlist()
returns trigger language plpgsql set search_path=''
as $function$
begin
  new.is_reversible := new.is_reversible and new.source_table in (
    'appointments','customers','employees','services','service_categories',
    'business_settings','app_records','employee_working_hours',
    'employee_schedule_exceptions','employee_leaves','employee_services'
  );
  if new.source_table='appointments'
     and new.action not in ('appointment_rescheduled','appointment_status_changed') then
    new.is_reversible := false;
  end if;
  if new.source_table='app_records'
     and new.entity_type not in ('roles','settings','employee_services') then
    new.is_reversible := false;
  end if;
  return new;
end;
$function$;
revoke all on function public.enforce_business_activity_undo_allowlist() from public,anon,authenticated;

update public.business_activity_events set is_reversible=false
where source_table in (
  'business_memberships','employee_pay_profiles','employee_commission_rules',
  'employee_service_compensation','businesses','business_finance_documents'
)
or (source_table='appointments' and action not in ('appointment_rescheduled','appointment_status_changed'))
or (source_table='app_records' and entity_type not in ('roles','settings','employee_services'));

drop trigger if exists business_activity_events_enforce_undo_allowlist on public.business_activity_events;
create trigger business_activity_events_enforce_undo_allowlist
before insert on public.business_activity_events
for each row execute function public.enforce_business_activity_undo_allowlist();
