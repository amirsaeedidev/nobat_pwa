create or replace function private.can_manage_appointment(
  p_business_id uuid,
  p_employee_id uuid,
  p_permission text
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (
      private.has_business_permission(p_business_id,p_permission)
      or private.has_business_permission(p_business_id,'appointments.manage')
    )
    and (
      private.has_business_permission(p_business_id,'appointments.view_all')
      or private.current_employee_id(p_business_id)=p_employee_id
    );
$$;
revoke all on function private.can_manage_appointment(uuid,uuid,text) from public,anon,authenticated;

do $$
declare
  v_definition text;
  v_updated text;
  v_old text;
  v_new text;
begin
  v_definition := pg_get_functiondef(
    'public.create_appointment(uuid,uuid,uuid,timestamp with time zone,uuid[],text,text,text)'::regprocedure
  );
  v_old := $old$if not (
    private.has_business_permission(p_business_id,'appointments.manage')
    or (
      private.current_employee_id(p_business_id)=p_employee_id
      and private.has_business_permission(p_business_id,'appointments.manage_self')
    )
  ) then$old$;
  v_new := $new$if not private.can_manage_appointment(p_business_id,p_employee_id,'appointments.create') then$new$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch create appointment permission'; end if;
  execute v_updated;

  v_definition := pg_get_functiondef(
    'public.update_appointment(uuid,uuid,uuid,timestamp with time zone,uuid[],text)'::regprocedure
  );
  v_old := $old$if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (
      private.current_employee_id(v_business_id)=v_current_employee_id
      and p_employee_id=v_current_employee_id
      and private.has_business_permission(v_business_id,'appointments.manage_self')
    )
  ) then$old$;
  v_new := $new$if not private.can_manage_appointment(v_business_id,v_current_employee_id,'appointments.edit')
    or (
      not private.has_business_permission(v_business_id,'appointments.view_all')
      and p_employee_id<>v_current_employee_id
    ) then$new$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch update appointment permission'; end if;
  execute v_updated;

  v_definition := pg_get_functiondef(
    'public.reschedule_appointment(uuid,timestamp with time zone)'::regprocedure
  );
  v_old := $old$if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (
      private.current_employee_id(v_business_id)=v_employee_id
      and private.has_business_permission(v_business_id,'appointments.manage_self')
    )
  ) then$old$;
  v_new := $new$if not private.can_manage_appointment(v_business_id,v_employee_id,'appointments.edit') then$new$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch reschedule appointment permission'; end if;
  execute v_updated;

  v_definition := pg_get_functiondef(
    'public.set_appointment_status(uuid,text,text)'::regprocedure
  );
  v_old := '  v_deleted_at timestamptz;';
  v_new := '  v_deleted_at timestamptz;'||E'\n'||'  v_required_permission text;';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not add status permission variable'; end if;
  v_old := $old$  if not (
    private.has_business_permission(v_business_id,'appointments.manage')
    or (
      private.current_employee_id(v_business_id)=v_employee_id
      and private.has_business_permission(v_business_id,'appointments.manage_self')
    )
  ) then$old$;
  v_new := $new$  v_required_permission := case p_status
    when 'confirmed' then 'appointments.confirm'
    when 'rejected' then 'appointments.reject'
    when 'cancelled' then 'appointments.cancel'
    when 'completed' then 'appointments.complete'
    when 'no_show' then 'appointments.edit'
    else 'appointments.edit'
  end;
  if not private.can_manage_appointment(v_business_id,v_employee_id,v_required_permission) then$new$;
  v_definition := v_updated;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch status appointment permission'; end if;
  execute v_updated;

  v_definition := pg_get_functiondef(
    'public.delete_appointment(uuid,text)'::regprocedure
  );
  v_old := '  if not private.has_business_permission(v_business_id,''appointments.manage'') then';
  v_new := '  if not private.can_manage_appointment(v_business_id,v_employee_id,''appointments.cancel'') then';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch delete appointment permission'; end if;
  execute v_updated;
end;
$$;
