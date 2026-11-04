begin;

do $$
begin
  if to_regprocedure('public.require_current_approved_device(uuid)') is null
     or to_regprocedure('public.require_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('reservations_private.has_event_permission(uuid,text,uuid)') is null
     or to_regclass('public.module_permission_catalog') is null
     or to_regclass('warehouse.stores') is null
     or to_regclass('reservations.events') is null then
    raise exception 'MODULE_PERMISSION_RESOURCE_ADMINISTRATION_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end;
$$;

create function public.list_module_permission_resources_for_administration(
  p_actor_device_id uuid,
  p_module_key text,
  p_resource_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','warehouse','reservations'
as $$
declare actor_id uuid;
begin
  actor_id:=public.require_current_approved_device(p_actor_device_id);
  if not exists(
    select 1 from public.platform_modules modules
    where modules.module_key=p_module_key and modules.status='active'
  ) then
    raise exception 'ACTIVE_MODULE_REQUIRED' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.module_permission_catalog catalog
    where catalog.module_key=p_module_key and catalog.status='active'
      and catalog.allowed_resource_type=p_resource_type
      and catalog.allowed_scope_mode in('resource','both')
  ) then
    raise exception 'MODULE_PERMISSION_RESOURCE_TYPE_NOT_ALLOWED' using errcode='42501';
  end if;
  if not public.is_system_owner(actor_id) then
    perform public.require_module_permission(
      p_actor_device_id,p_module_key,'module.manage',null,null
    );
  end if;

  if p_module_key='warehouse' and p_resource_type='store' then
    return coalesce((
      select jsonb_agg(jsonb_build_object(
        'resourceId',stores.id,'resourceType','store','code',stores.code,
        'name',stores.name,'displayName',stores.name,'status',stores.status
      ) order by stores.code,stores.id)
      from warehouse.stores stores
      where stores.status='active'
    ),'[]'::jsonb);
  elsif p_module_key='reservations' and p_resource_type='event' then
    return coalesce((
      select jsonb_agg(jsonb_build_object(
        'resourceId',events.id,'resourceType','event','code',null,
        'name',events.name,'displayName',events.name,'status',events.status
      ) order by events.start_date desc,events.name,events.id)
      from reservations.events events
      where reservations_private.has_event_permission(
        actor_id,'reservations.event.manage',events.id
      )
        and (
          (
            events.scope_type='standalone'
            and events.conference_id is null
            and events.organization_id is null
          )
          or (
            events.scope_type='conference'
            and exists(
              select 1
              from public.conferences conferences
              join public.organizations organizations
                on organizations.id=conferences.organization_id
               and organizations.status='active'
              join public.organization_members members
                on members.organization_id=conferences.organization_id
               and members.user_id=actor_id
              where conferences.id=events.conference_id
                and conferences.organization_id=events.organization_id
                and conferences.deleted_at is null
            )
          )
        )
    ),'[]'::jsonb);
  end if;

  raise exception 'MODULE_PERMISSION_RESOURCE_DISCOVERY_UNSUPPORTED' using errcode='42501';
end;
$$;

revoke all on function public.list_module_permission_resources_for_administration(uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.list_module_permission_resources_for_administration(uuid,text,text)
  to service_role;

alter function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  rename to execute_device_operation_pre_generic_permission_resource_administration;

create function platform.execute_device_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,
  p_module text,p_operation text,p_args jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','platform','platform_private'
as $$
declare session platform_private.device_sessions%rowtype;
begin
  if p_module<>'conference' or p_operation<>'list_module_permission_resources_for_administration' then
    return platform.execute_device_operation_pre_generic_permission_resource_administration(
      p_user_id,p_session_id,p_token_hash,p_module,p_operation,p_args
    );
  end if;
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_args is null or jsonb_typeof(p_args)<>'object'
     or p_args ?| array['organization_id','p_organization_id','scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then
    raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023';
  end if;

  select item.* into session
  from platform_private.device_sessions item
  join platform.device_key_bindings binding on binding.id=item.binding_id
  join platform.user_device_authorizations device_authorization on device_authorization.id=item.device_authorization_id
  join platform.devices device on device.id=item.device_id
  join platform.profiles profile on profile.user_id=item.user_id
  where item.id=p_session_id and item.user_id=p_user_id and item.token_hash=p_token_hash
    and item.purpose='PLATFORM_DEVICE_SESSION' and item.revoked_at is null
    and item.expires_at>statement_timestamp()
    and binding.user_id=item.user_id and binding.device_id=item.device_id
    and binding.device_authorization_id=item.device_authorization_id
    and binding.public_key_thumbprint=item.public_key_thumbprint
    and binding.algorithm='ECDSA_P256_SHA256' and binding.lifecycle_status='active'
    and binding.revoked_at is null and binding.retired_at is null
    and device_authorization.user_id=item.user_id and device_authorization.device_id=item.device_id
    and device_authorization.status='approved' and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved';
  if not found then
    raise exception 'DEVICE_SESSION_INVALID' using errcode='42501';
  end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user_id,'role','service_role')::text,true);
  perform set_config('platform.phase1c_context',jsonb_build_object(
    'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',session.id,
    'user_id',session.user_id,'device_id',session.device_id,
    'authorization_id',session.device_authorization_id,'binding_id',session.binding_id,
    'token_hash',encode(p_token_hash,'hex')
  )::text,true);
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key','p_resource_type']);
  return public.list_module_permission_resources_for_administration(
    session.device_id,p_args->>'p_module_key',p_args->>'p_resource_type'
  );
end;
$$;

revoke all on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb),
  platform.execute_device_operation_pre_generic_permission_resource_administration(uuid,uuid,bytea,text,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb),
  platform.execute_device_operation_pre_generic_permission_resource_administration(uuid,uuid,bytea,text,text,jsonb)
  to service_role;

commit;
