begin;

do $$ begin
  if to_regclass('public.conferences') is null or to_regclass('public.conference_participations') is null
     or to_regclass('platform.people') is null or to_regclass('platform.audit_events') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.validated_phase1c_device_authorization(uuid,uuid)') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null then
    raise exception 'P6I_B2_CANONICAL_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
  if not exists(select 1 from public.module_permission_catalog where permission_key='conference.transport.view' and module_key='conference' and status='active')
     or not exists(select 1 from public.module_permission_catalog where permission_key='conference.transport.manage' and module_key='conference' and status='active') then
    raise exception 'P6I_B2_TRANSPORT_PERMISSION_CONTRACT_REQUIRED' using errcode='55000';
  end if;
end $$;

create table public.conference_transport_vehicles(
  id uuid primary key default extensions.gen_random_uuid(), conference_id uuid not null references public.conferences(id) on delete cascade,
  name text not null check(length(btrim(name)) between 1 and 160), icon text not null default '🚌' check(length(icon)<=32),
  capacity integer not null check(capacity between 1 and 300), position integer not null default 0 check(position>=0),
  revision bigint not null default 1 check(revision>=1), created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(), created_by uuid not null references platform.profiles(user_id),
  updated_by uuid not null references platform.profiles(user_id), unique(conference_id,id), unique(conference_id,name)
);
create index conference_transport_vehicles_list_idx on public.conference_transport_vehicles(conference_id,position,id);

create table public.conference_transport_assignments(
  id uuid primary key default extensions.gen_random_uuid(), conference_id uuid not null references public.conferences(id) on delete cascade,
  vehicle_id uuid not null, participation_id uuid not null,
  assignment_mode text not null check(assignment_mode in('independent','shared')),
  rider_kind text not null check(rider_kind in('adult','child','infant')),
  seat_number integer check(seat_number between 1 and 300), revision bigint not null default 1 check(revision>=1),
  created_at timestamptz not null default statement_timestamp(), updated_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id), updated_by uuid not null references platform.profiles(user_id),
  foreign key(conference_id,vehicle_id) references public.conference_transport_vehicles(conference_id,id) on delete cascade,
  foreign key(participation_id,conference_id) references public.conference_participations(id,conference_id) on delete cascade,
  unique(conference_id,participation_id),
  check((assignment_mode='independent' and seat_number is not null) or (assignment_mode='shared' and seat_number is null))
);
create unique index conference_transport_unique_seat_idx on public.conference_transport_assignments(vehicle_id,seat_number) where seat_number is not null;
create index conference_transport_assignments_list_idx on public.conference_transport_assignments(conference_id,vehicle_id,seat_number,id);

alter table public.conference_transport_vehicles enable row level security; alter table public.conference_transport_vehicles force row level security;
alter table public.conference_transport_assignments enable row level security; alter table public.conference_transport_assignments force row level security;
revoke all on table public.conference_transport_vehicles,public.conference_transport_assignments from public,anon,authenticated,service_role;

alter table public.conference_participation_operations
  drop constraint conference_participation_operations_operation_check;
alter table public.conference_participation_operations
  add constraint conference_participation_operations_operation_check check(operation in(
    'create','create_with_person','set_status','set_guardian','delete',
    'transport_vehicle_create','transport_vehicle_update','transport_vehicle_delete',
    'transport_assignment_set','transport_assignment_remove'));

