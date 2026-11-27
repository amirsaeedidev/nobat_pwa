create index if not exists business_activity_events_actor_created_idx
  on public.business_activity_events (actor_id, created_at desc);
create index if not exists business_activity_events_undone_by_idx
  on public.business_activity_events (undone_by_event_id)
  where undone_by_event_id is not null;
