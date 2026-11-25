drop policy if exists employees_read_scoped on public.employees;
create policy employees_read_scoped on public.employees
for select to authenticated
using (
  private.has_business_permission(business_id,'employees.view_list')
  or private.has_business_permission(business_id,'appointments.view_all')
  or (
    auth_user_id = (select auth.uid())
    and exists (
      select 1 from public.business_memberships m
      where m.business_id = employees.business_id
        and m.user_id = (select auth.uid())
        and m.is_active
    )
  )
);

drop policy if exists business_holidays_read_scoped on public.business_holidays;
create policy business_holidays_read_scoped on public.business_holidays
for select to authenticated
using (
  private.has_business_permission(business_id, 'employees.schedule.view')
  or private.has_business_permission(business_id, 'employees.schedule.manage')
  or private.has_business_permission(business_id, 'appointments.view_all')
  or private.has_business_permission(business_id, 'appointments.view_self')
);
