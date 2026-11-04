begin;

do $$
begin
  if to_regclass('public.module_permission_catalog') is null
     or to_regclass('public.module_permission_grants') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('reservations_private.resolve_event_scope(uuid,uuid,text)') is null then
    raise exception 'RESERVATIONS_AUTHORIZATION_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end;
$$;

insert into public.module_permission_catalog(
  permission_key,module_key,display_name,description,status,
  allowed_scope_mode,allowed_resource_type,sensitive_mutation,catalog_version
) values (
  'reservations.event.create','reservations','إنشاء فعاليات الحجز',
  'إنشاء فعالية حجز جديدة داخل نطاق مصرح به.','active','module',null,true,1
);

update public.module_permission_catalog
set allowed_scope_mode='both',allowed_resource_type='event',catalog_version=catalog_version+1
where module_key='reservations'
  and status='active'
  and permission_key in(
    'reservations.event.view','reservations.event.manage',
    'reservations.booking.view','reservations.booking.create','reservations.booking.update','reservations.booking.delete',
    'reservations.payment.view','reservations.payment.record','reservations.payment.void',
    'reservations.attendance.view','reservations.attendance.manage',
    'reservations.operations.view','reservations.operations.manage'
  )
  and (allowed_scope_mode,coalesce(allowed_resource_type,'')) is distinct from ('both','event');

alter table public.module_grant_operations
  drop constraint module_grant_operations_authority_source_check,
  add constraint module_grant_operations_authority_source_check check (
    authority_source in ('system_owner','module_grant','business_rule')
  ),
  drop constraint module_grant_operations_authority_check,
  add constraint module_grant_operations_authority_check check (
    (authority_source='system_owner' and authority_grant_id is null)
    or (authority_source='module_grant' and authority_grant_id is not null)
    or (authority_source='business_rule' and authority_grant_id is null)
  );

alter table public.module_grant_audit_log
  drop constraint module_grant_audit_log_authority_source_check,
  add constraint module_grant_audit_log_authority_source_check check (
    authority_source in ('system_owner','module_grant','business_rule')
  ),
  drop constraint module_grant_audit_log_authority_check,
  add constraint module_grant_audit_log_authority_check check (
    (authority_source='system_owner' and authority_grant_id is null)
    or (authority_source='module_grant' and authority_grant_id is not null)
    or (authority_source='business_rule' and authority_grant_id is null)
  );

-- Preserve the historical create ability of active module-wide event managers.
insert into public.module_permission_grants(
  user_id,module_key,permission_key,resource_type,resource_id,
  granted_by,granted_by_device_id,granted_at
)
select manager.user_id,'reservations','reservations.event.create',null,null,
       manager.granted_by,manager.granted_by_device_id,statement_timestamp()
from public.module_permission_grants manager
where manager.module_key='reservations'
  and manager.permission_key='reservations.event.manage'
  and manager.resource_type is null and manager.resource_id is null
  and manager.revoked_at is null
  and not exists(
    select 1 from public.module_permission_grants existing
    where existing.user_id=manager.user_id
      and existing.module_key='reservations'
      and existing.permission_key='reservations.event.create'
      and existing.resource_type is null and existing.resource_id is null
      and existing.revoked_at is null
  );

create or replace function reservations_private.resolve_event_scope(
  p_device_id uuid,p_event_id uuid,p_permission text
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_event reservations.events%rowtype; v_context jsonb; v_actor uuid;
begin
  select * into v_event from reservations.events where id=p_event_id;
  if not found then raise exception 'RESERVATIONS_EVENT_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=public.require_effective_module_permission(
    p_device_id,'reservations',p_permission,'event',p_event_id::text
  );
  v_actor:=(v_context->>'actorUserId')::uuid;
  if v_event.scope_type='conference' then
    if not exists(
      select 1 from public.conferences c
      join public.organizations o on o.id=c.organization_id and o.status='active'
      join public.organization_members om on om.organization_id=c.organization_id and om.user_id=v_actor
      where c.id=v_event.conference_id and c.organization_id=v_event.organization_id and c.deleted_at is null
    ) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
  elsif v_event.scope_type<>'standalone' then
    raise exception 'RESERVATIONS_SCOPE_TYPE_INVALID' using errcode='22023';
  end if;
  return v_context||jsonb_build_object(
    'scopeType',v_event.scope_type,'scopePartitionId',v_event.scope_partition_id,
    'eventId',v_event.id,'conferenceId',v_event.conference_id,
    'organizationId',case when v_event.scope_type='conference' then v_event.organization_id end
  );
