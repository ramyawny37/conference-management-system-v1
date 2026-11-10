begin;

do $$
begin
  if to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null then
    raise exception 'WAREHOUSE_EFFECTIVE_PERMISSION_REQUIRED' using errcode='55000';
  end if;
  if to_regprocedure('platform_private.is_canonical_platform_owner(uuid)') is null then
    raise exception 'CANONICAL_PLATFORM_OWNER_HELPER_REQUIRED' using errcode='55000';
  end if;
end $$;

create or replace function warehouse.list_permission_administration_stores(
 p_device_id uuid,p_include_inactive boolean default false
) returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','public','warehouse' as $$
declare actor_id uuid;
begin
 actor_id:=public.require_current_approved_device(p_device_id);
 if not platform_private.is_canonical_platform_owner(actor_id) then
  perform public.require_effective_module_permission(
   p_device_id,'warehouse','warehouse.module.manage',null,null);
 end if;
 return coalesce((
  select jsonb_agg(jsonb_build_object(
   'storeId',stores.id,'code',stores.code,'name',stores.name,'status',stores.status)
   order by stores.code,stores.id)
  from warehouse.stores stores
  where coalesce(p_include_inactive,false) or stores.status='active'
 ),'[]'::jsonb);
end $$;

revoke all on function warehouse.list_permission_administration_stores(uuid,boolean)
from public,anon,authenticated;
grant execute on function warehouse.list_permission_administration_stores(uuid,boolean)
to service_role;

do $$
declare v_def text;
begin
  select pg_get_functiondef(to_regprocedure('warehouse.list_permission_administration_stores(uuid,boolean)')) into v_def;
  if position('require_effective_module_permission' in v_def)=0
     or position('warehouse.module.manage' in v_def)=0
     or position('require_module_permission' in v_def)>0 then
    raise exception 'WAREHOUSE_PERMISSION_ADMINISTRATION_STORE_CUTOVER_FAILED' using errcode='55000';
  end if;
end $$;

commit;
