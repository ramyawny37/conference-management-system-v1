-- Flatten active platform dispatchers after Organization retirement.
CREATE OR REPLACE FUNCTION platform.execute_conference_device_operation_phase1c_core(p_user_id uuid, p_session_id uuid, p_token_hash bytea, p_operation text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'platform', 'platform_private'
AS $function$
declare v_session platform_private.device_sessions%rowtype; v_result jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'CONFERENCE_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_user_id is null or p_session_id is null or octet_length(p_token_hash)<>32 then
    raise exception 'DEVICE_SESSION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select session.* into v_session from platform_private.device_sessions session
  join platform.device_key_bindings binding on binding.id=session.binding_id
  join platform.user_device_authorizations device_authorization
    on device_authorization.id=session.device_authorization_id
  join platform.devices device on device.id=session.device_id
  join platform.profiles profile on profile.user_id=session.user_id
  where session.id=p_session_id and session.user_id=p_user_id
    and session.token_hash=p_token_hash
    and session.revoked_at is null and session.expires_at>statement_timestamp()
    and binding.user_id=session.user_id and binding.device_id=session.device_id
    and binding.device_authorization_id=session.device_authorization_id
    and binding.public_key_thumbprint=session.public_key_thumbprint
    and binding.lifecycle_status='active' and binding.revoked_at is null
    and binding.retired_at is null
    and device_authorization.user_id=session.user_id
    and device_authorization.device_id=session.device_id
    and device_authorization.status='approved'
    and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved';
  if not found then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501'; end if;
  if p_args ? 'p_actor_device_id'
     or (p_args ? 'p_device_id' and p_operation<>'approve_pending_device_authorization') then
    raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='22023';
  end if;
  perform set_config('platform.phase1c_context',jsonb_build_object(
    'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',v_session.id,
    'user_id',v_session.user_id,'device_id',v_session.device_id,
    'authorization_id',v_session.device_authorization_id,
    'binding_id',v_session.binding_id,'token_hash',encode(p_token_hash,'hex'))::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',p_user_id,'role','authenticated')::text,true);

  case p_operation

  when 'get_user_management_actor_capabilities' then
    perform platform_private.require_exact_jsonb_keys(p_args,'{}');
    v_result:=public.get_user_management_actor_capabilities(v_session.device_id);
  when 'search_user_management_users' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_query','p_account_status','p_limit']);
    v_result:=public.search_user_management_users(v_session.device_id,p_args->>'p_query',p_args->>'p_account_status',(p_args->>'p_limit')::integer);
  when 'get_user_management_overview' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
    v_result:=public.get_user_management_overview(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
  when 'get_user_management_devices' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
    v_result:=public.get_user_management_devices(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
  when 'get_user_management_account' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
    v_result:=public.get_user_management_account(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
  when 'device_guarded_manage_system_user' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id','p_operation_id','p_action'],array['p_requested_value']);
    v_result:=public.device_guarded_manage_system_user(v_session.device_id,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',case when p_args ? 'p_requested_value' then (p_args->>'p_requested_value')::boolean else null end);

  when 'list_pending_device_authorizations' then
    perform platform_private.require_exact_jsonb_keys(p_args,'{}');
    v_result:=platform.list_pending_device_authorizations();
  when 'approve_pending_device_authorization' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_authorization_id','p_device_id','p_reason']);
    v_result:=platform.approve_pending_device_authorization((p_args->>'p_authorization_id')::uuid,(p_args->>'p_device_id')::uuid,p_args->>'p_reason');

  when 'apply_library_template_content_operation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_template_type','p_template_id','p_action','p_base_revision','p_payload']);
    v_result:=public.apply_library_template_content_operation(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_template_type',p_args->>'p_template_id',p_args->>'p_action',(p_args->>'p_base_revision')::bigint,p_args->'p_payload');

  when 'list_module_permission_grants' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key','p_target_user_id']);
    v_result:=public.list_module_permission_grants(v_session.device_id,p_args->>'p_module_key',(p_args->>'p_target_user_id')::uuid);
  when 'manage_foundation_module_grant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_action','p_target_user_id','p_module_key','p_permission_key','p_grant_id','p_revocation_reason']);
    v_result:=public.manage_foundation_module_grant(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',(p_args->>'p_target_user_id')::uuid,p_args->>'p_module_key',p_args->>'p_permission_key',(p_args->>'p_grant_id')::uuid,p_args->>'p_revocation_reason');
  when 'recover_revoke_final_module_manager' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_module_key','p_target_user_id','p_target_grant_id','p_recovery_reason']);
    v_result:=public.recover_revoke_final_module_manager(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_module_key',(p_args->>'p_target_user_id')::uuid,(p_args->>'p_target_grant_id')::uuid,p_args->>'p_recovery_reason');
  when 'acquire_conference_lock','renew_conference_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_lock_token','p_ttl_seconds']);
    if p_operation='acquire_conference_lock' then v_result:=public.device_guarded_acquire_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer);
    else v_result:=public.device_guarded_renew_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer); end if;
  when 'release_conference_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_lock_token']);
    v_result:=public.device_guarded_release_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_lock_token')::uuid);
  when 'get_conference_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    v_result:=public.device_guarded_get_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid);
  when 'acquire_conference_section_lock','renew_conference_section_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_section','p_lock_token','p_ttl_seconds']);
    if p_operation='acquire_conference_section_lock' then v_result:=public.acquire_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer);
    else v_result:=public.renew_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer); end if;
  when 'release_conference_section_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_section','p_lock_token']);
    v_result:=public.release_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id,(p_args->>'p_lock_token')::uuid);
  when 'get_conference_section_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_section']);
    v_result:=public.get_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id);
  when 'mutate_conference_core' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_expected_revision','p_name','p_start_date','p_end_date','p_status']); v_result:=public.mutate_conference_core(v_session.device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_name',(p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,p_args->>'p_status'); else raise exception 'CONFERENCE_OPERATION_NOT_ALLOWED' using errcode='42501';
  end case;
  return v_result;
end $function$
;

CREATE OR REPLACE FUNCTION platform.execute_device_operation(p_user_id uuid, p_session_id uuid, p_token_hash bytea, p_module text, p_operation text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'platform', 'platform_private'
AS $function$
declare session platform_private.device_sessions%rowtype;
begin
  if p_module='platform' then
    if p_operation='list_module_permission_resources_for_administration' then
      -- Keep this newer administration operation on its current hardened dispatcher until flattening.
      return platform.execute_device_operation_pre_generic_permission_resource_administration(
        p_user_id,p_session_id,p_token_hash,'conference',p_operation,p_args
      );
    end if;
    return platform.execute_conference_device_operation_phase1c_core(
      p_user_id,p_session_id,p_token_hash,p_operation,p_args
    );
  end if;

  if p_module='conference' then
    return platform.execute_conference_device_operation(
      p_user_id,p_session_id,p_token_hash,p_operation,p_args
    );
  end if;

  if p_module='reservations'
     and p_operation in ('get_effective_capabilities','update_participant_booking') then
    if coalesce(auth.jwt()->>'role','')<>'service_role' then
      raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501';
    end if;
    if p_args is null or jsonb_typeof(p_args)<>'object'
       or p_args ?| array['scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id','p_conference_person_id','conference_person_id'] then
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
     or p_args ?| array['scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then
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
$function$
;
