begin;

-- Canonical runtime authority is Platform device authorization plus its active
-- cryptographic binding. Legacy public device rows remain historical only.
create or replace function platform_private.require_canonical_device_authorization(
  p_user_id uuid,p_device_id uuid,p_require_active_binding boolean default true
) returns uuid language plpgsql stable security definer set search_path='' as $$
declare v_authorization_id uuid;
begin
  if p_user_id is null or p_device_id is null then
    raise exception 'PLATFORM_DEVICE_ACTOR_CONTEXT_REQUIRED' using errcode='22023';
  end if;
  select device_authorization.id into v_authorization_id
  from platform.user_device_authorizations device_authorization
  join platform.devices device on device.id=device_authorization.device_id
  join platform.profiles profile on profile.user_id=device_authorization.user_id
  where device_authorization.user_id=p_user_id and device_authorization.device_id=p_device_id
    and device_authorization.status='approved' and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved'
    and (not p_require_active_binding or exists(
      select 1 from platform.device_key_bindings binding
      where binding.user_id=device_authorization.user_id
        and binding.device_id=device_authorization.device_id
        and binding.device_authorization_id=device_authorization.id
        and binding.lifecycle_status='active' and binding.revoked_at is null
        and binding.retired_at is null
    ));
  if v_authorization_id is null then
    raise exception 'APPROVED_PLATFORM_DEVICE_REQUIRED' using errcode='42501';
  end if;
  return v_authorization_id;
end; $$;
revoke all on function platform_private.require_canonical_device_authorization(uuid,uuid,boolean)
  from public,anon,authenticated,service_role;

create or replace function platform_private.is_canonical_platform_owner(p_user_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from platform.profiles profile
    join platform.user_roles assignment on assignment.user_id=profile.user_id
    join platform.roles role on role.id=assignment.role_id
    where profile.user_id=p_user_id and profile.account_status='approved'
      and assignment.scope_type='platform' and assignment.scope_id is null
      and assignment.revoked_at is null
      and (assignment.expires_at is null or assignment.expires_at>pg_catalog.statement_timestamp())
      and role.domain='platform' and role.code='platform_owner'
  );
$$;
revoke all on function platform_private.is_canonical_platform_owner(uuid)
  from public,anon,authenticated,service_role;

