-- Cover both user foreign keys on the business settings row.
create index if not exists business_settings_created_by_idx
  on public.business_settings(created_by);
create index if not exists business_settings_updated_by_idx
  on public.business_settings(updated_by);
