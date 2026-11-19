-- Supporting indexes for tenant lookups and foreign-key maintenance.
create index if not exists businesses_created_by_idx on public.businesses (created_by);
create index if not exists business_memberships_user_id_idx on public.business_memberships (user_id);
create index if not exists app_records_created_by_idx on public.app_records (created_by);
create index if not exists app_records_updated_by_idx on public.app_records (updated_by);
