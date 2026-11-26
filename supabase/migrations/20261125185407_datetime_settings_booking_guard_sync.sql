-- Keep the current booking-slot validation path in sync with the canonical
-- business_settings row, and mirror dated closures to business_holidays.
create or replace function public.save_business_settings(
  p_business_id uuid,
  p_name text,
  p_settings jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_weekly_holidays jsonb;
  v_schedule_exceptions jsonb;
begin
  if p_business_id is null
     or p_name is null
     or length(btrim(p_name)) not between 1 and 160
     or p_settings is null
     or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'Invalid business settings payload';
  end if;

  v_weekly_holidays := coalesce(p_settings->'weekly_holidays', '[]'::jsonb);
  v_schedule_exceptions := coalesce(p_settings->'schedule_exceptions', '[]'::jsonb);
  if jsonb_typeof(v_weekly_holidays) <> 'array'
     or jsonb_typeof(v_schedule_exceptions) <> 'array' then
    raise exception 'Invalid business schedule settings';
  end if;

  update public.businesses
     set name = btrim(p_name),
         updated_at = now()
   where id = p_business_id;

  if not found then
    raise exception 'Business not found or update is not permitted';
  end if;

  insert into public.business_settings (
    business_id, settings, created_by, updated_by, created_at, updated_at
  ) values (
    p_business_id, p_settings, (select auth.uid()), (select auth.uid()), now(), now()
  )
  on conflict (business_id) do update
    set settings = excluded.settings,
        updated_by = (select auth.uid()),
        updated_at = now();

  -- The current slot guard reads weekly holidays from this legacy record.
  insert into public.app_records (
    business_id, entity_type, record_id, payload, created_by, updated_by
  ) values (
    p_business_id, 'settings', 'business_settings',
    jsonb_build_object('holidays', v_weekly_holidays),
    (select auth.uid()), (select auth.uid())
  )
  on conflict (business_id, entity_type, record_id) do update
    set payload = jsonb_set(
          coalesce(public.app_records.payload, '{}'::jsonb),
          '{holidays}',
          v_weekly_holidays,
          true
        ),
        updated_by = (select auth.uid()),
        updated_at = now();

  -- The current slot guard checks dated closures in business_holidays.
  delete from public.business_holidays
   where business_id = p_business_id;

  insert into public.business_holidays (
    business_id, holiday_date, title, created_by
  )
  select
    p_business_id,
    (item->>'date_key')::date,
    coalesce(nullif(btrim(item->>'title'), ''), 'تعطیلی مجموعه'),
    (select auth.uid())
  from jsonb_array_elements(v_schedule_exceptions) as item
  where coalesce((item->>'is_closed')::boolean, true)
    and coalesce(item->>'date_key', '') ~ '^\d{4}-\d{2}-\d{2}$';
end;
$function$;

revoke all on function public.save_business_settings(uuid, text, jsonb) from public, anon;
grant execute on function public.save_business_settings(uuid, text, jsonb) to authenticated;
