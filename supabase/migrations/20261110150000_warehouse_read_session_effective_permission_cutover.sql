begin;

do $$
begin
  if to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null then
    raise exception 'EFFECTIVE_MODULE_PERMISSION_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end;
$$;

create or replace function warehouse_private.require_read_session(p_device_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $$
declare
  context jsonb;
begin
  context := public.require_effective_module_permission(
    p_device_id,
    'warehouse',
    'warehouse.module.access',
    null,
    null
  );
  return (context->>'actorUserId')::uuid;
end;
$$;


do $$
declare
  body text;
begin
  select pg_get_functiondef(p.oid)
  into body
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='warehouse_private'
    and p.proname='require_read_session'
    and pg_get_function_identity_arguments(p.oid)='p_device_id uuid';

  if body is null
     or body not like '%public.require_effective_module_permission(%'
     or body like '%public.require_module_permission(%' then
    raise exception 'WAREHOUSE_READ_SESSION_CANONICAL_PERMISSION_CUTOVER_FAILED' using errcode='55000';
  end if;
end;
$$;

commit;
