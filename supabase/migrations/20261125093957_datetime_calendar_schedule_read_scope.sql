drop policy if exists employee_working_hours_read_scoped on public.employee_working_hours;
create policy employee_working_hours_read_scoped on public.employee_working_hours
for select to authenticated
using (
  private.has_business_permission(business_id,'employees.schedule.view')
  or private.has_business_permission(business_id,'appointments.view_all')
  or employee_id = private.current_employee_id(business_id)
);

drop policy if exists employee_schedule_exceptions_read_scoped on public.employee_schedule_exceptions;
create policy employee_schedule_exceptions_read_scoped on public.employee_schedule_exceptions
for select to authenticated
using (
  private.has_business_permission(business_id,'employees.schedule.view')
  or private.has_business_permission(business_id,'appointments.view_all')
  or employee_id = private.current_employee_id(business_id)
);

drop policy if exists employee_leaves_read_scoped on public.employee_leaves;
create policy employee_leaves_read_scoped on public.employee_leaves
for select to authenticated
using (
  private.has_business_permission(business_id,'employees.leave.view')
  or private.has_business_permission(business_id,'appointments.view_all')
  or employee_id = private.current_employee_id(business_id)
);
