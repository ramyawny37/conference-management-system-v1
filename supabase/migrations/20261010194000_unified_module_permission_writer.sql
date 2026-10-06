begin;
create or replace function public.manage_catalog_module_grant(
 p_actor_device_id uuid,p_operation_id uuid,p_action text,p_target_user_id uuid,
 p_module_key text,p_permission_key text,p_resource_type text default null,p_resource_id text default null,
 p_grant_id uuid default null,p_revocation_reason text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid;g uuid;expected_code text;
begin
 if p_operation_id is null or p_target_user_id is null or p_module_key not in('conference','warehouse','reservations') or p_action not in('grant','revoke','create') then raise exception 'INVALID_MODULE_GRANT_OPERATION' using errcode='22023'; end if;
 expected_code:=p_module_key||'.module.manage';
 a:=public.require_current_approved_device(p_actor_device_id);
 if p_permission_key=expected_code then
  if not platform_private.is_canonical_platform_owner(a) then raise exception 'PLATFORM_OWNER_REQUIRED' using errcode='42501'; end if;
 else
  if not platform_private.is_canonical_platform_owner(a) then perform public.require_effective_module_permission(p_actor_device_id,p_module_key,expected_code,null,null); end if;
 end if;
 if p_action in('grant','create') then
  if p_grant_id is not null then raise exception 'INVALID_MODULE_GRANT_OPERATION' using errcode='22023'; end if;
  g:=platform_private.create_permission_grant(a,p_actor_device_id,p_target_user_id,p_module_key,p_permission_key,p_resource_type,p_resource_id,p_operation_id);
 else
  select x.id into g from platform.permission_grants x join platform.permissions p on p.id=x.permission_id
  where x.id=p_grant_id and x.user_id=p_target_user_id and p.domain=p_module_key and p.code=p_permission_key
  and x.resource_type is not distinct from p_resource_type and x.resource_id is not distinct from p_resource_id;
  if g is null then raise exception 'PERMISSION_GRANT_NOT_FOUND_OR_STALE' using errcode='P0002'; end if;
  perform platform_private.revoke_permission_grant(a,p_actor_device_id,g,p_revocation_reason);
 end if;
 return jsonb_build_object('status',case when p_action='revoke' then 'revoked' else 'applied' end,'grantId',g,'targetUserId',p_target_user_id,'moduleKey',p_module_key,'permissionKey',p_permission_key,'resourceType',p_resource_type,'resourceId',p_resource_id);
end $$;
commit;