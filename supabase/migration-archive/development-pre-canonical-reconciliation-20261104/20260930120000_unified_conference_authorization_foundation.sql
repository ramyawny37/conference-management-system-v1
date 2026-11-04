begin;

do $$
begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.module_permission_grants') is null
     or to_regprocedure('public.require_current_approved_device(uuid)') is null
     or to_regprocedure('public.require_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('public.validate_module_permission_catalog(text,text,text,text,text)') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null then
    raise exception 'UNIFIED_CONFERENCE_AUTHORIZATION_FOUNDATION_REQUIRED'
      using errcode='55000';
  end if;
end $$;

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
set search_path = pg_catalog, public
as $$
declare
  actor_id uuid;
  catalog_context jsonb;
  matching_grant public.module_permission_grants%rowtype;
begin
  actor_id := public.require_current_approved_device(p_actor_device_id);
  catalog_context := public.validate_module_permission_catalog(
    p_module_key, p_permission_key, p_resource_type, p_resource_id, 'authorize'
  );

  if public.is_system_owner(actor_id) then
    return jsonb_build_object(
      'actorUserId', actor_id,
      'actorDeviceId', p_actor_device_id,
      'moduleKey', p_module_key,
      'permissionKey', p_permission_key,
      'resourceType', p_resource_type,
      'resourceId', p_resource_id,
      'authoritySource', 'system_owner',
      'grantId', null,
      'catalogVersion', (catalog_context ->> 'catalogVersion')::integer
    );
  end if;

  perform public.require_module_permission(
    p_actor_device_id, p_module_key, 'module.access', null, null
  );

  if p_module_key='conference'
     and p_resource_type='conference'
     and p_resource_id is not null
     and p_resource_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     and exists(
       select 1 from public.conferences conference
       where conference.id=p_resource_id::uuid
         and conference.owner_id=actor_id
     ) then
    return jsonb_build_object(
      'actorUserId', actor_id,
      'actorDeviceId', p_actor_device_id,
      'moduleKey', p_module_key,
      'permissionKey', p_permission_key,
      'resourceType', p_resource_type,
      'resourceId', p_resource_id,
      'authoritySource', 'conference_owner',
      'grantId', null,
      'catalogVersion', (catalog_context ->> 'catalogVersion')::integer
    );
  end if;

  matching_grant := null;
  if p_resource_type is not null then
    select * into matching_grant
      from public.module_permission_grants as grants
     where grants.user_id = actor_id
       and grants.module_key = p_module_key
       and grants.permission_key = p_permission_key
       and grants.resource_type = p_resource_type
       and grants.resource_id = p_resource_id
       and grants.revoked_at is null
     limit 1;
  end if;

  if matching_grant.grant_id is null then
    select * into matching_grant
      from public.module_permission_grants as grants
     where grants.user_id = actor_id
       and grants.module_key = p_module_key
       and grants.permission_key = p_permission_key
       and grants.resource_type is null
       and grants.resource_id is null
       and grants.revoked_at is null
     limit 1;
  end if;

  if matching_grant.grant_id is null then
    raise exception 'MODULE_PERMISSION_REQUIRED' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'actorUserId', actor_id,
    'actorDeviceId', p_actor_device_id,
    'moduleKey', p_module_key,
    'permissionKey', p_permission_key,
    'resourceType', p_resource_type,
    'resourceId', p_resource_id,
    'authoritySource', case
      when matching_grant.resource_type is null then 'module_grant'
      else 'resource_grant'
    end,
    'grantId', matching_grant.grant_id,
    'catalogVersion', (catalog_context ->> 'catalogVersion')::integer
  );
end;
$$;

comment on function public.require_effective_module_permission(uuid,text,text,text,text) is
'Canonical Platform effective permission resolver. Conference resource ownership is inherited only from public.conferences.owner_id after approved-device and module-access admission; Conference membership roles and participations have no authorization meaning.';

commit;