create function platform_private.require_conference_transport_context(p_device uuid,p_conference uuid,p_permission text,p_mutation boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; actor uuid; conf public.conferences%rowtype;
begin
  if p_permission not in('conference.transport.view','conference.transport.manage') then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  c:=public.require_effective_module_permission(p_device,'conference',p_permission,'conference',p_conference::text); actor:=(c->>'actorUserId')::uuid;
  if platform_private.validated_phase1c_device_authorization(actor,p_device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  select * into conf from public.conferences where id=p_conference and deleted_at is null;
  if not found then raise exception 'CONFERENCE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mutation and conf.status<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE' using errcode='55000'; end if;
  return c;
end $$;

create function platform_private.audit_conference_transport_assignment_removal(
  p_actor uuid,p_device_authorization uuid,p_assignment public.conference_transport_assignments,
  p_operation_id uuid,p_reason text,p_permission text
) returns void language plpgsql security definer set search_path='' as $$
begin
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(p_actor,p_device_authorization,'platform','conference','conference.transport.assignment_removed',
    'conference_transport_assignment',p_assignment.id,'platform',to_jsonb(p_assignment),null,
    jsonb_build_object('conferenceId',p_assignment.conference_id,'vehicleId',p_assignment.vehicle_id,
      'participationId',p_assignment.participation_id,'removalReason',p_reason,'permissionKey',p_permission),
    p_operation_id,'rpc');
end $$;

create function public.get_conference_transport(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; vehicles jsonb; assignments jsonb; can_manage boolean:=false;
begin
  c:=platform_private.require_conference_transport_context(p_actor_device_id,p_conference_id,'conference.transport.view',false);
  begin
    perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.transport.manage','conference',p_conference_id::text);
    can_manage:=true;
  exception when insufficient_privilege then null;
  end;
  select coalesce(jsonb_agg(jsonb_build_object('vehicleId',v.id,'name',v.name,'icon',v.icon,'capacity',v.capacity,'position',v.position,'revision',v.revision) order by v.position,v.id),'[]') into vehicles from public.conference_transport_vehicles v where v.conference_id=p_conference_id;
  select coalesce(jsonb_agg(jsonb_build_object('assignmentId',a.id,'vehicleId',a.vehicle_id,'participationId',a.participation_id,'mode',a.assignment_mode,'riderKind',a.rider_kind,'seatNumber',a.seat_number,'revision',a.revision,'participationStatus',p.status,'person',jsonb_build_object('personId',p.person_id,'fullName',person.full_name,'phone',person.phone),'guardianParticipationId',p.guardian_participation_id,'guardianParticipationStatus',gp.status,'guardianFullName',gperson.full_name,'roomNumber',room.room_number,'sharingEligible',a.assignment_mode<>'shared' or gp.status='active') order by a.vehicle_id,a.seat_number nulls last,a.id),'[]') into assignments
  from public.conference_transport_assignments a join public.conference_participations p on p.id=a.participation_id
  join platform.people person on person.id=p.person_id left join public.conference_participations gp on gp.id=p.guardian_participation_id
  left join platform.people gperson on gperson.id=gp.person_id left join public.conference_accommodation_occupancies o on o.participation_id=p.id
  left join public.conference_accommodation_rooms room on room.id=o.room_id where a.conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'canManage',can_manage,'vehicles',vehicles,'assignments',assignments);
end $$;

create function public.mutate_conference_transport_vehicle(p_device uuid,p_operation_id uuid,p_operation text,p_conference uuid,p_vehicle uuid,p_expected_revision bigint,p_name text,p_icon text,p_capacity integer,p_position integer,p_remove_overflow boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb; actor uuid; authz uuid; req jsonb; prior public.conference_participation_operations%rowtype;
  old public.conference_transport_vehicles%rowtype; row public.conference_transport_vehicles%rowtype;
  removed public.conference_transport_assignments%rowtype; removed_ids jsonb:='[]'::jsonb; result jsonb;
begin
  if p_operation_id is null or p_operation not in('create','update','delete') then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  c:=platform_private.require_conference_transport_context(p_device,p_conference,'conference.transport.manage',true); actor:=(c->>'actorUserId')::uuid; authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  req:=jsonb_build_object('operation',p_operation,'conferenceId',p_conference,'vehicleId',p_vehicle,'expectedRevision',p_expected_revision,'name',p_name,'icon',p_icon,'capacity',p_capacity,'position',p_position,'removeOverflow',p_remove_overflow);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'transport_vehicle_'||p_operation or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return prior.result; end if;
  if p_operation='create' then insert into public.conference_transport_vehicles(conference_id,name,icon,capacity,position,created_by,updated_by) values(p_conference,btrim(p_name),coalesce(nullif(p_icon,''),'🚌'),p_capacity,coalesce(p_position,0),actor,actor) returning * into row;
  else select * into old from public.conference_transport_vehicles where id=p_vehicle and conference_id=p_conference for update; if not found then raise exception 'CONFERENCE_TRANSPORT_VEHICLE_NOT_FOUND' using errcode='P0002'; end if; if old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if;
    if p_operation='delete' then
      for removed in select * from public.conference_transport_assignments where vehicle_id=p_vehicle order by id for update loop
        perform platform_private.audit_conference_transport_assignment_removal(actor,authz,removed,p_operation_id,'vehicle_deleted','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(removed.id);
      end loop;
      delete from public.conference_transport_assignments where vehicle_id=p_vehicle; delete from public.conference_transport_vehicles where id=p_vehicle; row:=old;
    else
      if p_capacity<old.capacity and exists(select 1 from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity) and not coalesce(p_remove_overflow,false) then raise exception 'CONFERENCE_TRANSPORT_CAPACITY_OCCUPIED' using errcode='23514'; end if;
      if p_capacity<old.capacity then
        for removed in select * from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity order by id for update loop
          perform platform_private.audit_conference_transport_assignment_removal(actor,authz,removed,p_operation_id,'capacity_reduced','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(removed.id);
        end loop;
        delete from public.conference_transport_assignments where vehicle_id=p_vehicle and seat_number>p_capacity;
      end if;
      update public.conference_transport_vehicles set name=btrim(p_name),icon=coalesce(nullif(p_icon,''),'🚌'),capacity=p_capacity,position=coalesce(p_position,position),revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=p_vehicle returning * into row;
    end if;
  end if;
  result:=jsonb_build_object('vehicleId',row.id,'conferenceId',row.conference_id,'name',row.name,'icon',row.icon,'capacity',row.capacity,'position',row.position,'revision',row.revision,'deleted',p_operation='delete','removedAssignmentIds',removed_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'transport_vehicle_'||p_operation,req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.transport.vehicle_'||p_operation,'conference_transport_vehicle',row.id,'platform',case when p_operation='create' then null else to_jsonb(old) end,case when p_operation='delete' then null else to_jsonb(row) end,jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.transport.manage'),p_operation_id,'rpc'); return result;
end $$;

create function public.set_conference_transport_assignment(p_device uuid,p_operation_id uuid,p_conference uuid,p_participation uuid,p_vehicle uuid,p_mode text,p_rider_kind text,p_seat integer,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c jsonb; actor uuid; authz uuid; req jsonb; prior public.conference_participation_operations%rowtype; part public.conference_participations%rowtype; guardian public.conference_participations%rowtype; vehicle public.conference_transport_vehicles%rowtype; old public.conference_transport_assignments%rowtype; row public.conference_transport_assignments%rowtype; result jsonb;
begin
  c:=platform_private.require_conference_transport_context(p_device,p_conference,'conference.transport.manage',true); actor:=(c->>'actorUserId')::uuid; authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  req:=jsonb_build_object('conferenceId',p_conference,'participationId',p_participation,'vehicleId',p_vehicle,'mode',p_mode,'riderKind',p_rider_kind,'seatNumber',p_seat,'expectedRevision',p_expected_revision); perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0)); select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id; if found then if prior.operation<>'transport_assignment_set' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; return prior.result; end if;
  select * into part from public.conference_participations where id=p_participation and conference_id=p_conference for key share; if not found or part.status<>'active' then raise exception 'CONFERENCE_TRANSPORT_PARTICIPATION_INELIGIBLE' using errcode='23514'; end if;
  select * into vehicle from public.conference_transport_vehicles where id=p_vehicle and conference_id=p_conference for update; if not found then raise exception 'CONFERENCE_TRANSPORT_VEHICLE_NOT_FOUND' using errcode='P0002'; end if;
  if p_mode='independent' then if p_seat is null or p_seat>vehicle.capacity then raise exception 'CONFERENCE_TRANSPORT_SEAT_INVALID' using errcode='23514'; end if;
  elsif p_mode='shared' then select * into guardian from public.conference_participations where id=part.guardian_participation_id and conference_id=p_conference; if not found or guardian.status<>'active' or not exists(select 1 from public.conference_transport_assignments where participation_id=guardian.id and vehicle_id=p_vehicle and assignment_mode='independent') then raise exception 'CONFERENCE_TRANSPORT_GUARDIAN_INELIGIBLE' using errcode='23514'; end if; p_seat:=null;
  else raise exception 'CONFERENCE_TRANSPORT_MODE_INVALID' using errcode='22023'; end if;
  select * into old from public.conference_transport_assignments where conference_id=p_conference and participation_id=p_participation for update;
  if found then if p_expected_revision is null or old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if; update public.conference_transport_assignments set vehicle_id=p_vehicle,assignment_mode=p_mode,rider_kind=p_rider_kind,seat_number=p_seat,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=old.id returning * into row;
  else insert into public.conference_transport_assignments(conference_id,vehicle_id,participation_id,assignment_mode,rider_kind,seat_number,created_by,updated_by) values(p_conference,p_vehicle,p_participation,p_mode,p_rider_kind,p_seat,actor,actor) returning * into row; end if;
  if row.assignment_mode='independent' then
    update public.conference_transport_assignments child_assignment set vehicle_id=row.vehicle_id,revision=child_assignment.revision+1,updated_at=statement_timestamp(),updated_by=actor
    from public.conference_participations child where child.id=child_assignment.participation_id and child.guardian_participation_id=row.participation_id and child_assignment.assignment_mode='shared' and child_assignment.conference_id=row.conference_id and child_assignment.vehicle_id<>row.vehicle_id;
  end if;
  result:=jsonb_build_object('assignmentId',row.id,'conferenceId',row.conference_id,'vehicleId',row.vehicle_id,'participationId',row.participation_id,'mode',row.assignment_mode,'riderKind',row.rider_kind,'seatNumber',row.seat_number,'revision',row.revision); insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'transport_assignment_set',req,result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.transport.assignment_set','conference_transport_assignment',row.id,'platform',case when old.id is null then null else to_jsonb(old) end,to_jsonb(row),jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.transport.manage'),p_operation_id,'rpc'); return result;
end $$;

create function public.remove_conference_transport_assignment(p_device uuid,p_operation_id uuid,p_assignment uuid,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.conference_transport_assignments%rowtype; removed public.conference_transport_assignments%rowtype;
  c jsonb; session_context jsonb; actor uuid; authz uuid; req jsonb; prior public.conference_participation_operations%rowtype;
  removed_ids jsonb:='[]'::jsonb; result jsonb;
begin
  if p_operation_id is null or p_assignment is null or p_expected_revision is null then raise exception 'CONFERENCE_TRANSPORT_ARGUMENT_INVALID' using errcode='22023'; end if;
  begin
    session_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    if session_context is null or session_context->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_context->>'device_id')::uuid is distinct from p_device then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
    actor:=(session_context->>'user_id')::uuid;
  exception when invalid_text_representation or null_value_not_allowed then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_device); if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  req:=jsonb_build_object('assignmentId',p_assignment,'expectedRevision',p_expected_revision);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0)); select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then if prior.operation<>'transport_assignment_remove' or prior.request<>req then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; c:=platform_private.require_conference_transport_context(p_device,(prior.result->>'conferenceId')::uuid,'conference.transport.manage',false); if (c->>'actorUserId')::uuid is distinct from actor then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if; return prior.result; end if;
  select * into old from public.conference_transport_assignments where id=p_assignment for update; if not found then raise exception 'CONFERENCE_TRANSPORT_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if;
  c:=platform_private.require_conference_transport_context(p_device,old.conference_id,'conference.transport.manage',true); if (c->>'actorUserId')::uuid is distinct from actor then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  if old.revision<>p_expected_revision then raise exception 'CONFERENCE_TRANSPORT_REVISION_CONFLICT' using errcode='40001'; end if;
  if old.assignment_mode='independent' then
    for removed in select child_assignment.* from public.conference_transport_assignments child_assignment join public.conference_participations child on child.id=child_assignment.participation_id where child.guardian_participation_id=old.participation_id and child_assignment.assignment_mode='shared' and child_assignment.vehicle_id=old.vehicle_id order by child_assignment.id for update of child_assignment loop
      perform platform_private.audit_conference_transport_assignment_removal(actor,authz,removed,p_operation_id,'guardian_assignment_removed','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(removed.id);
    end loop;
    delete from public.conference_transport_assignments child_assignment using public.conference_participations child where child.id=child_assignment.participation_id and child.guardian_participation_id=old.participation_id and child_assignment.assignment_mode='shared' and child_assignment.vehicle_id=old.vehicle_id;
  end if;
  perform platform_private.audit_conference_transport_assignment_removal(actor,authz,old,p_operation_id,'assignment_removed','conference.transport.manage'); removed_ids:=removed_ids||jsonb_build_array(old.id);
  delete from public.conference_transport_assignments where id=p_assignment;
  result:=jsonb_build_object('assignmentId',p_assignment,'conferenceId',old.conference_id,'deleted',true,'removedAssignmentIds',removed_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(actor,p_operation_id,'transport_assignment_remove',req,result,statement_timestamp()); return result;
end $$;

alter function public.delete_conference_participation(uuid,uuid,uuid,bigint)
  rename to delete_conference_participation_without_transport_cleanup;

create function public.delete_conference_participation(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_session_context jsonb; v_actor uuid; v_device_authorization uuid; v_context jsonb;
  v_current public.conference_participations%rowtype; v_prior public.conference_participation_operations%rowtype;
  v_assignment public.conference_transport_assignments%rowtype; v_participation_ids uuid[];
  v_removed_ids jsonb:='[]'::jsonb; v_result jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null or p_expected_revision<1 then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  begin
    v_session_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    if v_session_context is null or v_session_context->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (v_session_context->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
    v_actor:=(v_session_context->>'user_id')::uuid;
  exception when invalid_text_representation or null_value_not_allowed then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id); if v_device_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'delete' or v_prior.request<>jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision) then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if;
    v_context:=platform_private.require_conference_participation_context(p_actor_device_id,(v_prior.result->>'conferenceId')::uuid,'conference.people.manage',false); if (v_context->>'actorUserId')::uuid is distinct from v_actor then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
    return v_prior.result;
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id; if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,v_current.conference_id,'conference.people.manage',true); if (v_context->>'actorUserId')::uuid is distinct from v_actor then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||v_current.conference_id::text,0));
  perform 1 from public.conference_participations where id=p_participation_id or guardian_participation_id=p_participation_id order by id for update;
  select array_agg(id order by id) into v_participation_ids from public.conference_participations where id=p_participation_id or guardian_participation_id=p_participation_id;
  for v_assignment in select assignment.* from public.conference_transport_assignments assignment where assignment.participation_id=any(v_participation_ids) order by assignment.id for update loop
    perform platform_private.audit_conference_transport_assignment_removal(v_actor,v_device_authorization,v_assignment,p_operation_id,'participation_deleted','conference.people.manage'); v_removed_ids:=v_removed_ids||jsonb_build_array(v_assignment.id);
  end loop;
  delete from public.conference_transport_assignments where participation_id=any(v_participation_ids);
  v_result:=public.delete_conference_participation_without_transport_cleanup(p_actor_device_id,p_operation_id,p_participation_id,p_expected_revision)||jsonb_build_object('removedTransportAssignmentIds',v_removed_ids);
  update public.conference_participation_operations set result=v_result where actor_user_id=v_actor and operation_id=p_operation_id;
  return v_result;
