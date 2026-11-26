-- Keep employee-specific commission values behind financial/service-management RLS.
create table if not exists public.employee_service_compensation (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  employee_id uuid not null,
  service_id uuid not null,
  commission_rate_bps integer check (commission_rate_bps between 0 and 10000),
  fixed_commission_amount_toman bigint check (fixed_commission_amount_toman >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,employee_id,service_id),
  foreign key (business_id,employee_id,service_id)
    references public.employee_services(business_id,employee_id,service_id)
    on delete cascade
);

insert into public.employee_service_compensation(
  business_id,employee_id,service_id,commission_rate_bps,fixed_commission_amount_toman
)
select business_id,employee_id,service_id,commission_rate_bps,fixed_commission_amount_toman
from public.employee_services
where commission_rate_bps is not null or fixed_commission_amount_toman is not null
on conflict (business_id,employee_id,service_id) do update set
  commission_rate_bps=excluded.commission_rate_bps,
  fixed_commission_amount_toman=excluded.fixed_commission_amount_toman;

alter table public.employee_service_compensation enable row level security;
grant select,insert,update on public.employee_service_compensation to authenticated;
revoke delete on public.employee_service_compensation from anon,authenticated;

create policy employee_service_compensation_read on public.employee_service_compensation
for select to authenticated
using (
  private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'finance.manage')
  or (
    employee_id=private.current_employee_id(business_id)
    and private.has_business_permission(business_id,'finance.wallet.view_self')
  )
);
create policy employee_service_compensation_write on public.employee_service_compensation
for all to authenticated
using (
  private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'finance.manage')
)
with check (
  private.has_business_permission(business_id,'services.manage')
  or private.has_business_permission(business_id,'employees.services.manage')
  or private.has_business_permission(business_id,'finance.manage')
);

drop policy if exists employee_services_read_scoped on public.employee_services;
create policy employee_services_read_scoped on public.employee_services
for select to authenticated
using (
  private.has_business_permission(business_id,'employees.services.view')
  or private.has_business_permission(business_id,'services.manage')
  or employee_id=private.current_employee_id(business_id)
);

alter table public.employee_services
  drop constraint if exists employee_services_commission_rate_valid_check,
  drop constraint if exists employee_services_fixed_commission_valid_check,
  drop column if exists commission_rate_bps,
  drop column if exists fixed_commission_amount_toman;

do $$
declare
  v_definition text;
  v_updated text;
  v_old text;
  v_new text;
begin
  v_definition := pg_get_functiondef(
    'public.save_service_catalog_item(uuid,uuid,jsonb,jsonb)'::regprocedure
  );

  v_old := 'custom_duration_minutes,commission_rate_bps,';
  v_new := 'custom_duration_minutes,';
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not update service config insert columns'; end if;
  v_definition := v_updated;

  v_old := 'nullif(cfg->>''custom_duration_minutes'','''')::integer,';
  v_new := 'nullif(cfg->>''custom_duration_minutes'','''')::integer,';
  -- Keep custom duration intact; remove the commission values from the base relationship row.
  v_old := 'nullif(cfg->>''commission_rate_bps'','''')::integer,';
  v_updated := replace(v_definition,v_old,'');
  if v_updated=v_definition then raise exception 'Could not remove commission select from employee_services insert'; end if;
  v_definition := v_updated;

  v_old := '    commission_rate_bps = excluded.commission_rate_bps,';
  v_updated := replace(v_definition,v_old,'');
  if v_updated=v_definition then raise exception 'Could not remove commission conflict assignment'; end if;
  v_definition := v_updated;

  v_old := '    fixed_commission_amount_toman = excluded.fixed_commission_amount_toman,';
  v_updated := replace(v_definition,v_old,'');
  if v_updated=v_definition then raise exception 'Could not remove fixed commission conflict assignment'; end if;
  v_definition := v_updated;

  v_old := 'nullif(cfg->>''fixed_commission_amount_toman'','''')::bigint,';
  v_updated := replace(v_definition,v_old,'');
  if v_updated=v_definition then raise exception 'Could not remove fixed commission insert value'; end if;
  v_definition := v_updated;

  v_old := '  return v_service_id;';
  v_new := $insert$  insert into public.employee_service_compensation(
    business_id,employee_id,service_id,commission_rate_bps,fixed_commission_amount_toman
  )
  select p_business_id,(cfg->>'employee_id')::uuid,v_service_id,
    nullif(cfg->>'commission_rate_bps','')::integer,
    nullif(cfg->>'fixed_commission_amount_toman','')::bigint
  from jsonb_array_elements(p_employee_configs) cfg
  where nullif(cfg->>'commission_rate_bps','') is not null
     or nullif(cfg->>'fixed_commission_amount_toman','') is not null
  on conflict (business_id,employee_id,service_id) do update set
    commission_rate_bps=excluded.commission_rate_bps,
    fixed_commission_amount_toman=excluded.fixed_commission_amount_toman;

  return v_service_id;$insert$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not append employee service compensation persistence'; end if;
  execute v_updated;
end;
$$;
