begin;

create or replace function public.require_effective_module_permission(
  p_actor_device_id uuid,
  p_module_key text,
  p_permission_key text,
  p_resource_type text default null,
  p_resource_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid;
  v_permission platform.permissions%rowtype;
  v_grant platform.permission_grants%rowtype;
  v_requested_scope text;
begin
  v_actor:=public.require_current_approved_device(p_actor_device_id);
  if p_module_key not in ('conference','warehouse','reservations')
     or p_permission_key is null
     or split_part(p_permission_key,'.',1)<>p_module_key
     or ((p_resource_type is null)<>(p_resource_id is null)) then
    raise exception 'INVALID_MODULE_PERMISSION_REQUEST' using errcode='22023';
  end if;

  select * into v_permission
  from platform.permissions permission
  where permission.code=p_permission_key
    and permission.domain=p_module_key
    and permission.status='active';
  if not found then
    raise exception 'ACTIVE_MODULE_PERMISSION_REQUIRED' using errcode='42501';
  end if;

  v_requested_scope:=case when p_resource_type is null then 'module' else 'resource' end;
  if v_requested_scope='module' and v_permission.allowed_scope_mode not in ('module','both') then
    raise exception 'MODULE_PERMISSION_SCOPE_NOT_ALLOWED' using errcode='42501';
  end if;
  if v_requested_scope='resource' and (
      v_permission.allowed_scope_mode not in ('resource','both')
      or v_permission.allowed_resource_type<>p_resource_type
      or p_resource_id is null or length(p_resource_id) not between 1 and 255
      or p_resource_id<>btrim(p_resource_id)
  ) then
    raise exception 'MODULE_PERMISSION_RESOURCE_TYPE_INVALID' using errcode='42501';
  end if;

  if platform_private.is_canonical_platform_owner(v_actor) then
    return jsonb_build_object(
      'actorUserId',v_actor,'actorDeviceId',p_actor_device_id,
      'moduleKey',p_module_key,'permissionKey',p_permission_key,
      'resourceType',p_resource_type,'resourceId',p_resource_id,
      'authoritySource','platform_owner','grantId',null
    );
  end if;

  if v_requested_scope='resource' then
    select grants.* into v_grant
    from platform.permission_grants grants
    where grants.user_id=v_actor and grants.permission_id=v_permission.id
      and grants.scope_type='resource'
      and grants.resource_type=p_resource_type and grants.resource_id=p_resource_id
      and grants.revoked_at is null
    limit 1;
  end if;
  if v_grant.id is null and v_permission.allowed_scope_mode in ('module','both') then
    select grants.* into v_grant
    from platform.permission_grants grants
    where grants.user_id=v_actor and grants.permission_id=v_permission.id
      and grants.scope_type='module'
      and grants.resource_type is null and grants.resource_id is null
      and grants.revoked_at is null
    limit 1;
  end if;
  if v_grant.id is null then
    raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501';
  end if;

  return jsonb_build_object(
    'actorUserId',v_actor,'actorDeviceId',p_actor_device_id,
    'moduleKey',p_module_key,'permissionKey',p_permission_key,
    'resourceType',p_resource_type,'resourceId',p_resource_id,
    'authoritySource',case when v_grant.scope_type='module' then 'module_grant' else 'resource_grant' end,
    'grantId',v_grant.id
  );
end;
$$;

revoke all on function public.require_effective_module_permission(uuid,text,text,text,text)
from public,anon,authenticated,service_role;

commit;