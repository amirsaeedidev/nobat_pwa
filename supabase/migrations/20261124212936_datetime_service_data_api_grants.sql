-- Explicit Data API grants: RLS is required, but grants must also be least-privilege.
revoke all on table public.services from public,anon;
revoke all on table public.service_categories from public,anon;
revoke all on table public.employee_services from public,anon;
revoke all on table public.employee_service_compensation from public,anon;

grant select,insert,update on table public.services to authenticated;
grant select,insert,update,delete on table public.service_categories to authenticated;
grant select,insert,update,delete on table public.employee_services to authenticated;
grant select,insert,update on table public.employee_service_compensation to authenticated;
