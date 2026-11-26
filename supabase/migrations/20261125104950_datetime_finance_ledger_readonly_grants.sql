-- Finance ledger is a read-only projection for authenticated tenant-scoped users.
revoke all privileges on table public.business_finance_ledger from public, anon, authenticated;
grant select on table public.business_finance_ledger to authenticated;
