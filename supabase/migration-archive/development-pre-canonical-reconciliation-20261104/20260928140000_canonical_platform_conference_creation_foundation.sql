begin;

-- P3B adds the server-native Conference creation operation. The legacy
-- Organization-authorized publishing operation remains for its existing
-- local/snapshot consumers and is not called by this operation.
do $$
begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.conference_creation_operations') is null
     or to_regclass('public.conference_members') is null
     or to_regclass('public.organizations') is null
     or to_regclass('public.system_user_access') is null
     or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.phase1c_context_device_id()') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('public.can_user_create_conferences(uuid)') is null
     or to_regprocedure('public.create_organization_conference_idempotent(uuid,uuid,uuid,text,jsonb)') is null
     or to_regprocedure('platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)') is null
     or to_regprocedure('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)') is null
     or to_regprocedure('public.add_conference_owner_membership()') is null then
    raise exception 'P3B_CANONICAL_CONFERENCE_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
  if not exists(
    select 1 from public.module_permission_catalog catalog
    where catalog.permission_key='conference.lifecycle.create'
      and catalog.module_key='conference' and catalog.status='active'
      and catalog.allowed_scope_mode='module'
      and catalog.allowed_resource_type is null
  ) then
    raise exception 'P3B_CONFERENCE_CREATE_PERMISSION_REQUIRED' using errcode='55000';
  end if;
end $$;

-- Keep the surviving local/snapshot creator self-contained: it explicitly
-- creates its temporary legacy owner membership in the same transaction.
create or replace function public.create_organization_conference_idempotent(
  p_operation_id uuid,p_requested_conference_id uuid,p_organization_id uuid,
  p_name text,p_initial_metadata jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); prior public.conference_creation_operations%rowtype;
  normalized_name text:=btrim(coalesce(p_name,'')); access_status text;
begin
  if actor_id is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_operation_id is null or p_requested_conference_id is null or p_organization_id is null
    or normalized_name='' or length(normalized_name)>500
    or jsonb_typeof(coalesce(p_initial_metadata,'{}'::jsonb))<>'object' then
    raise exception 'INVALID_CONFERENCE_REQUEST' using errcode='22023';
  end if;
  select account_status into access_status from public.system_user_access where user_id=actor_id;
  if access_status<>'approved' or not public.can_user_create_conferences(actor_id) then
    raise exception 'CONFERENCE_CREATION_NOT_ALLOWED' using errcode='42501';
  end if;
  if not exists(select 1 from public.organizations o where o.id=p_organization_id and o.status='active')
    or not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=actor_id) then
    raise exception 'ACTIVE_ORGANIZATION_MEMBERSHIP_REQUIRED' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(actor_id::text||':conference-create:'||p_operation_id::text,0));
  select * into prior from public.conference_creation_operations where user_id=actor_id and operation_id=p_operation_id;
  if found then
    if prior.conference_id<>p_requested_conference_id then raise exception 'OPERATION_RESULT_MISMATCH' using errcode='22023'; end if;
    return jsonb_build_object('status','duplicate','operationId',p_operation_id,'conferenceId',prior.conference_id,'created',false);
  end if;
  if exists(select 1 from public.conferences where id=p_requested_conference_id) then
    raise exception 'CONFERENCE_ID_ALREADY_USED' using errcode='23505';
  end if;
  insert into public.conferences(id,name,owner_id,organization_id)
  values(p_requested_conference_id,normalized_name,actor_id,p_organization_id);
  insert into public.conference_members(conference_id,user_id,role)
  values(p_requested_conference_id,actor_id,'owner');
  insert into public.conference_creation_operations(user_id,operation_id,conference_id,initial_metadata)
  values(actor_id,p_operation_id,p_requested_conference_id,coalesce(p_initial_metadata,'{}'::jsonb));
  return jsonb_build_object('status','created','operationId',p_operation_id,'conferenceId',p_requested_conference_id,'created',true);
end $$;

revoke all on function public.create_organization_conference_idempotent(
  uuid,uuid,uuid,text,jsonb
) from public,anon,authenticated,service_role;

drop trigger conferences_add_owner_membership on public.conferences;
drop function public.add_conference_owner_membership();

