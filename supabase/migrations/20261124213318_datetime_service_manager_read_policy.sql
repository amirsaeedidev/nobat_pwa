drop policy if exists services_read_scoped on public.services;
create policy services_read_scoped on public.services
for select to authenticated
using (
  private.has_business_permission(business_id,'services.view')
  or private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'appointments.view_self')
);

drop policy if exists service_categories_read on public.service_categories;
create policy service_categories_read on public.service_categories
for select to authenticated
using (
  private.has_business_permission(business_id,'services.view')
  or private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'appointments.view_self')
);