end $$;

create or replace function reservations_private.has_event_permission(
  p_actor uuid,p_permission text,p_event_id uuid
)
returns boolean language sql stable security definer set search_path='' as $$
  select public.is_system_owner(p_actor) or exists(
    select 1 from public.module_permission_grants g
    where g.user_id=p_actor and g.module_key='reservations'
      and g.permission_key=p_permission and g.revoked_at is null
      and ((g.resource_type is null and g.resource_id is null)
        or (g.resource_type='event' and g.resource_id=p_event_id::text))
  )
$$;

create or replace function reservations_private.booking_creation_context(
  p_device_id uuid,p_args jsonb
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid; v_conference_id uuid;
begin
  if p_args is null or jsonb_typeof(p_args)<>'object' then
    raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
  end if;
  perform public.validate_module_permission_catalog(
    'reservations','reservations.booking.create','event','00000000-0000-0000-0000-000000000000','authorize'
  );
  v_actor:=public.require_current_approved_device(p_device_id);
  if p_args ? 'p_conference_id' and not p_args ? 'p_scope_type' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    v_conference_id:=nullif(p_args->>'p_conference_id','')::uuid;
    if v_conference_id is null or not exists(
      select 1 from public.conferences c
      join public.organizations o on o.id=c.organization_id and o.status='active'
      join public.organization_members om on om.organization_id=c.organization_id and om.user_id=v_actor
      where c.id=v_conference_id and c.deleted_at is null
    ) then raise exception 'RESERVATIONS_CONFERENCE_ACCESS_REQUIRED' using errcode='42501'; end if;
  elsif p_args ? 'p_scope_type' and not p_args ? 'p_conference_id' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']);
    if p_args->>'p_scope_type'<>'standalone' then
      raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023';
    end if;
  else raise exception 'RESERVATIONS_READ_ARGUMENTS_INVALID' using errcode='22023'; end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',e.id,'conference_id',e.conference_id,'name',e.name,
      'start_date',e.start_date,'end_date',e.end_date,'location',e.location,
      'capacity',e.capacity,'status',e.status,'notes','','revision',e.revision,
      'bookingTypes',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',t.id,'event_id',t.event_id,'name',t.name,'code',t.code,
          'price',t.price,'active',t.active,'display_order',t.display_order,
          'eligible_attendance_segments',t.eligible_attendance_segments,'revision',t.revision
        ) order by t.display_order,t.id)
        from reservations.booking_types t where t.event_id=e.id and t.scope_partition_id=e.scope_partition_id and t.active
      ),'[]'::jsonb)
    ) order by e.start_date desc,e.id),'[]'::jsonb)
    from reservations.events e
    where e.status not in('closed','full')
      and ((v_conference_id is null and e.scope_type='standalone' and e.conference_id is null and e.organization_id is null)
        or (v_conference_id is not null and e.scope_type='conference' and e.conference_id=v_conference_id))
      and reservations_private.has_event_permission(v_actor,'reservations.booking.create',e.id)
  );
end $$;

alter function reservations.read(uuid,text,jsonb)
  rename to read_pre_authorization_architecture_reconciliation;