end $$;

revoke all on function platform_private.require_conference_transport_context(uuid,uuid,text,boolean),platform_private.audit_conference_transport_assignment_removal(uuid,uuid,public.conference_transport_assignments,uuid,text,text),public.get_conference_transport(uuid,uuid),public.mutate_conference_transport_vehicle(uuid,uuid,text,uuid,uuid,bigint,text,text,integer,integer,boolean),public.set_conference_transport_assignment(uuid,uuid,uuid,uuid,uuid,text,text,integer,bigint),public.remove_conference_transport_assignment(uuid,uuid,uuid,bigint),public.delete_conference_participation_without_transport_cleanup(uuid,uuid,uuid,bigint),public.delete_conference_participation(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;

do $$ declare sig regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure; d text; marker text:='if p_operation=''list_accessible_conferences'' then'; branch text:='if p_operation=''get_conference_transport'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'']); return public.get_conference_transport(p_actor_device_id,(p_args->>''p_conference_id'')::uuid); elsif p_operation=''mutate_conference_transport_vehicle'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_operation'',''p_conference_id'',''p_vehicle_id'',''p_expected_revision'',''p_name'',''p_icon'',''p_capacity'',''p_position'',''p_remove_overflow'']); return public.mutate_conference_transport_vehicle(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,p_args->>''p_operation'',(p_args->>''p_conference_id'')::uuid,nullif(p_args->>''p_vehicle_id'','''')::uuid,nullif(p_args->>''p_expected_revision'','''')::bigint,p_args->>''p_name'',p_args->>''p_icon'',nullif(p_args->>''p_capacity'','''')::integer,nullif(p_args->>''p_position'','''')::integer,coalesce((p_args->>''p_remove_overflow'')::boolean,false)); elsif p_operation=''set_conference_transport_assignment'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_conference_id'',''p_participation_id'',''p_vehicle_id'',''p_mode'',''p_rider_kind'',''p_seat_number'',''p_expected_revision'']); return public.set_conference_transport_assignment(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_participation_id'')::uuid,(p_args->>''p_vehicle_id'')::uuid,p_args->>''p_mode'',p_args->>''p_rider_kind'',nullif(p_args->>''p_seat_number'','''')::integer,nullif(p_args->>''p_expected_revision'','''')::bigint); elsif p_operation=''remove_conference_transport_assignment'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_assignment_id'',''p_expected_revision'']); return public.remove_conference_transport_assignment(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_assignment_id'')::uuid,(p_args->>''p_expected_revision'')::bigint); elsif p_operation=''list_accessible_conferences'' then'; begin d:=pg_get_functiondef(sig); if position('p_operation=''get_conference_transport''' in d)<>0 or position(marker in d)=0 then raise exception 'P6I_B2_ROUTER_PRECONDITION_FAILED' using errcode='55000'; end if; execute replace(d,marker,branch); end $$;

create or replace function public.list_accessible_conferences(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_conference public.conferences%rowtype; v_items jsonb:='[]'::jsonb; v_can_sync boolean; v_can_accommodation_manage boolean; v_can_transport_manage boolean;
begin
  perform public.require_current_approved_device(p_actor_device_id);
  for v_conference in select conferences.* from public.conferences conferences where conferences.deleted_at is null order by conferences.created_at,conferences.id loop
    begin
      perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.access.view','conference',v_conference.id::text);
      v_can_sync:=false;v_can_accommodation_manage:=false;v_can_transport_manage:=false;
      begin perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.sync.write','conference',v_conference.id::text);v_can_sync:=true;exception when insufficient_privilege then null;end;
      begin perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.accommodation.manage','conference',v_conference.id::text);v_can_accommodation_manage:=true;exception when insufficient_privilege then null;end;
      begin perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.transport.manage','conference',v_conference.id::text);v_can_transport_manage:=true;exception when insufficient_privilege then null;end;
      v_items:=v_items||jsonb_build_array(jsonb_build_object('conferenceId',v_conference.id,'organizationId',v_conference.organization_id,'name',v_conference.name,'startDate',v_conference.start_date,'endDate',v_conference.end_date,'status',v_conference.status,'completedAt',v_conference.completed_at,'revision',v_conference.revision,'createdAt',v_conference.created_at,'updatedAt',v_conference.updated_at,'capabilities',jsonb_build_object('edit',v_can_sync and v_can_accommodation_manage,'sync',v_can_sync,'transportManage',v_can_transport_manage)));
    exception when insufficient_privilege then null;end;
  end loop;
  return jsonb_build_object('conferences',v_items);
end $$;

revoke all on function public.list_accessible_conferences(uuid) from public,anon,authenticated,service_role;

comment on function public.get_conference_transport(uuid,uuid) is 'Protected canonical Transport projection. Participation is sufficient for assignment; Accommodation is optional derived display data.';
comment on table public.conference_transport_assignments is 'Canonical Transport assignment by Conference Participation. No Accommodation occupancy is required or created.';

commit;
