alter table public.services
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users(id) on delete set null;

create index if not exists services_business_archived_idx
  on public.services(business_id,archived_at)
  where archived_at is not null;
