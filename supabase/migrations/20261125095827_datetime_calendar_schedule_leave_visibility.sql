create or replace function public.list_calendar_leave_blocks(
  p_business_id uuid,
  p_employee_ids uuid[],
  p_from_date date,
  p_to_date date
)
returns table(employee_id uuid, starts_at timestamptz, ends_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_self_employee_id uuid;
  v_can_view_all boolean;
begin
  if (select auth.uid()) is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  if p_employee_ids is null or cardinality(p_employee_ids)=0 then return; end if;
  if p_from_date is null or p_to_date is null or p_to_date<p_from_date then
    raise exception 'CALENDAR_DATE_RANGE_INVALID' using errcode='22023';
  end if;

  v_self_employee_id := private.current_employee_id(p_business_id);
  v_can_view_all :=
    private.has_business_permission(p_business_id,'appointments.view_all')
    or private.has_business_permission(p_business_id,'employees.leave.view')
    or private.has_business_permission(p_business_id,'employees.schedule.view');

  if not v_can_view_all and (
    v_self_employee_id is null
    or cardinality(p_employee_ids)<>1
    or p_employee_ids[1]<>v_self_employee_id
  ) then
    raise exception 'CALENDAR_LEAVE_VIEW_FORBIDDEN' using errcode='42501';
  end if;

  return query
  select l.employee_id,l.starts_at,l.ends_at
  from public.employee_leaves l
  join public.businesses b on b.id=l.business_id
  where l.business_id=p_business_id
    and l.employee_id=any(p_employee_ids)
    and l.status='approved'
    and l.starts_at < ((p_to_date+1)::timestamp at time zone b.timezone)
    and l.ends_at > (p_from_date::timestamp at time zone b.timezone)
    and (v_can_view_all or l.employee_id=v_self_employee_id)
  order by l.starts_at;
end;
$function$;

revoke all on function public.list_calendar_leave_blocks(uuid,uuid[],date,date) from public,anon;
grant execute on function public.list_calendar_leave_blocks(uuid,uuid[],date,date) to authenticated;
