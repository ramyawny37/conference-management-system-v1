begin;

-- Restore only the final server-native Conference creation capability after
-- Conference membership retirement. Platform permissions remain the sole authority.
do $$
begin
  if to_regclass('public.conferences') is null
     or to_regclass('public.conference_creation_operations') is null
     or to_regclass('public.organizations') is null
     or to_regclass('public.module_permission_catalog') is null
     or to_regclass('public.module_permission_grants') is null
     or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.require_exact_jsonb_keys(jsonb,text[],text[])') is null
     or to_regprocedure('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)') is null then
    raise exception 'FINAL_CANONICAL_CONFERENCE_CREATION_FOUNDATION_REQUIRED' using errcode='55000';
  end if;

  if to_regclass('public.conference_members') is not null
     or to_regprocedure('public.is_conference_member(uuid)') is not null
     or exists(
       select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname in(
         'has_conference_role','create_organization_conference_idempotent',
         'device_guarded_create_organization_conference_idempotent'
       )
     ) then
    raise exception 'RETIRED_CONFERENCE_AUTHORITY_MUST_REMAIN_ABSENT' using errcode='55000';
  end if;

  if exists(
    select 1 from (values
      ('conference.lifecycle.create','module',null::text),
      ('conference.access.view','resource','conference'),
      ('conference.lifecycle.manage','resource','conference')
    ) expected(permission_key,scope_mode,resource_type)
    where not exists(
      select 1 from public.module_permission_catalog catalog
      where catalog.permission_key=expected.permission_key
        and catalog.module_key='conference' and catalog.status='active'
        and catalog.allowed_scope_mode=expected.scope_mode
        and catalog.allowed_resource_type is not distinct from expected.resource_type
    )
  ) then
    raise exception 'FINAL_CANONICAL_CONFERENCE_PERMISSION_CONTRACT_REQUIRED' using errcode='55000';
  end if;
end $$;

create or replace function public.create_canonical_conference(
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
  v_permission text;
  v_grant_ids jsonb:='{}'::jsonb;
  v_grant_id uuid;
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
    'contract','final-canonical-conference-create-v1',
    'conferenceId',p_requested_conference_id,'organizationId',p_organization_id,
    'name',v_name,'startDate',p_start_date,'endDate',p_end_date
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
    if not exists(
      select 1 from public.conferences conference
      where conference.id=p_requested_conference_id and conference.deleted_at is null
    ) or exists(
      select 1 from (values('conference.access.view'),('conference.lifecycle.manage')) expected(permission_key)
      where not exists(
        select 1 from public.module_permission_grants grants
        where grants.user_id=v_actor and grants.module_key='conference'
          and grants.permission_key=expected.permission_key
          and grants.resource_type='conference'
          and grants.resource_id=p_requested_conference_id::text
          and grants.revoked_at is null
      )
    ) then
      raise exception 'CANONICAL_CONFERENCE_CREATE_REPLAY_STATE_INVALID' using errcode='55000';
    end if;
    return jsonb_build_object(
      'status','duplicate','operationId',p_operation_id,
      'conferenceId',p_requested_conference_id,'organizationId',p_organization_id,
      'name',v_name,'startDate',p_start_date,'endDate',p_end_date,
      'conferenceStatus','active','completedAt',null,'revision',1,'created',false
    );
  end if;

  if not exists(
    select 1 from public.organizations organization
    where organization.id=p_organization_id and organization.status='active'
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

  foreach v_permission in array array[
    'conference.access.view','conference.lifecycle.manage'
  ] loop
    insert into public.module_permission_grants(
      user_id,module_key,permission_key,resource_type,resource_id,
      granted_by,granted_by_device_id
    ) values(
      v_actor,'conference',v_permission,'conference',p_requested_conference_id::text,
      v_actor,p_actor_device_id
    ) returning grant_id into v_grant_id;
    v_grant_ids:=v_grant_ids||jsonb_build_object(v_permission,v_grant_id);
  end loop;

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
      'authorityGrantId',v_context->'grantId',
      'creatorResourceGrants',v_grant_ids,'deviceId',p_actor_device_id
    ),p_operation_id,'rpc'
  );
  return v_result;
end $$;

revoke all on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) from public,anon,authenticated,service_role;

-- Preserve the one verified-session dispatcher. Add the canonical creation
-- branch only when this post-P3A Development state does not already have it.
do $$
declare
  v_signature regprocedure:=
    'platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)'::regprocedure;
  v_definition text:=pg_get_functiondef(v_signature);
  v_router_signature regprocedure:=to_regprocedure(
    'platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'
  );
  v_router_definition text;
  v_marker text:='if p_operation=''mutate_conference_core'' then';
  v_branch text:='if p_operation=''create_canonical_conference'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_requested_conference_id'',''p_organization_id'',''p_name'',''p_start_date'',''p_end_date'']); return public.create_canonical_conference(v_session.device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_requested_conference_id'')::uuid,(p_args->>''p_organization_id'')::uuid,p_args->>''p_name'',(p_args->>''p_start_date'')::date,(p_args->>''p_end_date'')::date); elsif p_operation=''mutate_conference_core'' then';
  v_route_count integer;
begin
  v_route_count:=(length(v_definition)-length(replace(v_definition,
    'p_operation=''create_canonical_conference''','')))
    / length('p_operation=''create_canonical_conference''');
  if v_route_count=0 and v_router_signature is not null then
    v_router_definition:=pg_get_functiondef(v_router_signature);
    v_route_count:=(length(v_router_definition)-length(replace(v_router_definition,
      'p_operation=''create_canonical_conference''','')))
      / length('p_operation=''create_canonical_conference''');
    if v_route_count<>1
       or position('public.create_canonical_conference(p_actor_device_id' in v_router_definition)=0 then
      raise exception 'FINAL_CANONICAL_CONFERENCE_ROUTER_CONFLICT' using errcode='55000';
    end if;
  elsif v_route_count=0 then
    if (length(v_definition)-length(replace(v_definition,v_marker,'')))
       / length(v_marker)<>1 then
      raise exception 'FINAL_CANONICAL_CONFERENCE_DISPATCH_PRECONDITION_FAILED' using errcode='55000';
    end if;
    execute replace(v_definition,v_marker,v_branch);
    v_definition:=pg_get_functiondef(v_signature);
    v_route_count:=(length(v_definition)-length(replace(v_definition,
      'p_operation=''create_canonical_conference''','')))
      / length('p_operation=''create_canonical_conference''');
  end if;
  if v_route_count<>1 or (
    v_router_signature is null
    and position('public.create_canonical_conference(v_session.device_id' in v_definition)=0
  ) then
    raise exception 'FINAL_CANONICAL_CONFERENCE_DISPATCH_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end $$;

comment on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) is
'Final canonical Conference creation. The verified Platform session supplies actor/device; conference.lifecycle.create admits creation; exact conference.access.view and conference.lifecycle.manage resource grants make the created Conference discoverable and mutable without membership or role authority.';

commit;
