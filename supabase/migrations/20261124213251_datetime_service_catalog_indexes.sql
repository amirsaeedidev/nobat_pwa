create index if not exists employee_services_business_service_employee_idx
  on public.employee_services(business_id,service_id,employee_id);
create index if not exists appointment_services_business_service_idx
  on public.appointment_services(business_id,service_id);
create index if not exists services_archived_by_idx
  on public.services(archived_by);
create index if not exists service_categories_business_sort_idx
  on public.service_categories(business_id,sort_order);
