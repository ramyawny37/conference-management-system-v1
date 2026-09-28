begin;

do $$
begin
  if to_regclass('platform.people') is null or to_regclass('public.conferences') is null
     or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)') is null then
    raise exception 'P4B_CANONICAL_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
  if not exists(select 1 from public.module_permission_catalog where permission_key='conference.people.view' and module_key='conference' and status='active' and allowed_scope_mode='resource' and allowed_resource_type='conference')
     or not exists(select 1 from public.module_permission_catalog where permission_key='conference.people.manage' and module_key='conference' and status='active' and allowed_scope_mode='resource' and allowed_resource_type='conference') then
    raise exception 'P4B_PERMISSION_CONTRACT_REQUIRED' using errcode='55000';
  end if;
end $$;

create table public.conference_participations(
  id uuid primary key default extensions.gen_random_uuid(),
  conference_id uuid not null references public.conferences(id) on delete restrict,
  person_id uuid not null references platform.people(id) on delete restrict,
  status text not null default 'active' check(status in('active','apologized')),
  revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id) on delete restrict,
  updated_by uuid not null references platform.profiles(user_id) on delete restrict,
  unique(conference_id,person_id)
);
create index conference_participations_list_idx on public.conference_participations(conference_id,status,created_at,id);

create table public.conference_participation_operations(
  actor_user_id uuid not null references platform.profiles(user_id) on delete restrict,
  operation_id uuid not null,
  operation text not null check(operation in('create','set_status','delete')),
  request jsonb not null check(jsonb_typeof(request)='object'),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_at timestamptz not null default statement_timestamp(),
  primary key(actor_user_id,operation_id)
);

alter table public.conference_participations enable row level security;
alter table public.conference_participations force row level security;
alter table public.conference_participation_operations enable row level security;
alter table public.conference_participation_operations force row level security;
revoke all on table public.conference_participations,public.conference_participation_operations from public,anon,authenticated,service_role;