create function reservations.read(p_device_id uuid,p_operation text,p_args jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if p_operation='get_booking_creation_context' then
    return reservations_private.booking_creation_context(p_device_id,p_args);
  end if;
  -- Administrative reads retain their own read permission contract.
  if p_operation in('list_events','list_booking_types') then
    return reservations_private.read_scoped(p_device_id,p_operation,p_args);
  end if;
  return reservations.read_pre_authorization_architecture_reconciliation(p_device_id,p_operation,p_args);
end $$;

create or replace function platform_private.grant_deterministic_resource_permission(
  p_authorization_context jsonb,p_operation_id uuid,p_created_resource_id uuid
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_device uuid; v_verified jsonb; v_intent text;
        v_prior public.module_grant_operations%rowtype;
        v_grant public.module_permission_grants%rowtype;
        v_grant_id uuid; v_status text; v_result jsonb;
begin
  if p_authorization_context is null or jsonb_typeof(p_authorization_context)<>'object'
     or p_operation_id is null or p_created_resource_id is null
     or p_authorization_context->>'moduleKey'<>'reservations'
     or p_authorization_context->>'permissionKey'<>'reservations.event.create'
     or nullif(p_authorization_context->>'resourceType','') is not null
     or nullif(p_authorization_context->>'resourceId','') is not null then
    raise exception 'DETERMINISTIC_RESOURCE_GRANT_RULE_INVALID' using errcode='42501';
  end if;
  v_actor:=nullif(p_authorization_context->>'actorUserId','')::uuid;
  v_device:=nullif(p_authorization_context->>'actorDeviceId','')::uuid;
  if v_actor is null or v_device is null then
    raise exception 'DETERMINISTIC_RESOURCE_GRANT_CONTEXT_INVALID' using errcode='42501';
  end if;
  v_verified:=public.require_effective_module_permission(
    v_device,'reservations','reservations.event.create',null,null
  );
  if (v_verified->>'actorUserId')::uuid<>v_actor
     or (v_verified->>'actorDeviceId')::uuid<>v_device then
    raise exception 'DETERMINISTIC_RESOURCE_GRANT_CONTEXT_INVALID' using errcode='42501';
  end if;
  perform public.validate_module_permission_catalog(
    'reservations','reservations.event.manage','event',p_created_resource_id::text,'grant'
  );
  v_intent:=encode(extensions.digest(jsonb_build_object(
    'action','grant','actorUserId',v_actor,'actorDeviceId',v_device,
    'targetUserId',v_actor,'moduleKey','reservations',
    'sourcePermissionKey','reservations.event.create',
    'permissionKey','reservations.event.manage','resourceType','event',
    'resourceId',p_created_resource_id,'authoritySource','business_rule',
    'rule','resource_creator_ownership'
  )::text,'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('module-grant-operation:'||p_operation_id::text,0)
  );
  select * into v_prior from public.module_grant_operations where operation_id=p_operation_id;
  if found then
    if v_prior.intent_hash=v_intent then return v_prior.stored_result; end if;
    raise exception 'MODULE_GRANT_OPERATION_MISMATCH' using errcode='22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'module-grant:reservations:'||v_actor::text||':reservations.event.manage:event:'||p_created_resource_id::text,0
  ));
  select * into v_grant from public.module_permission_grants
  where user_id=v_actor and module_key='reservations'
    and permission_key='reservations.event.manage' and resource_type='event'
    and resource_id=p_created_resource_id::text and revoked_at is null for update;
  if found then
    v_grant_id:=v_grant.grant_id; v_status:='existing';
  else
    insert into public.module_permission_grants(
      user_id,module_key,permission_key,resource_type,resource_id,granted_by,granted_by_device_id
    ) values(
      v_actor,'reservations','reservations.event.manage','event',p_created_resource_id::text,v_actor,v_device
    ) returning grant_id into v_grant_id;
    v_status:='created';
  end if;
  v_result:=jsonb_build_object(
    'status',v_status,'grantId',v_grant_id,'targetUserId',v_actor,
    'moduleKey','reservations','permissionKey','reservations.event.manage',
    'resourceType','event','resourceId',p_created_resource_id,
    'authoritySource','business_rule','rule','resource_creator_ownership'
  );
  insert into public.module_grant_operations(
    operation_id,action,actor_user_id,actor_device_id,target_user_id,module_key,
    permission_key,resource_type,resource_id,requested_grant_id,resulting_grant_id,
    revocation_reason,authority_source,authority_grant_id,intent_hash,outcome,stored_result
  ) values(
    p_operation_id,'grant',v_actor,v_device,v_actor,'reservations',
    'reservations.event.manage','event',p_created_resource_id::text,null,v_grant_id,
    null,'business_rule',null,v_intent,v_status,v_result
  );
  if v_status='created' then
    insert into public.module_grant_audit_log(
      event_type,actor_user_id,actor_device_id,target_user_id,module_key,
      permission_key,resource_type,resource_id,grant_id,authority_source,
      authority_grant_id,operation_id,old_values,new_values
    ) values(
      'grant_created',v_actor,v_device,v_actor,'reservations',
      'reservations.event.manage','event',p_created_resource_id::text,v_grant_id,
      'business_rule',null,p_operation_id,'{}'::jsonb,
      jsonb_build_object('active',true,'permissionKey','reservations.event.manage',
        'resourceType','event','resourceId',p_created_resource_id,
        'authoritySource','business_rule','rule','resource_creator_ownership')
    );
  end if;
  return v_result;
end $$;

create or replace function reservations_private.create_event_authorized(
  p_device_id uuid,p_args jsonb
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_context jsonb; v_replay jsonb; v_result jsonb; v_actor uuid; v_partition uuid;
        v_event_id uuid; v_revision bigint; v_operation_id uuid:=(p_args->>'p_operation_id')::uuid;
begin
  if p_args->>'p_scope_type'='standalone' then
    perform reservations_private.standalone_create_business_args(p_args-'p_scope_type');
    v_context:=public.require_effective_module_permission(
      p_device_id,'reservations','reservations.event.create',null,null
    )||jsonb_build_object('scopeType','standalone');
    v_replay:=reservations_private.begin_standalone_create(v_operation_id,v_context,p_args-'p_scope_type');
    if v_replay is not null then return v_replay; end if;
    v_partition:=extensions.gen_random_uuid();
    v_context:=v_context||jsonb_build_object('scopePartitionId',v_partition);
  elsif p_args->>'p_scope_type'='conference' and nullif(p_args->>'p_conference_id','')::uuid is not null then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_scope_type','p_conference_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']);
    v_context:=reservations_private.conference_context(
      p_device_id,(p_args->>'p_conference_id')::uuid,'reservations.event.create'
    );
    v_replay:=reservations_private.begin_operation(v_operation_id,v_context,'create_event',p_args);
    if v_replay is not null then return v_replay; end if;
    v_partition:=(v_context->>'scopePartitionId')::uuid;
  else raise exception 'RESERVATIONS_CREATE_EVENT_SCOPE_INVALID' using errcode='22023'; end if;
  v_actor:=(v_context->>'actorUserId')::uuid;
  insert into reservations.events(
    scope_type,scope_partition_id,organization_id,conference_id,name,start_date,end_date,
    location,capacity,status,notes,created_by,updated_by
  ) values(
    p_args->>'p_scope_type',v_partition,nullif(v_context->>'organizationId','')::uuid,
    nullif(p_args->>'p_conference_id','')::uuid,btrim(p_args->>'p_name'),
    (p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,
    coalesce(p_args->>'p_location',''),(p_args->>'p_capacity')::integer,
    p_args->>'p_status',coalesce(p_args->>'p_notes',''),v_actor,v_actor
  ) returning id,revision into v_event_id,v_revision;
  perform platform_private.grant_deterministic_resource_permission(
    v_context,v_operation_id,v_event_id
  );
  v_result:=jsonb_build_object('eventId',v_event_id,'revision',v_revision,
    'scopeType',p_args->>'p_scope_type','scopePartitionId',v_partition,
    'event',(select to_jsonb(e) from reservations.events e where e.id=v_event_id));
  perform reservations_private.audit(v_context,'event.created','event',v_event_id,v_operation_id,null,v_result);
  if p_args->>'p_scope_type'='standalone' then
    return reservations_private.complete_standalone_create(v_operation_id,v_context,p_args-'p_scope_type',v_result);
  end if;
  return reservations_private.complete_operation(v_operation_id,v_context,'create_event',p_args,v_result);
end $$;

alter function reservations.mutate(uuid,text,jsonb)
  rename to mutate_pre_authorization_architecture_reconciliation;

create function reservations.mutate(p_device_id uuid,p_operation text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if p_operation='create_event' then
    return reservations_private.create_event_authorized(p_device_id,p_args);
  end if;
  return reservations.mutate_pre_authorization_architecture_reconciliation(p_device_id,p_operation,p_args);
end $$;

alter function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  rename to execute_device_operation_pre_reservations_authorization_reconciliation;

create function platform.execute_device_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,
  p_module text,p_operation text,p_args jsonb
)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','platform','platform_private','reservations' as $$
declare v_session platform_private.device_sessions%rowtype;
begin
  if p_module<>'reservations' or p_operation<>'get_booking_creation_context' then
    return platform.execute_device_operation_pre_reservations_authorization_reconciliation(
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
  select s.* into v_session
  from platform_private.device_sessions s
  join platform.device_key_bindings b on b.id=s.binding_id
  join platform.user_device_authorizations a on a.id=s.device_authorization_id
  join platform.devices d on d.id=s.device_id
  join platform.profiles p on p.user_id=s.user_id
  where s.id=p_session_id and s.user_id=p_user_id and s.token_hash=p_token_hash
    and s.purpose='PLATFORM_DEVICE_SESSION' and s.revoked_at is null and s.expires_at>statement_timestamp()
    and b.user_id=s.user_id and b.device_id=s.device_id and b.device_authorization_id=s.device_authorization_id
    and b.public_key_thumbprint=s.public_key_thumbprint and b.algorithm='ECDSA_P256_SHA256'
    and b.lifecycle_status='active' and b.revoked_at is null and b.retired_at is null
    and a.user_id=s.user_id and a.device_id=s.device_id and a.status='approved' and a.revoked_at is null
    and d.lifecycle_status='active' and d.retired_at is null and d.compromised_at is null
    and p.account_status='approved';
  if not found then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user_id,'role','service_role')::text,true);
  perform set_config('platform.phase1c_context',jsonb_build_object(
    'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',v_session.id,
    'user_id',v_session.user_id,'device_id',v_session.device_id,
    'authorization_id',v_session.device_authorization_id,'binding_id',v_session.binding_id,
    'token_hash',encode(p_token_hash,'hex')
  )::text,true);
  return reservations.read(v_session.device_id,p_operation,p_args);
end $$;

revoke all on function reservations_private.has_event_permission(uuid,text,uuid) from public,anon,authenticated,service_role;
revoke all on function reservations_private.booking_creation_context(uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function platform_private.grant_deterministic_resource_permission(jsonb,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function reservations_private.create_event_authorized(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function reservations_private.has_event_permission(uuid,text,uuid) to postgres;
grant execute on function reservations_private.booking_creation_context(uuid,jsonb) to postgres;
grant execute on function platform_private.grant_deterministic_resource_permission(jsonb,uuid,uuid) to postgres;
grant execute on function reservations_private.create_event_authorized(uuid,jsonb) to postgres;
revoke all on function reservations.read(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function reservations.read(uuid,text,jsonb) to service_role;
revoke all on function reservations.mutate(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function reservations.mutate(uuid,text,jsonb) to service_role;
revoke all on function platform.execute_device_operation_pre_reservations_authorization_reconciliation(uuid,uuid,bytea,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function platform.execute_device_operation_pre_reservations_authorization_reconciliation(uuid,uuid,bytea,text,text,jsonb) to postgres;
revoke all on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb) from public,anon,authenticated;
grant execute on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb) to service_role;

commit;
