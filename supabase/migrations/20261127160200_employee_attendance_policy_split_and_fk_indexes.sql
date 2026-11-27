drop policy if exists employee_attendance_policy_manage on public.employee_attendance_payroll_policies;
create policy employee_attendance_policy_insert on public.employee_attendance_payroll_policies for insert to authenticated
with check (private.has_business_permission(business_id,'employees.manage') or private.has_business_permission(business_id,'finance.payroll.manage'));
create policy employee_attendance_policy_update on public.employee_attendance_payroll_policies for update to authenticated
using (private.has_business_permission(business_id,'employees.manage') or private.has_business_permission(business_id,'finance.payroll.manage'))
with check (private.has_business_permission(business_id,'employees.manage') or private.has_business_permission(business_id,'finance.payroll.manage'));
create index if not exists employee_attendance_records_created_by_idx on public.employee_attendance_records(created_by);
create index if not exists employee_attendance_payroll_policies_updated_by_idx on public.employee_attendance_payroll_policies(updated_by);