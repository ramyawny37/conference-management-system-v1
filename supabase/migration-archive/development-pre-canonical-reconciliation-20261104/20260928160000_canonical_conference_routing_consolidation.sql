begin;

do $$
begin
  if to_regprocedure('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)') is null
     or to_regprocedure('platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date)') is null
     or to_regprocedure('public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text)') is null
     or to_regprocedure('public.list_conference_participations(uuid,uuid)') is null
     or to_regprocedure('public.create_conference_participation(uuid,uuid,uuid,uuid)') is null
     or to_regprocedure('public.set_conference_participation_status(uuid,uuid,uuid,bigint,text)') is null
     or to_regprocedure('public.delete_conference_participation(uuid,uuid,uuid,bigint)') is null then
    raise exception 'P4C_CANONICAL_CONFERENCE_ROUTING_REQUIRED' using errcode='55000';
  end if;
end $$;

create function platform_private.route_canonical_conference_operation(
  p_user_id uuid,
  p_session_id uuid,
  p_token_hash bytea,
  p_actor_device_id uuid,
  p_operation text,
  p_args jsonb
) returns jsonb language plpgsql security definer
set search_path=''
as $$
begin
  if p_operation='create_canonical_conference' then
    perform platform_private.require_exact_jsonb_keys(
      p_args,array[
        'p_operation_id','p_requested_conference_id','p_organization_id',
        'p_name','p_start_date','p_end_date'
      ]
    );
    return public.create_canonical_conference(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_requested_conference_id')::uuid,
      (p_args->>'p_organization_id')::uuid,p_args->>'p_name',
      (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date
    );
  elsif p_operation='mutate_conference_core' then
    perform platform_private.require_exact_jsonb_keys(
      p_args,array[
        'p_conference_id','p_expected_revision','p_name','p_start_date',
        'p_end_date','p_status'
      ]
    );
    return public.mutate_conference_core(
      p_actor_device_id,(p_args->>'p_conference_id')::uuid,
      (p_args->>'p_expected_revision')::bigint,p_args->>'p_name',
      (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,
      p_args->>'p_status'
    );
  elsif p_operation='list_conference_participations' then
    perform platform_private.require_exact_jsonb_keys(
      p_args,array['p_conference_id']
    );
    return public.list_conference_participations(
      p_actor_device_id,(p_args->>'p_conference_id')::uuid
    );
  elsif p_operation='create_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(
      p_args,array['p_operation_id','p_conference_id','p_person_id']
    );
    return public.create_conference_participation(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_conference_id')::uuid,(p_args->>'p_person_id')::uuid
    );
  elsif p_operation='set_conference_participation_status' then
    perform platform_private.require_exact_jsonb_keys(
      p_args,array[
        'p_operation_id','p_participation_id','p_expected_revision','p_status'
      ]
    );
    return public.set_conference_participation_status(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_participation_id')::uuid,
      (p_args->>'p_expected_revision')::bigint,p_args->>'p_status'
    );
  elsif p_operation='delete_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(
      p_args,array['p_operation_id','p_participation_id','p_expected_revision']
    );
    return public.delete_conference_participation(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_participation_id')::uuid,
      (p_args->>'p_expected_revision')::bigint
    );
  end if;

  return platform.execute_conference_device_operation_phase1c_core(
    p_user_id,p_session_id,p_token_hash,p_operation,p_args
  );
end $$;

revoke all on function platform_private.route_canonical_conference_operation(
  uuid,uuid,bytea,uuid,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function platform.execute_conference_device_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer
set search_path=''
as $$
declare
  v_session platform_private.device_sessions%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'CONFERENCE_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_user_id is null or p_session_id is null
     or pg_catalog.octet_length(p_token_hash)<>32 then
    raise exception 'DEVICE_SESSION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select session.* into v_session
  from platform_private.device_sessions session
  join platform.device_key_bindings binding on binding.id=session.binding_id
  join platform.user_device_authorizations device_authorization
    on device_authorization.id=session.device_authorization_id
  join platform.devices device on device.id=session.device_id
  join platform.profiles profile on profile.user_id=session.user_id
  where session.id=p_session_id and session.user_id=p_user_id
    and session.token_hash=p_token_hash
    and session.purpose='PLATFORM_DEVICE_SESSION'
    and session.revoked_at is null
    and session.expires_at>pg_catalog.statement_timestamp()
    and binding.user_id=session.user_id and binding.device_id=session.device_id
    and binding.device_authorization_id=session.device_authorization_id
    and binding.public_key_thumbprint=session.public_key_thumbprint
    and binding.algorithm='ECDSA_P256_SHA256'
    and binding.lifecycle_status='active'
    and binding.revoked_at is null and binding.retired_at is null
    and device_authorization.user_id=session.user_id
    and device_authorization.device_id=session.device_id
    and device_authorization.status='approved'
    and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved';
  if not found then
    raise exception 'DEVICE_SESSION_INVALID' using errcode='42501';
  end if;
  perform pg_catalog.set_config(
    'platform.phase1c_context',pg_catalog.jsonb_build_object(
      'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',v_session.id,
      'user_id',v_session.user_id,'device_id',v_session.device_id,
      'authorization_id',v_session.device_authorization_id,
      'binding_id',v_session.binding_id,
      'token_hash',pg_catalog.encode(p_token_hash,'hex')
    )::text,true
  );
  perform pg_catalog.set_config(
    'request.jwt.claims',pg_catalog.jsonb_build_object(
      'sub',p_user_id,'role','authenticated'
    )::text,true
  );

  return platform_private.route_canonical_conference_operation(
    p_user_id,p_session_id,p_token_hash,v_session.device_id,p_operation,p_args
  );
end $$;

revoke all on function platform.execute_conference_device_operation(
  uuid,uuid,bytea,text,jsonb
) from public,anon,authenticated,service_role;
grant execute on function platform.execute_conference_device_operation(
  uuid,uuid,bytea,text,jsonb
) to service_role;

comment on function platform_private.route_canonical_conference_operation(
  uuid,uuid,bytea,uuid,text,jsonb
) is 'Internal canonical Conference routing extension point. The outer Platform dispatcher validates the backend device session; unmatched legacy operations temporarily delegate to the Phase1C core.';

commit;