create function platform_private.require_conference_participation_context(p_device_id uuid,p_conference_id uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_conference public.conferences%rowtype; v_actor uuid;
begin
  if p_conference_id is null or p_permission not in('conference.people.view','conference.people.manage') then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_context:=public.require_effective_module_permission(p_device_id,'conference',p_permission,'conference',p_conference_id::text);
  v_actor:=(v_context->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(v_actor,p_device_id) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  select * into v_conference from public.conferences where id=p_conference_id;
  if not found or v_conference.deleted_at is not null then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mutation and v_conference.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000'; end if;
  return v_context;
end $$;

create function public.list_conference_participations(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_items jsonb; v_total bigint; v_active bigint; v_apologized bigint;
begin
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.view',false);
  select count(*),count(*) filter(where status='active'),count(*) filter(where status='apologized'),
    coalesce(jsonb_agg(jsonb_build_object('participationId',id,'conferenceId',conference_id,'personId',person_id,'status',status,'revision',revision,'createdAt',created_at,'updatedAt',updated_at,'createdBy',created_by,'updatedBy',updated_by) order by created_at,id),'[]'::jsonb)
  into v_total,v_active,v_apologized,v_items from public.conference_participations where conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'totalCount',v_total,'activeCount',v_active,'apologizedCount',v_apologized,'items',v_items);
end $$;

create function public.create_conference_participation(p_actor_device_id uuid,p_operation_id uuid,p_conference_id uuid,p_person_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_row public.conference_participations%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_person_id is null then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.manage',true); v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  v_request:=jsonb_build_object('conferenceId',p_conference_id,'personId',p_person_id);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then if v_prior.operation<>'create' or v_prior.request<>v_request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return v_prior.result; end if;
  if not exists(select 1 from platform.people where id=p_person_id) then raise exception 'PLATFORM_PERSON_NOT_FOUND' using errcode='23503'; end if;
  if exists(select 1 from public.conference_participations where conference_id=p_conference_id and person_id=p_person_id) then raise exception 'CONFERENCE_PARTICIPATION_ALREADY_EXISTS' using errcode='23505'; end if;
  insert into public.conference_participations(conference_id,person_id,created_by,updated_by) values(p_conference_id,p_person_id,v_actor,v_actor) returning * into v_row;
  v_result:=jsonb_build_object('participationId',v_row.id,'conferenceId',v_row.conference_id,'personId',v_row.person_id,'status',v_row.status,'revision',v_row.revision,'createdAt',v_row.created_at,'updatedAt',v_row.updated_at,'createdBy',v_row.created_by,'updatedBy',v_row.updated_by);
  insert into public.conference_participation_operations values(v_actor,p_operation_id,'create',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(v_actor,v_device_authorization,'platform','conference','conference.participation.created','conference_participation',v_row.id,'platform',null,jsonb_build_object('conferenceId',p_conference_id,'personId',p_person_id,'status','active','revision',1),jsonb_build_object('permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

create function public.set_conference_participation_status(p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_current public.conference_participations%rowtype; v_updated public.conference_participations%rowtype; v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null or p_expected_revision<1 or p_status not in('active','apologized') then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  select * into v_current from public.conference_participations where id=p_participation_id; if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,v_current.conference_id,'conference.people.manage',true); v_actor:=(v_context->>'actorUserId')::uuid; v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision,'status',p_status); perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id; if found then if v_prior.operation<>'set_status' or v_prior.request<>v_request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return v_prior.result; end if;
  select * into v_current from public.conference_participations where id=p_participation_id for update; if v_current.revision<>p_expected_revision then raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001'; end if;
  update public.conference_participations set status=p_status,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=p_participation_id returning * into v_updated;
  v_result:=jsonb_build_object('participationId',v_updated.id,'conferenceId',v_updated.conference_id,'personId',v_updated.person_id,'status',v_updated.status,'revision',v_updated.revision,'updatedAt',v_updated.updated_at,'updatedBy',v_updated.updated_by);
  insert into public.conference_participation_operations values(v_actor,p_operation_id,'set_status',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(v_actor,v_device_authorization,'platform','conference','conference.participation.status_changed','conference_participation',v_updated.id,'platform',jsonb_build_object('status',v_current.status,'revision',v_current.revision),jsonb_build_object('status',v_updated.status,'revision',v_updated.revision),jsonb_build_object('conferenceId',v_updated.conference_id,'personId',v_updated.person_id,'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc'); return v_result;
end $$;

create function public.delete_conference_participation(p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_current public.conference_participations%rowtype; v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null or p_expected_revision<1 then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_actor:=auth.uid();
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'delete' or v_prior.request<>v_request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if;
    perform platform_private.require_conference_participation_context(p_actor_device_id,(v_prior.result->>'conferenceId')::uuid,'conference.people.manage',true);
    return v_prior.result;
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id; if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,v_current.conference_id,'conference.people.manage',true); v_actor:=(v_context->>'actorUserId')::uuid; v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  select * into v_current from public.conference_participations where id=p_participation_id for update; if v_current.revision<>p_expected_revision then raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001'; end if;
  delete from public.conference_participations where id=p_participation_id; v_result:=jsonb_build_object('participationId',p_participation_id,'conferenceId',v_current.conference_id,'personId',v_current.person_id,'deleted',true);
  insert into public.conference_participation_operations values(v_actor,p_operation_id,'delete',v_request,v_result,statement_timestamp()); insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(v_actor,v_device_authorization,'platform','conference','conference.participation.deleted','conference_participation',p_participation_id,'platform',jsonb_build_object('conferenceId',v_current.conference_id,'personId',v_current.person_id,'status',v_current.status,'revision',v_current.revision),null,jsonb_build_object('permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc'); return v_result;
end $$;

revoke all on function platform_private.require_conference_participation_context(uuid,uuid,text,boolean),public.list_conference_participations(uuid,uuid),public.create_conference_participation(uuid,uuid,uuid,uuid),public.set_conference_participation_status(uuid,uuid,uuid,bigint,text),public.delete_conference_participation(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;
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
  elsif p_operation='list_conference_participations' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.list_conference_participations(v_session.device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='create_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_person_id']);
    return public.create_conference_participation(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_person_id')::uuid);
  elsif p_operation='set_conference_participation_status' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision','p_status']);
    return public.set_conference_participation_status(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_status');
  elsif p_operation='delete_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision']);
    return public.delete_conference_participation(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  end if;

  return platform.execute_conference_device_operation_phase1c_core(
    p_user_id,p_session_id,p_token_hash,p_operation,p_args
  );
end $$;


revoke all on function platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb) to service_role;
comment on table public.conference_participations is 'Canonical Conference participation linking one platform.people identity to one Conference. Apologized remains visible but inactive; completed Conferences are read-only.';
comment on table public.conference_participation_operations is 'P4B actor-scoped idempotency ledger for canonical participation mutations.';
commit;
