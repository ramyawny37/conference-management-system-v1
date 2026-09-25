-- Complete the existing Reservations capability contract at the canonical
-- Platform transport boundary. Business authorization remains Reservations-owned.
create or replace function platform.execute_device_operation(
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
  if p_module='reservations'
     and p_operation in ('get_effective_capabilities','update_participant_booking') then
    if coalesce(auth.jwt()->>'role','')<>'service_role' then
      raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501';
    end if;
    if p_args is null or jsonb_typeof(p_args)<>'object'
       or p_args ?| array['organization_id','p_organization_id','scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id','p_conference_person_id','conference_person_id'] then
      raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023';
    end if;
    if p_operation='update_participant_booking' then
      perform platform_private.require_exact_jsonb_keys(p_args,array[
        'p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id',
        'p_full_name','p_phone','p_age','p_church','p_governorate',
        'p_city_or_village','p_service_sector','p_service_sector_other','p_notes'
      ]);
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
    if p_operation='get_effective_capabilities' then
      return reservations.read(session.device_id,p_operation,p_args);
    end if;
    return reservations_private.mutate_scoped(session.device_id,p_operation,p_args);
  end if;

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

revoke all on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  to service_role;
