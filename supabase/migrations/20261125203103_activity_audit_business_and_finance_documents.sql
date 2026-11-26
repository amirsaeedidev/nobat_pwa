-- Cover business-root profile edits and financial document lifecycle events.
create or replace function public.capture_business_root_activity_event()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare
  v_row jsonb := case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_old jsonb := case when tg_op='INSERT' then null else to_jsonb(old) end;
  v_new jsonb := case when tg_op='DELETE' then null else to_jsonb(new) end;
  v_business_id uuid; v_actor_id uuid; v_actor_name text;
  v_id uuid := gen_random_uuid(); v_title text;
begin
  v_business_id := (v_row->>'id')::uuid;
  v_actor_id := coalesce(auth.uid(),(v_row->>'created_by')::uuid);
  if v_actor_id is null then raise exception 'ACTIVITY_AUDIT_CONTEXT_MISSING' using errcode='23502'; end if;
  if tg_op='UPDATE' and (v_old-'updated_at')=(v_new-'updated_at') then return new; end if;
  v_title := case tg_op when 'INSERT' then 'ایجاد مجموعه' when 'UPDATE' then 'تغییر مشخصات مجموعه' else 'حذف مجموعه' end;
  select coalesce(nullif(p.display_name,''),'کاربر') into v_actor_name from public.profiles p where p.id=v_actor_id;
  insert into public.business_activity_events (
    id,operation_id,business_id,actor_id,actor_name,source_table,entity_key_column,
    entity_type,entity_id,action,operation_type,type,title,description,before_state,after_state,is_reversible
  ) values (
    v_id,v_id,v_business_id,v_actor_id,coalesce(v_actor_name,'کاربر'),'businesses','id',
    'settings',v_business_id::text,lower(tg_op),'business_'||lower(tg_op),'settingsChanged',
    v_title,v_title||' | شناسه: '||v_business_id::text,v_old,v_new,false
  );
  return coalesce(new,old);
end;
$function$;
revoke all on function public.capture_business_root_activity_event() from public,anon,authenticated;
drop trigger if exists activity_audit_businesses on public.businesses;
create trigger activity_audit_businesses after insert or update or delete on public.businesses
for each row execute function public.capture_business_root_activity_event();

create or replace function public.capture_business_finance_document_activity_event()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare
  v_new jsonb := case when tg_op<>'DELETE' then to_jsonb(new) else null end;
  v_old jsonb := case when tg_op<>'INSERT' then to_jsonb(old) else null end;
  v_row jsonb := coalesce(v_new,v_old);
  v_business_id uuid := (v_row->>'business_id')::uuid;
  v_actor_id uuid := coalesce(auth.uid(),(v_row->>'created_by')::uuid,(v_row->>'voided_by')::uuid);
  v_actor_name text; v_id uuid := gen_random_uuid();
  v_action text := lower(tg_op); v_key text; v_title text;
begin
  if v_actor_id is null then raise exception 'ACTIVITY_AUDIT_CONTEXT_MISSING' using errcode='23502'; end if;
  if tg_op='UPDATE' and (v_old-'updated_at')=(v_new-'updated_at') then return new; end if;
  if tg_op='INSERT' then v_key := nullif(v_new->>'idempotency_key',''); end if;
  v_title := case tg_op when 'INSERT' then 'ثبت سند مالی مجموعه' when 'UPDATE' then 'تغییر سند مالی مجموعه' else 'حذف سند مالی مجموعه' end;
  select coalesce(nullif(p.display_name,''),'کاربر') into v_actor_name from public.profiles p where p.id=v_actor_id;
  insert into public.business_activity_events (
    id,operation_id,business_id,actor_id,actor_name,source_table,entity_key_column,
    entity_type,entity_id,action,operation_type,type,title,description,before_state,
    after_state,idempotency_key,is_reversible
  ) values (
    v_id,v_id,v_business_id,v_actor_id,coalesce(v_actor_name,'کاربر'),
    'business_finance_documents','id','finance',v_row->>'id',v_action,
    'financial_document_'||v_action,'settingsChanged',v_title,
    v_title||' | شناسه: '||coalesce(v_row->>'id',''),v_old,v_new,v_key,false
  ) on conflict do nothing;
  return coalesce(new,old);
end;
$function$;
revoke all on function public.capture_business_finance_document_activity_event() from public,anon,authenticated;
drop trigger if exists activity_audit_business_finance_documents on public.business_finance_documents;
create trigger activity_audit_business_finance_documents after insert or update or delete on public.business_finance_documents
for each row execute function public.capture_business_finance_document_activity_event();
