-- Persist the complete staff profile and save related work data atomically.
alter table public.employees
  add column if not exists title text not null default '',
  add column if not exists staff_role text not null default 'specialist',
  add column if not exists employment_status text not null default 'active',
  add column if not exists specialties text[] not null default '{}',
  add column if not exists emergency_contact_name text not null default '',
  add column if not exists emergency_contact_phone text not null default '',
  add column if not exists schedule_enabled boolean not null default true,
  add column if not exists buffer_minutes integer not null default 0;

alter table public.employees
  add constraint employees_staff_role_check
    check (staff_role in ('owner','manager','receptionist','specialist')),
  add constraint employees_employment_status_check
    check (employment_status in ('active','inactive','onLeave','suspended')),
  add constraint employees_buffer_minutes_check
    check (buffer_minutes between 0 and 240),
  add constraint employees_title_length_check
    check (char_length(title) <= 120),
  add constraint employees_emergency_contact_name_length_check
    check (char_length(emergency_contact_name) <= 120),
  add constraint employees_emergency_contact_phone_length_check
    check (char_length(emergency_contact_phone) <= 32);

create or replace function public.save_employee_profile(
  p_business_id uuid,
  p_employee_id uuid,
  p_profile jsonb,
  p_services jsonb,
  p_working_hours jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_employee_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '28000';
  end if;
  if not private.has_business_permission(p_business_id, 'employees.manage') then
    raise exception 'EMPLOYEE_MANAGE_FORBIDDEN' using errcode = '42501';
  end if;
  if jsonb_typeof(p_profile) <> 'object'
     or jsonb_typeof(p_services) <> 'array'
     or jsonb_typeof(p_working_hours) <> 'array' then
    raise exception 'INVALID_EMPLOYEE_PAYLOAD' using errcode = '22023';
  end if;

  if p_employee_id is null then
    insert into public.employees (
      business_id, full_name, phone, email, is_active, hired_on, notes,
      title, staff_role, employment_status, specialties,
      emergency_contact_name, emergency_contact_phone,
      schedule_enabled, buffer_minutes
    ) values (
      p_business_id,
      nullif(trim(p_profile->>'full_name'), ''),
      nullif(trim(p_profile->>'phone'), ''),
      nullif(trim(p_profile->>'email'), ''),
      coalesce((p_profile->>'is_active')::boolean, true),
      nullif(p_profile->>'hired_on','')::date,
      coalesce(p_profile->>'notes',''),
      coalesce(p_profile->>'title',''),
      coalesce(p_profile->>'staff_role','specialist'),
      coalesce(p_profile->>'employment_status','active'),
      coalesce(array(select jsonb_array_elements_text(coalesce(p_profile->'specialties','[]'::jsonb))), '{}'),
      coalesce(p_profile->>'emergency_contact_name',''),
      coalesce(p_profile->>'emergency_contact_phone',''),
      coalesce((p_profile->>'schedule_enabled')::boolean,true),
      coalesce((p_profile->>'buffer_minutes')::integer,0)
    ) returning id into v_employee_id;
  else
    update public.employees set
      full_name = nullif(trim(p_profile->>'full_name'), ''),
      phone = nullif(trim(p_profile->>'phone'), ''),
      email = nullif(trim(p_profile->>'email'), ''),
      is_active = coalesce((p_profile->>'is_active')::boolean, true),
      hired_on = nullif(p_profile->>'hired_on','')::date,
      notes = coalesce(p_profile->>'notes',''),
      title = coalesce(p_profile->>'title',''),
      staff_role = coalesce(p_profile->>'staff_role','specialist'),
      employment_status = coalesce(p_profile->>'employment_status','active'),
      specialties = coalesce(array(select jsonb_array_elements_text(coalesce(p_profile->'specialties','[]'::jsonb))), '{}'),
      emergency_contact_name = coalesce(p_profile->>'emergency_contact_name',''),
      emergency_contact_phone = coalesce(p_profile->>'emergency_contact_phone',''),
      schedule_enabled = coalesce((p_profile->>'schedule_enabled')::boolean,true),
      buffer_minutes = coalesce((p_profile->>'buffer_minutes')::integer,0),
      updated_at = now()
    where business_id = p_business_id and id = p_employee_id
    returning id into v_employee_id;
    if v_employee_id is null then
      raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  delete from public.employee_services
    where business_id = p_business_id and employee_id = v_employee_id;
  insert into public.employee_services (
    business_id, employee_id, service_id, is_active,
    custom_price_toman, custom_duration_minutes, notes
  )
  select p_business_id, v_employee_id, (item->>'service_id')::uuid,
         coalesce((item->>'is_active')::boolean,true),
         nullif(item->>'custom_price_toman','')::bigint,
         nullif(item->>'custom_duration_minutes','')::integer,
         coalesce(item->>'notes','')
  from jsonb_array_elements(p_services) item;

  delete from public.employee_working_hours
    where business_id = p_business_id and employee_id = v_employee_id;
  insert into public.employee_working_hours (
    business_id, employee_id, weekday, starts_at, ends_at,
    break_starts_at, break_ends_at, is_active, valid_from, valid_until
  )
  select p_business_id, v_employee_id,
         (item->>'weekday')::smallint,
         (item->>'starts_at')::time,
         (item->>'ends_at')::time,
         nullif(item->>'break_starts_at','')::time,
         nullif(item->>'break_ends_at','')::time,
         coalesce((item->>'is_active')::boolean,true),
         nullif(item->>'valid_from','')::date,
         nullif(item->>'valid_until','')::date
  from jsonb_array_elements(p_working_hours) item;

  return v_employee_id;
end;
$$;

revoke all on function public.save_employee_profile(uuid,uuid,jsonb,jsonb,jsonb) from public, anon;
grant execute on function public.save_employee_profile(uuid,uuid,jsonb,jsonb,jsonb) to authenticated;
