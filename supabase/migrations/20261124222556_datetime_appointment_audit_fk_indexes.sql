create index if not exists appointment_audit_events_actor_idx
  on public.appointment_audit_events (actor_id);

create index if not exists appointments_deleted_by_idx
  on public.appointments (deleted_by)
  where deleted_by is not null;
