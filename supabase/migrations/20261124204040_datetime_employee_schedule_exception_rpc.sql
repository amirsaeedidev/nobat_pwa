-- Make date-specific schedule replacement atomic and permission-checked.
create or replace function public.replace_employee_schedule_exception(
  p_business_id uuid,
  p_employee_id uuid,
  p_work_date date,
  p_is_closed boolean,
  p_reason text,
  p_shifts jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '28000';
  end if;
  if not private.has_business_permission(p_business_id, 'employees.schedule.manage') then
    raise exception 'EMPLOYEE_SCHEDULE_MANAGE_FORBIDDEN' using errcode = '42501';
  end if;
  if jsonb_typeof(p_shifts) <> 'array' then
    raise exception 'INVALID_SCHEDULE_PAYLOAD' using errcode = '22023';
  end if;

  delete from public.employee_schedule_exceptions
  where business_id = p_business_id
    and employee_id = p_employee_id
    and work_date = p_work_date;

  if p_is_closed then
    insert into public.employee_schedule_exceptions(
      business_id, employee_id, work_date, is_available, reason
    ) values (
      p_business_id, p_employee_id, p_work_date, false, coalesce(p_reason, '')
    );
  else
    insert into public.employee_schedule_exceptions(
      business_id, employee_id, work_date, is_available, starts_at, ends_at, reason
    )
    select p_business_id, p_employee_id, p_work_date, true,
      (item->>'starts_at')::time,
      (item->>'ends_at')::time,
      coalesce(p_reason, '')
    from jsonb_array_elements(p_shifts) item;
  end if;
end;
$$;

revoke all on function public.replace_employee_schedule_exception(uuid,uuid,date,boolean,text,jsonb) from public, anon;
grant execute on function public.replace_employee_schedule_exception(uuid,uuid,date,boolean,text,jsonb) to authenticated;
