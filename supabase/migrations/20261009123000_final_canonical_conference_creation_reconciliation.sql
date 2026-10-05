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
     or to_regprocedure('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)') is null
     or to_regprocedure('platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb)') is null
     or to_regprocedure('public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text)') is null
     or to_regprocedure('public.list_accessible_conferences(uuid)') is null then
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

-- One deterministic owner for canonical Conference lifecycle and discovery.
-- The outer dispatcher alone establishes the verified session and supplies the
-- server-derived device. Unmatched Platform operations continue to the final
-- non-canonical core, which fails closed for unknown operations.
create or replace function platform_private.route_canonical_conference_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_actor_device_id uuid,
  p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if p_operation='create_canonical_conference' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[
      'p_operation_id','p_requested_conference_id','p_organization_id',
      'p_name','p_start_date','p_end_date'
    ]);
    return public.create_canonical_conference(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_requested_conference_id')::uuid,
      (p_args->>'p_organization_id')::uuid,p_args->>'p_name',
      (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date
    );
  elsif p_operation='mutate_conference_core' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[
      'p_operation_id','p_conference_id','p_expected_revision','p_name',
      'p_place','p_start_date','p_end_date','p_status'
    ]);
    return public.mutate_conference_core(
      p_actor_device_id,(p_args->>'p_operation_id')::uuid,
      (p_args->>'p_conference_id')::uuid,
      (p_args->>'p_expected_revision')::bigint,p_args->>'p_name',
      p_args->>'p_place',(p_args->>'p_start_date')::date,
      (p_args->>'p_end_date')::date,p_args->>'p_status'
    );
  elsif p_operation='list_accessible_conferences' then
    perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
    return public.list_accessible_conferences(p_actor_device_id);
  elsif p_operation='get_conference_core' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_core(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='list_conference_participations' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.list_conference_participations(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='create_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_person_id']);
    return public.create_conference_participation(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_person_id')::uuid);
  elsif p_operation='create_conference_participation_with_person' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_full_name','p_phone','p_gender','p_date_of_birth','p_church']);
    return public.create_conference_participation_with_person(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_full_name',p_args->>'p_phone',p_args->>'p_gender',(p_args->>'p_date_of_birth')::date,p_args->>'p_church');
  elsif p_operation='set_conference_participation_status' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision','p_status']);
    return public.set_conference_participation_status(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_status');
  elsif p_operation='set_conference_participation_guardian' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision','p_guardian_participation_id']);
    return public.set_conference_participation_guardian(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint,(p_args->>'p_guardian_participation_id')::uuid);
  elsif p_operation='delete_conference_participation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_participation_id','p_expected_revision']);
    return public.delete_conference_participation(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation in('create_accommodation_house','update_accommodation_house','delete_accommodation_house','create_accommodation_floor','update_accommodation_floor','delete_accommodation_floor','create_accommodation_room','update_accommodation_room','delete_accommodation_room') then
    return public.mutate_conference_accommodation_structure(p_actor_device_id,replace(p_operation,'_accommodation_','_'),p_args);
  elsif p_operation='assign_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_room_id','p_participation_id','p_arrival_day','p_leave_day','p_bed_type','p_extra_bed_person_type']);
    return public.assign_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_room_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_arrival_day')::integer,(p_args->>'p_leave_day')::integer,p_args->>'p_bed_type',p_args->>'p_extra_bed_person_type');
  elsif p_operation='move_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_occupancy_id','p_expected_revision','p_room_id','p_arrival_day','p_leave_day','p_bed_type','p_extra_bed_person_type']);
    return public.move_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_occupancy_id')::uuid,(p_args->>'p_expected_revision')::bigint,(p_args->>'p_room_id')::uuid,(p_args->>'p_arrival_day')::integer,(p_args->>'p_leave_day')::integer,p_args->>'p_bed_type',p_args->>'p_extra_bed_person_type');
  elsif p_operation='remove_conference_accommodation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_occupancy_id','p_expected_revision']);
    return public.remove_conference_accommodation(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_occupancy_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_transport' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_transport(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_transport_vehicle' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_operation','p_conference_id','p_vehicle_id','p_expected_revision','p_name','p_icon','p_capacity','p_position','p_remove_overflow']);
    return public.mutate_conference_transport_vehicle(p_actor_device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_operation',(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_vehicle_id','')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->>'p_name',p_args->>'p_icon',nullif(p_args->>'p_capacity','')::integer,nullif(p_args->>'p_position','')::integer,coalesce((p_args->>'p_remove_overflow')::boolean,false));
  elsif p_operation='set_conference_transport_assignment' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_participation_id','p_vehicle_id','p_mode','p_rider_kind','p_seat_number','p_expected_revision']);
    return public.set_conference_transport_assignment(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_participation_id')::uuid,(p_args->>'p_vehicle_id')::uuid,p_args->>'p_mode',p_args->>'p_rider_kind',nullif(p_args->>'p_seat_number','')::integer,nullif(p_args->>'p_expected_revision','')::bigint);
  elsif p_operation='remove_conference_transport_assignment' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_assignment_id','p_expected_revision']);
    return public.remove_conference_transport_assignment(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_assignment_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  elsif p_operation='get_conference_restaurant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_restaurant(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_restaurant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_operation','p_conference_id','p_expected_revision','p_payload']);
    return public.mutate_conference_restaurant(p_actor_device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_operation',(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->'p_payload');
  elsif p_operation='mutate_conference_accommodation_pricing' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_expected_revision','p_payload']);
    return public.mutate_conference_accommodation_pricing(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,nullif(p_args->>'p_expected_revision','')::bigint,p_args->'p_payload');
  elsif p_operation='get_conference_air_conditioning' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_air_conditioning(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_air_conditioning' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_scope','p_scope_id','p_action','p_expected_revision','p_configuration']);
    return public.mutate_conference_air_conditioning(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_scope',nullif(p_args->>'p_scope_id','')::uuid,p_args->>'p_action',(p_args->>'p_expected_revision')::bigint,p_args->'p_configuration');
  elsif p_operation='get_conference_finance' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_finance(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_finance' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_entity','p_action','p_entity_id','p_expected_revision','p_payload']);
    return public.mutate_conference_finance(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_entity',p_args->>'p_action',nullif(p_args->>'p_entity_id','')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  elsif p_operation='get_conference_branding' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.get_conference_branding(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='mutate_conference_branding' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_action','p_expected_revision','p_payload']);
    return public.mutate_conference_branding(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,p_args->>'p_action',(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  elsif p_operation='list_conference_activity' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    return public.list_conference_activity(p_actor_device_id,(p_args->>'p_conference_id')::uuid);
  elsif p_operation='record_conference_output_event' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_event']);
    return public.record_conference_output_event(p_actor_device_id,(p_args->>'p_conference_id')::uuid,p_args->>'p_event');
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
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_session platform_private.device_sessions%rowtype;
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
  if p_args ? 'p_actor_device_id'
     or (p_args ? 'p_device_id'
         and p_operation<>'approve_pending_device_authorization') then
    raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='22023';
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
) is 'One final internal canonical Conference lifecycle/discovery router. The outer Platform dispatcher supplies verified server-derived actor/device context; unmatched operations fail closed through the final Platform core.';

comment on function public.create_canonical_conference(
  uuid,uuid,uuid,uuid,text,date,date
) is
'Final canonical Conference creation. The verified Platform session supplies actor/device; conference.lifecycle.create admits creation; exact conference.access.view and conference.lifecycle.manage resource grants make the created Conference discoverable and mutable without membership or role authority.';

commit;
