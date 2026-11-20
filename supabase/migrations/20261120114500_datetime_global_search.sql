-- Permission-aware, tenant-scoped server search for DateTime.
-- SECURITY INVOKER is intentional: app_records RLS remains the final access boundary.
create or replace function public.search_app_records(
  p_business_id uuid,
  p_entity_type text,
  p_query text,
  p_limit integer default 60
)
returns table (
  record_id text,
  payload jsonb,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  with normalized_query as (
    select translate(
      replace(lower(trim(coalesce(p_query, ''))), chr(8204), ''),
      'يىك٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹أإٱةۀ',
      'ییک01234567890123456789اااهه'
    ) as value
  ),
  candidates as (
    select
      r.record_id,
      r.payload,
      r.created_at,
      translate(
        replace(lower(r.record_id || ' ' || r.payload::text), chr(8204), ''),
        'يىك٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹أإٱةۀ',
        'ییک01234567890123456789اااهه'
      ) as normalized_content
    from public.app_records r
    where r.business_id = p_business_id
      and r.entity_type = p_entity_type
  )
  select c.record_id, c.payload, c.created_at
  from candidates c
  cross join normalized_query q
  where q.value <> ''
    and not exists (
      select 1
      from unnest(string_to_array(q.value, ' ')) as term
      where term <> ''
        and c.normalized_content not like '%' || term || '%'
    )
  order by c.created_at desc
  limit least(greatest(coalesce(p_limit, 60), 1), 100);
$$;

grant execute on function public.search_app_records(uuid, text, text, integer)
  to authenticated;