create function public.create_canonical_conference(
  p_actor_device_id uuid,
  p_operation_id uuid,
  p_requested_conference_id uuid,
  p_organization_id uuid,
  p_name text,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_device_authorization_id uuid;
  v_name text:=btrim(coalesce(p_name,''));
  v_intent jsonb;
  v_prior public.conference_creation_operations%rowtype;
  v_result jsonb;
begin
  if p_operation_id is null or p_requested_conference_id is null
     or p_organization_id is null or v_name='' or char_length(v_name)>500
     or p_start_date is null or p_end_date is null or p_end_date<p_start_date then
    raise exception 'CANONICAL_CONFERENCE_CREATE_ARGUMENT_INVALID' using errcode='22023';
  end if;

  v_context:=public.require_effective_module_permission(
    p_actor_device_id,'conference','conference.lifecycle.create',null,null
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization_id:=platform_private.validated_phase1c_device_authorization(
    v_actor,p_actor_device_id
  );
  if v_device_authorization_id is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;

  v_intent:=jsonb_build_object(
    'contract','canonical-platform-conference-create-v1',
    'conferenceId',p_requested_conference_id,
    'organizationId',p_organization_id,
    'name',v_name,
    'startDate',p_start_date,
    'endDate',p_end_date
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text||':conference-create:'||p_operation_id::text,0)
  );
  select operations.* into v_prior
  from public.conference_creation_operations operations
  where operations.user_id=v_actor and operations.operation_id=p_operation_id;
  if found then
    if v_prior.conference_id<>p_requested_conference_id
       or v_prior.initial_metadata<>v_intent then
      raise exception 'CANONICAL_CONFERENCE_CREATE_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return jsonb_build_object(
      'status','duplicate','operationId',p_operation_id,
      'conferenceId',p_requested_conference_id,'organizationId',p_organization_id,
      'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
      'conferenceStatus','active','completedAt',null,'revision',1,'created',false
    );
  end if;

  if not exists(
    select 1 from public.organizations organizations
    where organizations.id=p_organization_id and organizations.status='active'
  ) then
    raise exception 'ACTIVE_ORGANIZATION_REQUIRED' using errcode='23503';
  end if;
  if exists(select 1 from public.conferences where id=p_requested_conference_id) then
    raise exception 'CONFERENCE_ID_ALREADY_USED' using errcode='23505';
  end if;

  insert into public.conferences(
    id,name,owner_id,organization_id,start_date,end_date,status,
    completed_at,revision,updated_by
  ) values(
    p_requested_conference_id,v_name,v_actor,p_organization_id,
    p_start_date,p_end_date,'active',null,1,v_actor
  );

  insert into public.conference_creation_operations(
    user_id,operation_id,conference_id,initial_metadata
  ) values(v_actor,p_operation_id,p_requested_conference_id,v_intent);

  v_result:=jsonb_build_object(
    'status','created','operationId',p_operation_id,
    'conferenceId',p_requested_conference_id,'organizationId',p_organization_id,
    'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
    'conferenceStatus','active','completedAt',null,'revision',1,'created',true
  );
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,subject_user_id,
    domain,module,action,entity_type,entity_id,scope_type,scope_id,
    old_values,new_values,metadata,operation_id,source
  ) values(
    v_actor,v_device_authorization_id,null,
    'platform','conference','conference.lifecycle.created',
    'conference',p_requested_conference_id,'platform',null,
    null,jsonb_build_object(
      'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
      'status','active','completedAt',null,'revision',1,
      'organizationId',p_organization_id
    ),jsonb_build_object(
      'permissionKey','conference.lifecycle.create',
      'authoritySource',v_context->>'authoritySource',
      'grantId',v_context->'grantId',
      'deviceId',p_actor_device_id
    ),p_operation_id,'rpc'
  );
  return v_result;
end $$;

revoke all on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) from public,anon,authenticated,service_role;

-- Keep the existing Phase1C dispatcher as the single entry boundary. Route
-- canonical handlers explicitly and delegate unchanged legacy operations to
-- the reviewed core; future canonical branches require no function-text edit.
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

  if p_operation='create_canonical_conference' then
    perform platform_private.require_exact_jsonb_keys(
      p_args,array[
        'p_operation_id','p_requested_conference_id','p_organization_id',
        'p_name','p_start_date','p_end_date'
      ]
    );
    return public.create_canonical_conference(
      v_session.device_id,(p_args->>'p_operation_id')::uuid,
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
      v_session.device_id,(p_args->>'p_conference_id')::uuid,
      (p_args->>'p_expected_revision')::bigint,p_args->>'p_name',
      (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,
      p_args->>'p_status'
    );
  end if;

  return platform.execute_conference_device_operation_phase1c_core(
    p_user_id,p_session_id,p_token_hash,p_operation,p_args
  );
end $$;

revoke all on function platform.execute_conference_device_operation(
  uuid,uuid,bytea,text,jsonb
) from public,anon,authenticated,service_role;
grant execute on function platform.execute_conference_device_operation(
  uuid,uuid,bytea,text,jsonb
) to service_role;

comment on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) is
'P3B canonical server Conference creation. The verified Platform session supplies actor/device; module-scoped conference.lifecycle.create is the sole authority; organization_id is validated business data; the existing Conference creation ledger provides actor-scoped idempotency.';

commit;