-- Privileged history predating canonical Platform authority remains truthful
-- historical provenance. It must not be backfilled or reclassified. Each
-- explicitly NOT VALID constraint below is prospective enforcement for new or
-- changed rows; historical validation is intentionally deferred unless a
-- separately reviewed archival reconciliation is designed.
alter table public.device_security_credentials
  drop constraint device_security_credentials_authorization_fk,
  -- Historical credentials predate canonical Platform authority; no backfill or
  -- reclassification is permitted. Enforce prospectively without validation.
  add constraint device_security_credentials_platform_authorization_fk
    foreign key(user_id,device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid;
alter table public.device_possession_challenges
  drop constraint device_possession_challenges_actor_authorization_fk,
  drop constraint device_possession_challenges_target_authorization_fk,
  drop constraint device_possession_challenges_replaced_authorization_fk,
  drop constraint device_possession_challenges_replacement_authorization_fk,
  -- Historical actor challenges predate canonical Platform authority; no
  -- backfill or reclassification is permitted. Enforce prospectively only.
  add constraint device_possession_challenges_actor_platform_authorization_fk
    foreign key(user_id,actor_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  -- Historical target challenges predate canonical Platform authority; no
  -- backfill or reclassification is permitted. Enforce prospectively only.
  add constraint device_possession_challenges_target_platform_authorization_fk
    foreign key(target_user_id,target_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  add constraint device_possession_challenges_replaced_platform_authorization_fk
    foreign key(target_user_id,replaced_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict,
  add constraint device_possession_challenges_replacement_platform_authorization_fk
    foreign key(target_user_id,replacement_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict;
alter table public.system_owner_device_authorization_operations
  drop constraint system_owner_device_operations_actor_authorization_fk,
  drop constraint system_owner_device_operations_target_authorization_fk,
  drop constraint system_owner_device_operations_replaced_authorization_fk,
  drop constraint system_owner_device_operations_replacement_authorization_fk,
  -- Historical operation actors predate canonical Platform authority; no
  -- backfill or reclassification is permitted. Enforce prospectively only.
  add constraint system_owner_device_operations_actor_platform_authorization_fk
    foreign key(actor_user_id_snapshot,actor_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  -- Historical operation targets predate canonical Platform authority; no
  -- backfill or reclassification is permitted. Enforce prospectively only.
  add constraint system_owner_device_operations_target_platform_authorization_fk
    foreign key(target_user_id_snapshot,target_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  add constraint system_owner_device_operations_replaced_platform_authorization_fk
    foreign key(target_user_id_snapshot,replaced_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict,
  add constraint system_owner_device_operations_replacement_platform_authorization_fk
    foreign key(target_user_id_snapshot,replacement_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict;
alter table public.privileged_device_authorization_audit_log
  drop constraint privileged_device_audit_actor_authorization_fk,
  drop constraint privileged_device_audit_target_authorization_fk,
  drop constraint privileged_device_audit_replaced_authorization_fk,
  drop constraint privileged_device_audit_replacement_authorization_fk,
  -- Historical audit actors predate canonical Platform authority; no backfill
  -- or reclassification is permitted. Enforce prospectively only.
  add constraint privileged_device_audit_actor_platform_authorization_fk
    foreign key(actor_user_id_snapshot,actor_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  -- Historical audit targets predate canonical Platform authority; no backfill
  -- or reclassification is permitted. Enforce prospectively only.
  add constraint privileged_device_audit_target_platform_authorization_fk
    foreign key(target_user_id_snapshot,target_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  add constraint privileged_device_audit_replaced_platform_authorization_fk
    foreign key(target_user_id_snapshot,replaced_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict,
  add constraint privileged_device_audit_replacement_platform_authorization_fk
    foreign key(target_user_id_snapshot,replacement_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict;
alter table public.system_owner_credential_bootstrap_authorizations
  drop constraint system_owner_credential_bootstrap_device_fk,
  -- Historical bootstrap grants predate canonical Platform authority; no
  -- backfill or reclassification is permitted. Enforce prospectively only.
  add constraint system_owner_credential_bootstrap_platform_device_fk
    foreign key(intended_user_id,intended_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid;
alter table public.system_owner_credential_recovery_authorizations
  drop constraint system_owner_credential_recovery_device_fk,
  add constraint system_owner_credential_recovery_platform_device_fk
    foreign key(intended_user_id,intended_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict;

create or replace function platform_private.resolve_startup_device_authorization_status(
  p_user_id uuid,p_device_id uuid
) returns text language sql stable security definer set search_path='' as $$
  select device_authorization.status
  from platform.user_device_authorizations device_authorization
  join platform.devices device on device.id=device_authorization.device_id
  where device_authorization.user_id=p_user_id and device_authorization.device_id=p_device_id
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null;
$$;
revoke all on function platform_private.resolve_startup_device_authorization_status(uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function public.require_current_approved_device(p_actor_device_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare current_user_id uuid:=auth.uid(); platform_authorization_id uuid;
begin
  if current_user_id is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_actor_device_id is null then raise exception 'DEVICE_REQUIRED' using errcode='22023'; end if;
  platform_authorization_id:=platform_private.validated_phase1c_device_authorization(
    current_user_id,p_actor_device_id);
  if platform_authorization_id is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  perform platform_private.require_canonical_device_authorization(
    current_user_id,p_actor_device_id,true);
  return current_user_id;
end; $$;
revoke all on function public.require_current_approved_device(uuid)
  from public,anon,authenticated,service_role;

create or replace function public.require_system_owner_webauthn_actor(
  p_actor_user_id uuid,p_actor_device_id uuid,p_credential_id uuid
) returns public.device_security_credentials language plpgsql security definer
set search_path='' as $$
declare credential public.device_security_credentials%rowtype;
begin
  perform public.require_platform_device_backend();
  if not platform_private.is_canonical_platform_owner(p_actor_user_id) then
    raise exception 'APPROVED_SYSTEM_OWNER_REQUIRED' using errcode='42501';
  end if;
  perform platform_private.require_canonical_device_authorization(
    p_actor_user_id,p_actor_device_id,true);
  select * into credential from public.device_security_credentials stored
  where stored.id=p_credential_id and stored.user_id=p_actor_user_id
    and stored.device_id=p_actor_device_id and stored.credential_kind='platform_primary'
    and stored.lifecycle_status='active' and stored.backup_eligible=false
    and stored.backup_state=false and stored.user_verification_policy='required'
  for update;
  if not found then
    raise exception 'ACTIVE_PLATFORM_CREDENTIAL_REQUIRED' using errcode='42501';
  end if;
  return credential;
end; $$;
revoke all on function public.require_system_owner_webauthn_actor(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.require_system_owner_webauthn_actor(uuid,uuid,uuid) to service_role;

create or replace function public.begin_system_owner_credential_enrollment(
  p_actor_user_id uuid,p_actor_device_id uuid,p_session_id uuid,
  p_environment text,p_expected_origin text,p_expected_rp_id text,
  p_challenge_hash bytea,p_operation_id uuid,p_bootstrap_hash bytea
) returns jsonb language plpgsql security definer set search_path='' as $$
declare bootstrap_authorization public.system_owner_credential_bootstrap_authorizations%rowtype;
  challenge_id uuid;
begin
  perform public.require_platform_device_backend();
  if p_session_id is null or p_operation_id is null
    or pg_catalog.octet_length(p_challenge_hash)<>32
    or pg_catalog.octet_length(p_bootstrap_hash)<>32 then
    raise exception 'CREDENTIAL_ENROLLMENT_ARGUMENT_INVALID' using errcode='22023';
  end if;
  if not platform_private.is_canonical_platform_owner(p_actor_user_id) then
    raise exception 'APPROVED_SYSTEM_OWNER_DEVICE_REQUIRED' using errcode='42501';
  end if;
  perform platform_private.require_canonical_device_authorization(
    p_actor_user_id,p_actor_device_id,true);
  select * into bootstrap_authorization
  from public.system_owner_credential_bootstrap_authorizations bootstrap
  where bootstrap.authorization_hash=p_bootstrap_hash
    and bootstrap.intended_user_id=p_actor_user_id
    and bootstrap.intended_device_id=p_actor_device_id
    and bootstrap.environment=p_environment and bootstrap.consumed_at is null
    and pg_catalog.statement_timestamp() between bootstrap.issued_at and bootstrap.expires_at
  for update;
  if not found then
    raise exception 'CREDENTIAL_BOOTSTRAP_AUTHORIZATION_INVALID' using errcode='42501';
  end if;
  insert into public.device_possession_challenges(challenge_hash,user_id,session_id,
    actor_device_id,credential_id,purpose,operation_id,expected_origin,expected_rp_id,
    environment,expires_at)
  values(p_challenge_hash,p_actor_user_id,p_session_id,p_actor_device_id,null,
    'SYSTEM_OWNER_CREDENTIAL_ENROLLMENT',p_operation_id,pg_catalog.lower(p_expected_origin),
    pg_catalog.lower(p_expected_rp_id),p_environment,pg_catalog.now()+interval '2 minutes')
  returning id into challenge_id;
  return pg_catalog.jsonb_build_object('status','challenge_created','challengeId',challenge_id,
    'bootstrapAuthorizationId',bootstrap_authorization.id,'operationId',p_operation_id);
end; $$;
revoke all on function public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)
  from public,anon,authenticated;
grant execute on function public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)
  to service_role;

create or replace function public.get_system_owner_platform_device_administration_state(
  p_actor_user_id uuid,p_actor_device_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare credential public.device_security_credentials%rowtype;
begin
  perform public.require_platform_device_backend();
  if not platform_private.is_canonical_platform_owner(p_actor_user_id) then
    raise exception 'APPROVED_SYSTEM_OWNER_DEVICE_REQUIRED' using errcode='42501';
  end if;
  perform platform_private.require_canonical_device_authorization(
    p_actor_user_id,p_actor_device_id,true);
  select * into credential from public.device_security_credentials stored
  where stored.user_id=p_actor_user_id and stored.device_id=p_actor_device_id
    and stored.credential_kind='platform_primary' and stored.lifecycle_status='active'
    and stored.backup_eligible=false and stored.backup_state=false
  order by stored.activated_at desc limit 1;
  if not found then
    return pg_catalog.jsonb_build_object('status','enrollment_required');
  end if;
  return pg_catalog.jsonb_build_object('status','ready','credentialId',credential.id,
    'credentialExternalId',pg_catalog.encode(credential.webauthn_credential_id,'base64'),
    'transports',credential.transports);
end; $$;
revoke all on function public.get_system_owner_platform_device_administration_state(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.get_system_owner_platform_device_administration_state(uuid,uuid)
  to service_role;

create or replace function public.begin_system_owner_device_possession_challenge(
  p_actor_user_id uuid,p_actor_device_id uuid,p_credential_id uuid,p_session_id uuid,
  p_purpose text,p_target_user_id uuid,p_target_device_id uuid,p_operation_id uuid,
  p_environment text,p_expected_origin text,p_expected_rp_id text,p_challenge_hash bytea
) returns jsonb language plpgsql security definer set search_path='' as $$
declare credential public.device_security_credentials%rowtype; challenge_id uuid;
  existing public.system_owner_device_authorization_operations%rowtype;
begin
  credential:=public.require_system_owner_webauthn_actor(
    p_actor_user_id,p_actor_device_id,p_credential_id);
  if p_session_id is null or pg_catalog.octet_length(p_challenge_hash)<>32
    or p_purpose not in ('SYSTEM_OWNER_PENDING_DEVICE_LIST',
      'SYSTEM_OWNER_PENDING_DEVICE_APPROVE','SYSTEM_OWNER_PENDING_DEVICE_REJECT') then
    raise exception 'PLATFORM_DEVICE_CHALLENGE_ARGUMENT_INVALID' using errcode='22023';
  end if;
  if p_purpose='SYSTEM_OWNER_PENDING_DEVICE_LIST' then
    if p_target_user_id is not null or p_target_device_id is not null
      or p_operation_id is not null then
      raise exception 'PLATFORM_DEVICE_LIST_CHALLENGE_BINDING_INVALID' using errcode='22023';
    end if;
  else
    if p_target_user_id is null or p_target_device_id is null or p_operation_id is null then
      raise exception 'PLATFORM_DEVICE_MUTATION_CHALLENGE_BINDING_INVALID' using errcode='22023';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'system-owner-device-operation:'||p_operation_id::text,0));
    select * into existing from public.system_owner_device_authorization_operations operations
    where operations.operation_id=p_operation_id;
    if found then
      if existing.actor_user_id_snapshot=p_actor_user_id
        and existing.actor_device_id=p_actor_device_id
        and existing.target_user_id_snapshot=p_target_user_id
        and existing.target_device_id=p_target_device_id
        and existing.environment=p_environment
        and existing.action=(case p_purpose when 'SYSTEM_OWNER_PENDING_DEVICE_APPROVE'
          then 'approve_system_owner_pending_device' else 'reject_system_owner_pending_device' end) then
        return pg_catalog.jsonb_build_object('status','completed','result',existing.stored_result);
      end if;
      raise exception 'PLATFORM_DEVICE_OPERATION_MISMATCH' using errcode='22023';
    end if;
    if not exists(select 1 from platform.user_device_authorizations device_authorization
      join platform.devices device on device.id=device_authorization.device_id
      join platform.profiles profile on profile.user_id=device_authorization.user_id
      where device_authorization.user_id=p_target_user_id
        and device_authorization.device_id=p_target_device_id
        and device_authorization.status='pending' and device_authorization.revoked_at is null
        and device.lifecycle_status='active' and device.retired_at is null
        and device.compromised_at is null and profile.account_status='approved'
        and exists(select 1 from platform.device_key_bindings binding
          where binding.user_id=device_authorization.user_id
            and binding.device_id=device_authorization.device_id
            and binding.device_authorization_id=device_authorization.id
            and binding.lifecycle_status='active' and binding.revoked_at is null
            and binding.retired_at is null)) then
      raise exception 'PENDING_APPROVED_ACCOUNT_DEVICE_REQUIRED' using errcode='42501';
    end if;
  end if;
  insert into public.device_possession_challenges(challenge_hash,user_id,session_id,
    actor_device_id,credential_id,purpose,target_user_id,target_device_id,operation_id,
    expected_origin,expected_rp_id,environment,expires_at)
  values(p_challenge_hash,p_actor_user_id,p_session_id,p_actor_device_id,p_credential_id,
    p_purpose,p_target_user_id,p_target_device_id,p_operation_id,
    pg_catalog.lower(p_expected_origin),pg_catalog.lower(p_expected_rp_id),p_environment,
    pg_catalog.statement_timestamp()+interval '2 minutes') returning id into challenge_id;
  return pg_catalog.jsonb_build_object('status','challenge_created','challengeId',challenge_id,
    'credentialId',credential.id,
    'credentialExternalId',pg_catalog.encode(credential.webauthn_credential_id,'base64'),
    'publicKeyCose',pg_catalog.encode(credential.public_key_cose,'base64'),
    'signCount',credential.sign_count,'transports',credential.transports,
    'operationId',p_operation_id);
end; $$;
revoke all on function public.begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)
  from public,anon,authenticated;
grant execute on function public.begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)
  to service_role;

create or replace function public.list_system_owner_pending_device_authorizations(
  p_actor_user_id uuid,p_actor_device_id uuid,p_session_id uuid,p_environment text,
  p_listing_token_hash bytea
) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_platform_device_backend();
  if not exists(select 1 from public.privileged_device_listing_sessions session
    where session.opaque_token_hash=p_listing_token_hash and session.user_id=p_actor_user_id
      and session.session_id=p_session_id and session.actor_device_id=p_actor_device_id
      and session.environment=p_environment
      and session.scope='SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY'
      and session.revoked_at is null and session.expires_at>pg_catalog.statement_timestamp())
    or not platform_private.is_canonical_platform_owner(p_actor_user_id) then
    raise exception 'PRIVILEGED_LISTING_SESSION_INVALID' using errcode='42501';
  end if;
  perform platform_private.require_canonical_device_authorization(
    p_actor_user_id,p_actor_device_id,true);
  return pg_catalog.jsonb_build_object('status','success','devices',coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'targetUserId',device_authorization.user_id,'authorizationId',device_authorization.id,
      'deviceId',device_authorization.device_id,'deviceName',device.display_name,
      'platform',device.platform,'authorizationStatus',device_authorization.status,
      'requestedAt',device_authorization.requested_at,'displayName',profile.display_name,
      'email',users.email
    ) order by device_authorization.requested_at,device_authorization.id)
    from platform.user_device_authorizations device_authorization
    join platform.devices device on device.id=device_authorization.device_id
    join platform.profiles profile on profile.user_id=device_authorization.user_id
    join auth.users users on users.id=device_authorization.user_id
    where device_authorization.status='pending' and device_authorization.revoked_at is null
      and device.lifecycle_status='active' and device.retired_at is null
      and device.compromised_at is null and profile.account_status='approved'
  ),'[]'::jsonb));
end; $$;
revoke all on function public.list_system_owner_pending_device_authorizations(uuid,uuid,uuid,text,bytea)
  from public,anon,authenticated;
grant execute on function public.list_system_owner_pending_device_authorizations(uuid,uuid,uuid,text,bytea)
  to service_role;

create or replace function public.complete_system_owner_pending_device_operation(
  p_actor_user_id uuid,p_actor_device_id uuid,p_credential_id uuid,p_session_id uuid,
  p_environment text,p_challenge_id uuid,p_challenge_hash bytea,p_operation_id uuid,
  p_target_user_id uuid,p_target_device_id uuid,p_action text,p_new_sign_count bigint,
  p_origin text,p_rp_id text,p_verification_context jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare credential public.device_security_credentials%rowtype;
  challenge public.device_possession_challenges%rowtype;
  existing public.system_owner_device_authorization_operations%rowtype;
  target platform.user_device_authorizations%rowtype;
  result jsonb; purpose text; operation_action text; audit_action text;
begin
  perform public.require_platform_device_backend();
  if p_action not in ('approve','reject') then
    raise exception 'PLATFORM_DEVICE_ACTION_INVALID' using errcode='22023';
  end if;
  purpose:=case p_action when 'approve' then 'SYSTEM_OWNER_PENDING_DEVICE_APPROVE'
    else 'SYSTEM_OWNER_PENDING_DEVICE_REJECT' end;
  operation_action:=case p_action when 'approve' then 'approve_system_owner_pending_device'
    else 'reject_system_owner_pending_device' end;
  audit_action:=case p_action when 'approve' then 'pending_device_approved'
    else 'pending_device_rejected' end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'system-owner-device-operation:'||p_operation_id::text,0));
  select * into existing from public.system_owner_device_authorization_operations operation
  where operation.operation_id=p_operation_id;
  if found then
    if existing.actor_user_id_snapshot=p_actor_user_id
      and existing.actor_device_id=p_actor_device_id
      and existing.target_user_id_snapshot=p_target_user_id
      and existing.target_device_id=p_target_device_id
      and existing.action=operation_action and existing.environment=p_environment then
      return existing.stored_result;
    end if;
    raise exception 'PLATFORM_DEVICE_OPERATION_MISMATCH' using errcode='22023';
  end if;
  credential:=public.require_system_owner_webauthn_actor(
    p_actor_user_id,p_actor_device_id,p_credential_id);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'platform-device-authorization-user:'||p_target_user_id::text,0));
  select * into challenge from public.device_possession_challenges stored
  where stored.id=p_challenge_id and stored.user_id=p_actor_user_id
    and stored.session_id=p_session_id and stored.actor_device_id=p_actor_device_id
    and stored.credential_id=p_credential_id and stored.purpose=purpose
    and stored.target_user_id=p_target_user_id and stored.target_device_id=p_target_device_id
    and stored.operation_id=p_operation_id and stored.environment=p_environment
    and stored.challenge_hash=p_challenge_hash for update;
  if not found or challenge.verified_at is not null or challenge.consumed_at is not null
    or challenge.failed_at is not null or challenge.expires_at<=pg_catalog.statement_timestamp()
    or challenge.expected_origin<>pg_catalog.lower(p_origin)
    or challenge.expected_rp_id<>pg_catalog.lower(p_rp_id)
    or p_new_sign_count<credential.sign_count
    or coalesce((p_verification_context->>'userVerified')::boolean,false)<>true
    or coalesce((p_verification_context->>'backupEligible')::boolean,true)<>false
    or coalesce((p_verification_context->>'backupState')::boolean,true)<>false then
    raise exception 'PLATFORM_DEVICE_OPERATION_VERIFICATION_INVALID' using errcode='42501';
  end if;
  select device_authorization.* into target
  from platform.user_device_authorizations device_authorization
  join platform.devices device on device.id=device_authorization.device_id
  join platform.profiles profile on profile.user_id=device_authorization.user_id
  where device_authorization.user_id=p_target_user_id
    and device_authorization.device_id=p_target_device_id
    and device_authorization.status='pending' and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved'
    and exists(select 1 from platform.device_key_bindings binding
      where binding.user_id=device_authorization.user_id
        and binding.device_id=device_authorization.device_id
        and binding.device_authorization_id=device_authorization.id
        and binding.lifecycle_status='active' and binding.revoked_at is null
        and binding.retired_at is null)
  for update of device_authorization;
  if not found then
    raise exception 'PENDING_APPROVED_ACCOUNT_DEVICE_REQUIRED' using errcode='42501';
  end if;
  update public.device_possession_challenges set verified_at=pg_catalog.statement_timestamp(),
    verification_context=p_verification_context where id=p_challenge_id;
  update public.device_security_credentials set sign_count=p_new_sign_count,
    last_used_at=pg_catalog.statement_timestamp() where id=p_credential_id;
  insert into public.device_possession_challenge_consumers(challenge_id,user_id,session_id,
    actor_device_id,actor_credential_id,challenge_purpose,environment,consumer_kind,consumer_id)
  values(p_challenge_id,p_actor_user_id,p_session_id,p_actor_device_id,p_credential_id,
    purpose,p_environment,'device_authorization_operation',p_operation_id);
  update platform.user_device_authorizations set
    status=case p_action when 'approve' then 'approved' else 'revoked' end,
    approved_by=case p_action when 'approve' then p_actor_user_id else approved_by end,
    approved_at=case p_action when 'approve' then pg_catalog.statement_timestamp() else approved_at end,
    revoked_by=case p_action when 'reject' then p_actor_user_id else null end,
    revoked_at=case p_action when 'reject' then pg_catalog.statement_timestamp() else null end,
    status_reason=null
  where id=target.id and user_id=p_target_user_id and device_id=p_target_device_id;
  result:=pg_catalog.jsonb_build_object('status','applied','action',p_action,
    'targetUserId',p_target_user_id,'deviceId',p_target_device_id,
    'authorizationStatus',case p_action when 'approve' then 'approved' else 'revoked' end,
    'operationId',p_operation_id);
  insert into public.system_owner_device_authorization_operations(operation_id,actor_user_id,
    actor_user_id_snapshot,actor_device_id,actor_credential_id,challenge_id,session_id,
    challenge_purpose,environment,target_user_id,target_user_id_snapshot,target_device_id,
    action,outcome,stored_result)
  values(p_operation_id,p_actor_user_id,p_actor_user_id,p_actor_device_id,p_credential_id,
    p_challenge_id,p_session_id,purpose,p_environment,p_target_user_id,p_target_user_id,
    p_target_device_id,operation_action,'applied',result);
  insert into public.privileged_device_authorization_audit_log(actor_user_id,
    actor_user_id_snapshot,actor_device_id,actor_credential_id,session_id_hash,session_id,
    challenge_id,challenge_purpose,environment,target_user_id,target_user_id_snapshot,
    target_device_id,challenge_target_user_id,challenge_target_device_id,action,operation_id,
    result,origin,rp_id,user_verified,backup_eligible,backup_state,security_context)
  values(p_actor_user_id,p_actor_user_id,p_actor_device_id,p_credential_id,
    extensions.digest(p_session_id::text,'sha256'),p_session_id,p_challenge_id,purpose,
    p_environment,p_target_user_id,p_target_user_id,p_target_device_id,p_target_user_id,
    p_target_device_id,audit_action,p_operation_id,'applied',pg_catalog.lower(p_origin),
    pg_catalog.lower(p_rp_id),true,false,false,p_verification_context);
  perform platform_private.write_audit_event(p_actor_user_id,p_target_user_id,'platform',
    'devices','device_authorization.'||(case p_action when 'approve' then 'approved' else 'revoked' end),
    'user_device_authorization',target.id,'platform',
    pg_catalog.jsonb_build_object('status','pending'),
    pg_catalog.jsonb_build_object('status',case p_action when 'approve' then 'approved' else 'revoked' end),
    pg_catalog.jsonb_build_object('deviceId',p_target_device_id,'confirmation','webauthn'),
    null,p_operation_id,'system');
  update public.device_possession_challenges set consumed_at=pg_catalog.statement_timestamp()
  where id=p_challenge_id;
  return result;
end; $$;
revoke all on function public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)
  to service_role;

create or replace function public.get_system_owner_device_operation_result(
  p_actor_user_id uuid,p_actor_device_id uuid,p_operation_id uuid,p_target_user_id uuid,
  p_target_device_id uuid,p_action text,p_environment text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare stored public.system_owner_device_authorization_operations%rowtype;
begin
  perform public.require_platform_device_backend();
  if not platform_private.is_canonical_platform_owner(p_actor_user_id) then
    raise exception 'APPROVED_SYSTEM_OWNER_DEVICE_REQUIRED' using errcode='42501';
  end if;
  perform platform_private.require_canonical_device_authorization(
    p_actor_user_id,p_actor_device_id,true);
  select * into stored from public.system_owner_device_authorization_operations operation
  where operation.operation_id=p_operation_id;
  if not found then return pg_catalog.jsonb_build_object('status','not_found'); end if;
  if stored.actor_user_id_snapshot<>p_actor_user_id
    or stored.actor_device_id<>p_actor_device_id
    or stored.target_user_id_snapshot<>p_target_user_id
    or stored.target_device_id<>p_target_device_id or stored.environment<>p_environment
    or stored.action<>(case p_action when 'approve' then 'approve_system_owner_pending_device'
      when 'reject' then 'reject_system_owner_pending_device' else '' end) then
    raise exception 'PLATFORM_DEVICE_OPERATION_MISMATCH' using errcode='22023';
  end if;
  return pg_catalog.jsonb_build_object('status','completed','result',stored.stored_result);
end; $$;
revoke all on function public.get_system_owner_device_operation_result(uuid,uuid,uuid,uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.get_system_owner_device_operation_result(uuid,uuid,uuid,uuid,uuid,text,text)
  to service_role;

create or replace function public.issue_system_owner_credential_bootstrap_authorization(
  p_operator_user_id uuid,p_operator_device_id uuid,p_intended_user_id uuid,
  p_intended_device_id uuid,p_environment text,p_authorization_hash bytea,
  p_origin text,p_rp_id text,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare audit_id uuid; authorization_id uuid;
begin
  perform public.require_platform_device_backend();
  if pg_catalog.octet_length(p_authorization_hash)<>32
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) not between 1 and 500 then
    raise exception 'CREDENTIAL_BOOTSTRAP_ISSUANCE_ARGUMENT_INVALID' using errcode='22023';
  end if;
  if not platform_private.is_canonical_platform_owner(p_operator_user_id)
    or not platform_private.is_canonical_platform_owner(p_intended_user_id) then
    raise exception 'CREDENTIAL_BOOTSTRAP_APPROVED_SYSTEM_OWNER_DEVICE_REQUIRED' using errcode='42501';
  end if;
  perform platform_private.require_canonical_device_authorization(
    p_operator_user_id,p_operator_device_id,true);
  perform platform_private.require_canonical_device_authorization(
    p_intended_user_id,p_intended_device_id,true);
  insert into public.privileged_device_authorization_audit_log(actor_user_id,
    actor_user_id_snapshot,actor_device_id,actor_credential_id,session_id_hash,session_id,
    challenge_id,challenge_purpose,environment,target_user_id,target_user_id_snapshot,
    target_device_id,action,operation_id,result,origin,rp_id,user_verified,
    backup_eligible,backup_state,security_context)
  values(p_operator_user_id,p_operator_user_id,p_operator_device_id,null,
    extensions.digest('bootstrap-issuance:'||p_authorization_hash::text,'sha256'),
    null,null,null,p_environment,p_intended_user_id,p_intended_user_id,p_intended_device_id,
    'credential_bootstrap_authorization_issued',null,'issued',pg_catalog.lower(p_origin),
    pg_catalog.lower(p_rp_id),false,false,false,
    pg_catalog.jsonb_build_object('reason',pg_catalog.btrim(p_reason))) returning id into audit_id;
  insert into public.system_owner_credential_bootstrap_authorizations(authorization_hash,
    intended_user_id,intended_device_id,environment,intended_device_authorization_status,
    intended_device_revoked_at,intended_user_system_owner,expires_at,operator_user_id,reason,
    issuance_audit_id)
  values(p_authorization_hash,p_intended_user_id,p_intended_device_id,p_environment,
    'approved',null,true,pg_catalog.statement_timestamp()+interval '10 minutes',
    p_operator_user_id,pg_catalog.btrim(p_reason),audit_id) returning id into authorization_id;
  return pg_catalog.jsonb_build_object('status','issued','authorizationId',authorization_id,
    'expiresInSeconds',600,'auditId',audit_id);
end; $$;
revoke all on function public.issue_system_owner_credential_bootstrap_authorization(uuid,uuid,uuid,uuid,text,bytea,text,text,text)
  from public,anon,authenticated;
grant execute on function public.issue_system_owner_credential_bootstrap_authorization(uuid,uuid,uuid,uuid,text,bytea,text,text,text)
  to service_role;

create or replace function public.guard_device_security_credential_lifecycle()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    if new.lifecycle_status<>'enrollment_pending' then
      raise exception 'DEVICE_SECURITY_CREDENTIAL_MUST_ENROLL_PENDING' using errcode='42501';
    end if;
    perform platform_private.require_canonical_device_authorization(new.user_id,new.device_id,true);
    return new;
  end if;
  if tg_op='DELETE' then
    raise exception 'DEVICE_SECURITY_CREDENTIAL_DELETE_FORBIDDEN' using errcode='42501';
  end if;
  if new.id<>old.id or new.webauthn_credential_id<>old.webauthn_credential_id
    or new.user_id<>old.user_id or new.device_id<>old.device_id
    or new.credential_kind<>old.credential_kind or new.public_key_cose<>old.public_key_cose
    or new.public_key_algorithm<>old.public_key_algorithm or new.aaguid is distinct from old.aaguid
    or new.transports<>old.transports or new.backup_eligible<>old.backup_eligible
    or new.backup_state<>old.backup_state or new.user_verification_policy<>old.user_verification_policy
    or new.created_at<>old.created_at then
    raise exception 'DEVICE_SECURITY_CREDENTIAL_IDENTITY_IMMUTABLE' using errcode='42501';
  end if;
  if (old.enrolled_at is not null and new.enrolled_at is distinct from old.enrolled_at)
    or (old.activated_at is not null and new.activated_at is distinct from old.activated_at)
    or (old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at) then
    raise exception 'DEVICE_SECURITY_CREDENTIAL_SECURITY_TIME_IMMUTABLE' using errcode='42501';
  end if;
  if old.lifecycle_status='revoked'
    or (old.lifecycle_status='enrollment_pending' and new.lifecycle_status not in ('enrollment_pending','active','revoked'))
    or (old.lifecycle_status='active' and new.lifecycle_status not in ('active','rotation_pending','recovery_required','revoked'))
    or (old.lifecycle_status='rotation_pending' and new.lifecycle_status not in ('rotation_pending','active','recovery_required','revoked'))
    or (old.lifecycle_status='recovery_required' and new.lifecycle_status not in ('recovery_required','revoked')) then
    raise exception 'DEVICE_SECURITY_CREDENTIAL_TRANSITION_INVALID' using errcode='42501';
  end if;
  if new.sign_count<old.sign_count then
    raise exception 'DEVICE_SECURITY_CREDENTIAL_COUNTER_REGRESSION' using errcode='42501';
  end if;
  if new.lifecycle_status='active' then
    perform platform_private.require_canonical_device_authorization(new.user_id,new.device_id,true);
  end if;
  return new;
end; $$;

create or replace function platform_private.guard_canonical_device_credential_state()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then
    if exists(select 1 from public.device_security_credentials credential
      where credential.user_id=old.user_id and credential.device_id=old.device_id
        and credential.lifecycle_status<>'revoked') then
      raise exception 'DEVICE_AUTHORIZATION_HAS_LIVE_SECURITY_CREDENTIAL' using errcode='42501';
    end if;
    return old;
  end if;
  if (new.status in ('blocked','revoked') or new.revoked_at is not null)
    and exists(select 1 from public.device_security_credentials credential
      where credential.user_id=new.user_id and credential.device_id=new.device_id
        and credential.lifecycle_status<>'revoked') then
    raise exception 'LIVE_SECURITY_CREDENTIAL_REVOCATION_REQUIRED' using errcode='42501';
  end if;
  return new;
end; $$;
drop trigger if exists canonical_device_authorization_security_credential_guard
  on platform.user_device_authorizations;
create trigger canonical_device_authorization_security_credential_guard
before update or delete on platform.user_device_authorizations
for each row execute function platform_private.guard_canonical_device_credential_state();
revoke all on function platform_private.guard_canonical_device_credential_state()
  from public,anon,authenticated,service_role;

alter table public.device_authorization_admin_operations
  drop constraint device_authorization_admin_actor_device_fk,
  drop constraint device_authorization_admin_target_device_fk,
  drop constraint device_authorization_admin_replacement_device_fk,
  -- Historical member-operation actors predate canonical Platform authority;
  -- no backfill or reclassification is permitted. Enforce prospectively only.
  add constraint device_authorization_admin_actor_platform_device_fk
    foreign key(actor_user_id_snapshot,actor_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  -- Historical member-operation targets predate canonical Platform authority;
  -- no backfill or reclassification is permitted. Enforce prospectively only.
  add constraint device_authorization_admin_target_platform_device_fk
    foreign key(target_user_id_snapshot,device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid,
  add constraint device_authorization_admin_replacement_platform_device_fk
    foreign key(target_user_id_snapshot,replacement_device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict;
alter table public.device_authorization_audit_log
  drop constraint device_authorization_audit_device_owner_fk,
  -- Historical member-device audit rows predate canonical Platform authority;
  -- no backfill or reclassification is permitted. Enforce prospectively only.
  add constraint device_authorization_audit_platform_device_owner_fk
    foreign key(target_user_id,device_id)
    references platform.user_device_authorizations(user_id,device_id) on delete restrict not valid;

-- Active Conference, template, synchronization, and module-grant provenance
-- must accept canonical-only Platform devices. These constraints are NOT VALID
-- so historical legacy provenance is preserved without being reclassified;
-- every new or changed row is nevertheless enforced against Platform authority.
alter table public.conference_locks
  drop constraint conference_locks_device_id_fkey,
  add constraint conference_locks_platform_device_fkey foreign key(device_id)
    references platform.devices(id) on delete cascade not valid;
alter table public.conference_snapshots
  drop constraint conference_snapshots_updated_by_device_id_fkey,
  add constraint conference_snapshots_platform_device_fkey foreign key(updated_by_device_id)
    references platform.devices(id) not valid;
alter table public.sync_operations
  drop constraint sync_operations_device_id_fkey,
  add constraint sync_operations_platform_device_fkey foreign key(device_id)
    references platform.devices(id) not valid;
alter table public.library_template_audit_log
  drop constraint library_template_audit_log_actor_device_id_fkey,
  add constraint library_template_audit_log_platform_device_fkey foreign key(actor_device_id)
    references platform.devices(id) on delete set null not valid;
alter table public.library_template_operations
  drop constraint library_template_operations_actor_device_id_fkey,
  add constraint library_template_operations_platform_device_fkey foreign key(actor_device_id)
    references platform.devices(id) on delete restrict not valid;
alter table public.organization_template_access_audit_log
  drop constraint organization_template_access_audit_log_actor_device_id_fkey,
  add constraint organization_template_access_audit_platform_device_fkey foreign key(actor_device_id)
    references platform.devices(id) on delete set null not valid;
alter table public.organization_template_access_operations
  drop constraint organization_template_access_operations_actor_device_id_fkey,
  add constraint organization_template_access_operations_platform_device_fkey foreign key(actor_device_id)
    references platform.devices(id) on delete restrict not valid;
alter table public.organization_template_audit_log
  drop constraint organization_template_audit_log_actor_device_id_fkey,
  add constraint organization_template_audit_log_platform_device_fkey foreign key(actor_device_id)
    references platform.devices(id) on delete set null not valid;
alter table public.organization_template_operations
  drop constraint organization_template_operations_actor_device_id_fkey,
  add constraint organization_template_operations_platform_device_fkey foreign key(actor_device_id)
    references platform.devices(id) on delete restrict not valid;
alter table public.module_grant_audit_log
  drop constraint module_grant_audit_log_actor_device_fkey,
  add constraint module_grant_audit_log_actor_platform_device_fkey
    foreign key(actor_user_id,actor_device_id)
    references platform.user_device_authorizations(user_id,device_id)
    on delete restrict not valid;
alter table public.module_grant_operations
  drop constraint module_grant_operations_actor_device_fkey,
  add constraint module_grant_operations_actor_platform_device_fkey
    foreign key(actor_user_id,actor_device_id)
    references platform.user_device_authorizations(user_id,device_id)
    on delete restrict not valid;
alter table public.module_permission_grants
  drop constraint module_permission_grants_grantor_device_fkey,
  drop constraint module_permission_grants_revoker_device_fkey,
  add constraint module_permission_grants_grantor_platform_device_fkey
    foreign key(granted_by,granted_by_device_id)
    references platform.user_device_authorizations(user_id,device_id)
    on delete restrict not valid,
  add constraint module_permission_grants_revoker_platform_device_fkey
    foreign key(revoked_by,revoked_by_device_id)
    references platform.user_device_authorizations(user_id,device_id)
    on delete restrict not valid;

create or replace function public.list_member_device_authorizations(
  p_actor_device_id uuid,p_organization_id uuid,p_target_user_id uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare target_role text;
begin
  target_role:=public.require_device_authorization_manager(
    p_actor_device_id,p_organization_id,p_target_user_id);
  return pg_catalog.jsonb_build_object('status','success','organizationId',p_organization_id,
    'targetUserId',p_target_user_id,'targetRole',target_role,'devices',coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'deviceId',device_authorization.device_id,'deviceName',device.display_name,
        'platform',device.platform,'authorizationStatus',device_authorization.status,
        'requestedAt',device_authorization.requested_at,'approvedAt',device_authorization.approved_at,
        'approvedBy',device_authorization.approved_by,'revokedAt',device_authorization.revoked_at,
        'revokedBy',device_authorization.revoked_by,
        'lastRegisteredAt',device_authorization.last_authorized_seen_at,
        'isSoleApprovedDevice',device_authorization.status='approved'
          and device_authorization.revoked_at is null and (select count(*)
            from platform.user_device_authorizations approved
            join platform.devices approved_device on approved_device.id=approved.device_id
            where approved.user_id=p_target_user_id and approved.status='approved'
              and approved.revoked_at is null and approved_device.lifecycle_status='active')=1
      ) order by device_authorization.created_at,device_authorization.device_id)
      from platform.user_device_authorizations device_authorization
      join platform.devices device on device.id=device_authorization.device_id
      where device_authorization.user_id=p_target_user_id
    ),'[]'::jsonb));
end; $$;

create or replace function platform_private.apply_member_device_authorization(
  p_action text,p_actor_device_id uuid,p_organization_id uuid,p_target_user_id uuid,
  p_device_id uuid,p_replacement_device_id uuid,p_operation_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); target_role text;
  existing public.device_authorization_admin_operations%rowtype;
  target platform.user_device_authorizations%rowtype;
  replacement platform.user_device_authorizations%rowtype;
  result jsonb; result_status text; operation_name text;
begin
  if p_action not in ('approve','reject','revoke','replace') or p_device_id is null
    or p_operation_id is null or (p_action='replace')<>(p_replacement_device_id is not null)
    or (p_action='replace' and p_device_id=p_replacement_device_id) then
    raise exception 'DEVICE_ADMINISTRATION_ARGUMENT_REQUIRED' using errcode='22023';
  end if;
  target_role:=public.require_device_authorization_manager(
    p_actor_device_id,p_organization_id,p_target_user_id);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'organization-membership:'||p_organization_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'platform-device-authorization-user:'||p_target_user_id::text,0));
  target_role:=public.require_device_authorization_manager(
    p_actor_device_id,p_organization_id,p_target_user_id);
  operation_name:=case p_action when 'approve' then 'approve_member_device'
    when 'reject' then 'reject_member_pending_device' when 'revoke' then 'revoke_member_device'
    else 'replace_member_active_device' end;
  select * into existing from public.device_authorization_admin_operations operation
  where operation.operation_id=p_operation_id;
  if found then
    if existing.actor_user_id_snapshot=actor_id and existing.actor_device_id=p_actor_device_id
      and existing.organization_id=p_organization_id
      and existing.target_user_id_snapshot=p_target_user_id
      and existing.device_id=p_device_id
      and existing.replacement_device_id is not distinct from p_replacement_device_id
      and existing.action=operation_name then return existing.stored_result; end if;
    raise exception 'DEVICE_ADMINISTRATION_OPERATION_MISMATCH' using errcode='22023';
  end if;
  select device_authorization.* into target from platform.user_device_authorizations device_authorization
  join platform.devices device on device.id=device_authorization.device_id
  where device_authorization.user_id=p_target_user_id and device_authorization.device_id=p_device_id
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null for update of device_authorization;
  if not found then raise exception 'DEVICE_AUTHORIZATION_NOT_FOUND' using errcode='P0002'; end if;
  if p_action in ('approve','reject') and (target.status<>'pending' or target.revoked_at is not null) then
    raise exception 'PENDING_UNREVOKED_DEVICE_REQUIRED' using errcode='42501';
  end if;
  if p_action='approve' and exists(select 1 from platform.user_device_authorizations approved
    join platform.devices device on device.id=approved.device_id
    where approved.user_id=p_target_user_id and approved.status='approved'
      and approved.revoked_at is null and device.lifecycle_status='active') then
    raise exception 'DEVICE_APPROVAL_PRECONDITION_INVALID' using errcode='42501';
  end if;
  if p_action='revoke' and (target.status<>'approved' or target.revoked_at is not null) then
    raise exception 'APPROVED_UNREVOKED_DEVICE_REQUIRED' using errcode='42501';
  end if;
  if p_action='revoke' and (
      target_role='organization_owner' or actor_id=p_target_user_id
      or platform_private.is_canonical_platform_owner(p_target_user_id)
    ) and (select count(*) from platform.user_device_authorizations approved
      join platform.devices device on device.id=approved.device_id
      where approved.user_id=p_target_user_id and approved.status='approved'
        and approved.revoked_at is null and device.lifecycle_status='active'
        and device.retired_at is null and device.compromised_at is null)<=1 then
    raise exception 'DEVICE_REVOCATION_REPLACEMENT_REQUIRED' using errcode='42501';
  end if;
  if p_action='approve' and (
      not exists(select 1 from platform.profiles profile
        where profile.user_id=p_target_user_id and profile.account_status='approved')
      or not exists(select 1 from platform.device_key_bindings binding
        where binding.user_id=p_target_user_id and binding.device_id=p_device_id
          and binding.device_authorization_id=target.id
          and binding.lifecycle_status='active' and binding.revoked_at is null
          and binding.retired_at is null)
    ) then
    raise exception 'DEVICE_APPROVAL_PRECONDITION_INVALID' using errcode='42501';
  end if;
  if p_action='replace' then
    select device_authorization.* into replacement from platform.user_device_authorizations device_authorization
    join platform.devices device on device.id=device_authorization.device_id
    where device_authorization.user_id=p_target_user_id
      and device_authorization.device_id=p_replacement_device_id
      and device.lifecycle_status='active' and device.retired_at is null
      and device.compromised_at is null for update of device_authorization;
    if target.status<>'approved' or target.revoked_at is not null
      or replacement.status is distinct from 'pending' or replacement.revoked_at is not null
      or (select count(*) from platform.user_device_authorizations approved
        join platform.devices device on device.id=approved.device_id
        where approved.user_id=p_target_user_id and approved.status='approved'
          and approved.revoked_at is null and device.lifecycle_status='active')<>1 then
      raise exception 'DEVICE_REPLACEMENT_PRECONDITION_INVALID' using errcode='42501';
    end if;
  end if;
  if p_action in ('reject','revoke','replace') then
    update platform.user_device_authorizations set status='revoked',revoked_at=pg_catalog.now(),
      revoked_by=actor_id where id=target.id;
  else
    update platform.user_device_authorizations set status='approved',approved_at=pg_catalog.now(),
      approved_by=actor_id,revoked_at=null,revoked_by=null where id=target.id;
  end if;
  if p_action='replace' then
    update platform.user_device_authorizations set status='approved',approved_at=pg_catalog.now(),
      approved_by=actor_id,revoked_at=null,revoked_by=null where id=replacement.id;
  end if;
  result_status:=case when p_action in ('approve','replace') then 'approved' else 'revoked' end;
  result:=case when p_action='replace' then pg_catalog.jsonb_build_object('status','applied',
    'organizationId',p_organization_id,'targetUserId',p_target_user_id,
    'revokedDeviceId',p_device_id,'approvedDeviceId',p_replacement_device_id)
  else pg_catalog.jsonb_build_object('status','applied','authorizationStatus',result_status,
    'organizationId',p_organization_id,'targetUserId',p_target_user_id,'deviceId',p_device_id) end;
  insert into public.device_authorization_audit_log(actor_user_id,target_user_id,device_id,
    action,operation_id,old_values,new_values)
  values(actor_id,p_target_user_id,p_device_id,
    case p_action when 'approve' then 'device_authorization_approved'
      when 'reject' then 'device_authorization_rejected' else 'device_authorization_revoked' end,
    p_operation_id,pg_catalog.jsonb_build_object('authorizationStatus',target.status),
    pg_catalog.jsonb_build_object('authorizationStatus',case when p_action='approve' then 'approved' else 'revoked' end,
      'organizationId',p_organization_id,'replacementDeviceId',p_replacement_device_id));
  if p_action='replace' then
    insert into public.device_authorization_audit_log(actor_user_id,target_user_id,device_id,
      action,operation_id,old_values,new_values)
    values(actor_id,p_target_user_id,p_replacement_device_id,'device_authorization_approved',
      p_operation_id,pg_catalog.jsonb_build_object('authorizationStatus','pending'),
      pg_catalog.jsonb_build_object('authorizationStatus','approved','organizationId',p_organization_id,
        'replacedDeviceId',p_device_id));
  end if;
  insert into public.device_authorization_admin_operations(operation_id,organization_id,
    actor_user_id,actor_user_id_snapshot,actor_device_id,target_user_id,target_user_id_snapshot,
    device_id,replacement_device_id,action,outcome,stored_result)
  values(p_operation_id,p_organization_id,actor_id,actor_id,p_actor_device_id,p_target_user_id,
    p_target_user_id,p_device_id,p_replacement_device_id,operation_name,'applied',result);
  return result;
end; $$;
revoke all on function platform_private.apply_member_device_authorization(text,uuid,uuid,uuid,uuid,uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function public.approve_member_device(
  p_actor_device_id uuid,p_organization_id uuid,p_target_user_id uuid,
  p_device_id uuid,p_operation_id uuid
)
returns jsonb language sql security definer set search_path='' as $$
  select platform_private.apply_member_device_authorization('approve',p_actor_device_id,
    p_organization_id,p_target_user_id,p_device_id,null,p_operation_id); $$;
create or replace function public.reject_member_pending_device(
  p_actor_device_id uuid,p_organization_id uuid,p_target_user_id uuid,
  p_device_id uuid,p_operation_id uuid
)
returns jsonb language sql security definer set search_path='' as $$
  select platform_private.apply_member_device_authorization('reject',p_actor_device_id,
    p_organization_id,p_target_user_id,p_device_id,null,p_operation_id); $$;
create or replace function public.revoke_member_device(
  p_actor_device_id uuid,p_organization_id uuid,p_target_user_id uuid,
  p_device_id uuid,p_operation_id uuid
)
returns jsonb language sql security definer set search_path='' as $$
  select platform_private.apply_member_device_authorization('revoke',p_actor_device_id,
    p_organization_id,p_target_user_id,p_device_id,null,p_operation_id); $$;
create or replace function public.replace_member_active_device(
  p_actor_device_id uuid,p_organization_id uuid,p_target_user_id uuid,
  p_active_device_id uuid,p_replacement_device_id uuid,p_operation_id uuid
)
returns jsonb language sql security definer set search_path='' as $$
  select platform_private.apply_member_device_authorization('replace',p_actor_device_id,
    p_organization_id,p_target_user_id,p_active_device_id,p_replacement_device_id,p_operation_id); $$;

revoke all on function public.list_member_device_authorizations(uuid,uuid,uuid) from public,anon;
revoke all on function public.approve_member_device(uuid,uuid,uuid,uuid,uuid) from public,anon;
revoke all on function public.reject_member_pending_device(uuid,uuid,uuid,uuid,uuid) from public,anon;
revoke all on function public.revoke_member_device(uuid,uuid,uuid,uuid,uuid) from public,anon;
revoke all on function public.replace_member_active_device(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon;
grant execute on function public.list_member_device_authorizations(uuid,uuid,uuid) to authenticated;
grant execute on function public.approve_member_device(uuid,uuid,uuid,uuid,uuid) to authenticated;
grant execute on function public.reject_member_pending_device(uuid,uuid,uuid,uuid,uuid) to authenticated;
grant execute on function public.revoke_member_device(uuid,uuid,uuid,uuid,uuid) to authenticated;
grant execute on function public.replace_member_active_device(uuid,uuid,uuid,uuid,uuid,uuid) to authenticated;

create or replace function platform_private.canonical_device_count(p_user_id uuid)
returns bigint language sql stable security definer set search_path='' as $$
  select count(*) from platform.user_device_authorizations device_authorization
  join platform.devices device on device.id=device_authorization.device_id
  where device_authorization.user_id=p_user_id
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null;
$$;
revoke all on function platform_private.canonical_device_count(uuid)
  from public,anon,authenticated,service_role;

create or replace function public.search_user_management_users(
  p_actor_device_id uuid,p_query text default null,p_account_status text default null,
  p_limit integer default 50
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid; system_owner boolean;
  normalized_query text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_query,'')));
  effective_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
  actor_id:=public.require_current_approved_device(p_actor_device_id);
  system_owner:=public.is_system_owner(actor_id);
  if p_account_status is not null and p_account_status not in ('pending','approved','blocked') then
    raise exception 'INVALID_ACCOUNT_STATUS' using errcode='22023';
  end if;
  return pg_catalog.jsonb_build_object('status','success',
    'capabilities',public.get_user_management_actor_capabilities(p_actor_device_id)-'status',
    'users',coalesce((with scoped_users as (
      select users.id,users.email from auth.users users where system_owner
      union
      select users.id,users.email from public.organization_members actor_members
      join public.organization_members target_members
        on target_members.organization_id=actor_members.organization_id
      join auth.users users on users.id=target_members.user_id
      where actor_members.user_id=actor_id
        and actor_members.role in ('organization_owner','organization_admin')
      union
      select users.id,users.email from public.conferences conferences
      join public.conference_members target_members
        on target_members.conference_id=conferences.id
      join auth.users users on users.id=target_members.user_id
      where conferences.owner_id=actor_id and conferences.deleted_at is null
    ), filtered as (
      select users.id,users.email from scoped_users users
      join public.system_user_access access on access.user_id=users.id
      left join public.profiles profiles on profiles.id=users.id
      where (p_account_status is null or access.account_status=p_account_status)
        and (normalized_query='' or pg_catalog.lower(coalesce(profiles.display_name,''))
          like '%'||normalized_query||'%'
          or pg_catalog.lower(coalesce(users.email,'')) like '%'||normalized_query||'%')
      order by coalesce(profiles.display_name,users.email),users.id limit effective_limit
    ) select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'userId',users.id,'displayName',profiles.display_name,'email',users.email,
      'accountStatus',access.account_status,
      'conferenceCount',(select count(*) from public.conference_members members
        join public.conferences conferences on conferences.id=members.conference_id
        where members.user_id=users.id and (system_owner or conferences.owner_id=actor_id)),
      'deviceCount',platform_private.canonical_device_count(users.id)
    ) order by coalesce(profiles.display_name,users.email),users.id)
    from filtered users
    join public.system_user_access access on access.user_id=users.id
    left join public.profiles profiles on profiles.id=users.id),'[]'::jsonb));
end; $$;
revoke all on function public.search_user_management_users(uuid,text,text,integer) from public,anon;
grant execute on function public.search_user_management_users(uuid,text,text,integer) to authenticated;

create or replace function public.get_organization_management_overview(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); rows jsonb; can_create boolean;
begin
  if actor_id is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  perform public.require_current_approved_device(p_actor_device_id);
  can_create:=public.is_system_owner(actor_id);
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'organizationId',organization.id,'organizationKey',organization.organization_key,
    'displayName',organization.display_name,'description',organization.description,
    'status',organization.status,'createdAt',organization.created_at,
    'updatedAt',organization.updated_at,'role',mine.role,
    'ownerId',owner_row.user_id,'ownerName',owner_profile.display_name,
    'conferenceCount',(select count(*) from public.conferences conference
      where conference.organization_id=organization.id),
    'memberCount',(select count(*) from public.organization_members member
      where member.organization_id=organization.id),
    'deviceCount',(select coalesce(sum(platform_private.canonical_device_count(member.user_id)),0)
      from public.organization_members member where member.organization_id=organization.id),
    'capabilities',pg_catalog.jsonb_build_object('canOpen',true,
      'canManageMembers',organization.status='active'
        and mine.role in ('organization_owner','organization_admin'),
      'canEdit',organization.status='active' and mine.role='organization_owner',
      'canArchive',organization.status='active' and mine.role='organization_owner',
      'canRestore',organization.status='archived' and mine.role='organization_owner',
      'canDelete',false)
  ) order by organization.created_at,organization.id),'[]'::jsonb) into rows
  from public.organizations organization
  join public.organization_members mine
    on mine.organization_id=organization.id and mine.user_id=actor_id
  left join lateral (select member.user_id from public.organization_members member
    where member.organization_id=organization.id and member.role='organization_owner'
    order by member.created_at,member.user_id limit 1) owner_row on true
  left join public.profiles owner_profile on owner_profile.id=owner_row.user_id;
  return pg_catalog.jsonb_build_object('status','success','canCreate',can_create,
    'organizations',rows);
end; $$;
revoke all on function public.get_organization_management_overview(uuid) from public,anon;
grant execute on function public.get_organization_management_overview(uuid) to authenticated;

create or replace function public.get_user_management_devices(
  p_actor_device_id uuid,p_target_user_id uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid; system_owner boolean; scoped boolean;
begin
  if p_target_user_id is null then
    raise exception 'TARGET_USER_REQUIRED' using errcode='22023';
  end if;
  actor_id:=public.require_current_approved_device(p_actor_device_id);
  system_owner:=public.is_system_owner(actor_id);
  scoped:=system_owner or exists(
    select 1 from public.organization_members actor_member
    join public.organization_members target_member
      on target_member.organization_id=actor_member.organization_id
    where actor_member.user_id=actor_id and target_member.user_id=p_target_user_id
      and actor_member.role in ('organization_owner','organization_admin')
      and (actor_member.role='organization_owner' or target_member.role='member'));
  if not scoped then raise exception 'DEVICE_READ_SCOPE_DENIED' using errcode='42501'; end if;
  return pg_catalog.jsonb_build_object('status','success','devices',coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'deviceId',device_authorization.device_id,'deviceName',device.display_name,
      'platform',device.platform,'lastSeenAt',device.last_seen_at,
      'authorizationStatus',device_authorization.status,
      'requestedAt',device_authorization.requested_at,'approvedAt',device_authorization.approved_at,
      'revokedAt',device_authorization.revoked_at,
      'lastRegisteredAt',device_authorization.last_authorized_seen_at,
      'capabilities',pg_catalog.jsonb_build_object(
        'canApprove',false,'canReject',false,'canRevoke',false))
      order by device_authorization.created_at,device_authorization.device_id)
    from platform.user_device_authorizations device_authorization
    join platform.devices device on device.id=device_authorization.device_id
    where device_authorization.user_id=p_target_user_id
  ),'[]'::jsonb));
end; $$;
revoke all on function public.get_user_management_devices(uuid,uuid) from public,anon;
grant execute on function public.get_user_management_devices(uuid,uuid) to authenticated;

-- Native Platform enrollment supersedes these legacy mutators. Keep their
-- historical definitions for migration lineage, but remove all runtime entry.
revoke execute on function public.register_or_refresh_current_device(uuid,text,text)
  from public,anon,authenticated,service_role;
revoke execute on function public.request_current_device_authorization(uuid,uuid)
  from public,anon,authenticated,service_role;

commit;
