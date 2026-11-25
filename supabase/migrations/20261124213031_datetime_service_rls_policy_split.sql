-- Separate read and write policies to avoid redundant permissive SELECT checks.
drop policy if exists services_manage_all on public.services;
create policy services_insert_manage on public.services
for insert to authenticated
with check (private.has_business_permission(business_id,'services.manage'));
create policy services_update_manage on public.services
for update to authenticated
using (private.has_business_permission(business_id,'services.manage'))
with check (private.has_business_permission(business_id,'services.manage'));

drop policy if exists service_categories_manage on public.service_categories;
create policy service_categories_insert_manage on public.service_categories
for insert to authenticated
with check (private.has_business_permission(business_id,'services.manage'));
create policy service_categories_update_manage on public.service_categories
for update to authenticated
using (private.has_business_permission(business_id,'services.manage'))
with check (private.has_business_permission(business_id,'services.manage'));
create policy service_categories_delete_manage on public.service_categories
for delete to authenticated
using (private.has_business_permission(business_id,'services.manage'));

drop policy if exists employee_services_manage_all on public.employee_services;
create policy employee_services_insert_manage on public.employee_services
for insert to authenticated
with check (
  private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'services.manage')
);
create policy employee_services_update_manage on public.employee_services
for update to authenticated
using (
  private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'services.manage')
)
with check (
  private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'services.manage')
);
create policy employee_services_delete_manage on public.employee_services
for delete to authenticated
using (
  private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'services.manage')
);

drop policy if exists employee_service_compensation_write on public.employee_service_compensation;
create policy employee_service_compensation_insert_manage on public.employee_service_compensation
for insert to authenticated
with check (
  private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'finance.manage')
);
create policy employee_service_compensation_update_manage on public.employee_service_compensation
for update to authenticated
using (
  private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'finance.manage')
)
with check (
  private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'finance.manage')
);
