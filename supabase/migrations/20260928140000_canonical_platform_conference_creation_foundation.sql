begin;

-- P3B adds the server-native Conference creation operation. The legacy
-- Organization-authorized publishing operation remains for its existing
-- local/snapshot consumers and is not called by this operation.
do $$
begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.conference_creation_operations') is null
     or to_regclass('public.organizations') is null
     or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.phase1c_context_device_id()') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)') is null
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

-- The historical insert trigger bootstraps owner membership. Canonical
-- Platform creation deliberately has no Conference/Organization membership
-- authority, so only the protected canonical insert suppresses that legacy
-- compatibility side effect.
create or replace function public.add_conference_owner_membership()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_phase1c_device_id uuid:=platform_private.phase1c_context_device_id();
begin
  if nullif(pg_catalog.current_setting('platform.canonical_conference_create_actor',true),'')::uuid
       is not distinct from new.owner_id
     and v_phase1c_device_id is not null
     and platform_private.validated_phase1c_device_authorization(
       new.owner_id,v_phase1c_device_id
     ) is not null then
    return new;
  end if;
  insert into public.conference_members(conference_id,user_id,role)
  values(new.id,new.owner_id,'owner');
  return new;
end $$;

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

  perform pg_catalog.set_config(
    'platform.canonical_conference_create_actor',v_actor::text,true
  );
  insert into public.conferences(
    id,name,owner_id,organization_id,start_date,end_date,status,
    completed_at,revision,updated_by
  ) values(
    p_requested_conference_id,v_name,v_actor,p_organization_id,
    p_start_date,p_end_date,'active',null,1,v_actor
  );
  perform pg_catalog.set_config('platform.canonical_conference_create_actor','',true);

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

-- Extend the reviewed verified-device Conference dispatcher with one isolated
-- canonical operation. Existing legacy cases remain unchanged.
do $$
declare
  v_signature regprocedure:=
    'platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)'::regprocedure;
  v_definition text;
  v_marker text:='else raise exception ''CONFERENCE_OPERATION_NOT_ALLOWED'' using errcode=''42501'';';
  v_branch text:='when ''create_canonical_conference'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_requested_conference_id'',''p_organization_id'',''p_name'',''p_start_date'',''p_end_date'']); v_result:=public.create_canonical_conference(v_session.device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_requested_conference_id'')::uuid,(p_args->>''p_organization_id'')::uuid,p_args->>''p_name'',(p_args->>''p_start_date'')::date,(p_args->>''p_end_date'')::date); ';
  v_occurrences integer;
begin
  v_definition:=pg_get_functiondef(v_signature);
  if position('when ''create_canonical_conference'' then' in v_definition)<>0 then
    raise exception 'P3B_CANONICAL_CREATE_DISPATCH_ALREADY_EXISTS' using errcode='55000';
  end if;
  v_occurrences:=(length(v_definition)-length(replace(v_definition,v_marker,'')))
    / length(v_marker);
  if v_occurrences<>1 then
    raise exception 'P3B_CONFERENCE_DISPATCH_PRECONDITION_FAILED' using errcode='55000';
  end if;
  execute replace(v_definition,v_marker,v_branch||v_marker);
  v_definition:=pg_get_functiondef(v_signature);
  if position('when ''create_canonical_conference'' then' in v_definition)=0
     or position('public.create_canonical_conference(v_session.device_id' in v_definition)=0
     or position('device_guarded_create_organization_conference_idempotent' in v_branch)<>0 then
    raise exception 'P3B_CONFERENCE_DISPATCH_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end $$;

comment on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) is
'P3B canonical server Conference creation. The verified Platform session supplies actor/device; module-scoped conference.lifecycle.create is the sole authority; organization_id is validated business data; the existing Conference creation ledger provides actor-scoped idempotency.';

commit;
