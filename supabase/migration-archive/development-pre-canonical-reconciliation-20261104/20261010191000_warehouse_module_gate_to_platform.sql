begin;
create or replace function warehouse_private.require_read_session(p_device_id uuid)
returns uuid language plpgsql stable security definer
set search_path='pg_catalog','public' as $$
declare context jsonb;
begin
 context:=public.require_effective_module_permission(
  p_device_id,'warehouse','warehouse.module.access',null,null);
 return (context->>'actorUserId')::uuid;
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

revoke all on function warehouse_private.require_read_session(uuid) from public,anon,authenticated,service_role;
revoke all on function warehouse.list_permission_administration_stores(uuid,boolean) from public,anon,authenticated;
grant execute on function warehouse_private.require_read_session(uuid) to service_role;
grant execute on function warehouse.list_permission_administration_stores(uuid,boolean) to service_role;
commit;