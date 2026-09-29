begin;

create function platform_private.prevent_conference_accommodation_occupancy_reparenting()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.participation_id is distinct from old.participation_id
     or new.conference_id is distinct from old.conference_id then
    raise exception 'ACCOMMODATION_OCCUPANCY_PARENT_IMMUTABLE' using errcode='55000';
  end if;
  return new;
end $$;

create trigger conference_accommodation_occupancy_parent_immutable
before update on public.conference_accommodation_occupancies
for each row execute function platform_private.prevent_conference_accommodation_occupancy_reparenting();

create function platform_private.cleanup_conference_accommodation_for_participation(
  p_participation_id uuid,p_actor_user_id uuid,p_device_authorization_id uuid,
  p_authority_context jsonb,p_cause text,p_operation_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_occupancy public.conference_accommodation_occupancies%rowtype;
begin
  if p_cause not in('participation_apologized','participation_deleted') then
    raise exception 'PARTICIPATION_ACCOMMODATION_CLEANUP_CAUSE_INVALID' using errcode='22023';
  end if;
  select * into v_occupancy from public.conference_accommodation_occupancies
  where participation_id=p_participation_id for update;
  if not found then return null; end if;
  delete from public.conference_accommodation_occupancies where id=v_occupancy.id;
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,
    entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source
  ) values(
    p_actor_user_id,p_device_authorization_id,'platform','conference',
    'conference.accommodation.participation_cleanup','accommodation_occupancy',
    v_occupancy.id,'platform',to_jsonb(v_occupancy),null,
    jsonb_build_object(
      'conferenceId',v_occupancy.conference_id,'participationId',p_participation_id,
      'occupancyId',v_occupancy.id,'previousRoomId',v_occupancy.room_id,
      'cause',p_cause,'permissionKey','conference.people.manage',
      'authoritySource',p_authority_context->>'authoritySource',
      'grantId',p_authority_context->'grantId'
    ),p_operation_id,'rpc'
  );
  return v_occupancy.id;
end $$;

create or replace function public.set_conference_participation_status(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,
  p_expected_revision bigint,p_status text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_current public.conference_participations%rowtype;
  v_updated public.conference_participations%rowtype;
  v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb;
  v_prior public.conference_participation_operations%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null
     or p_expected_revision<1 or p_status not in('active','apologized') then
    raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision,'status',p_status);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations
  where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'set_status' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return v_prior.result;
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id for update;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  if (v_context->>'actorUserId')::uuid is distinct from v_actor then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  if v_current.revision<>p_expected_revision then
    raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  if v_current.status='active' and p_status='apologized' then
    perform platform_private.cleanup_conference_accommodation_for_participation(
      p_participation_id,v_actor,v_device_authorization,v_context,
      'participation_apologized',p_operation_id);
  end if;
  update public.conference_participations
  set status=p_status,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor
  where id=p_participation_id returning * into v_updated;
  v_result:=jsonb_build_object(
    'participationId',v_updated.id,'conferenceId',v_updated.conference_id,
    'personId',v_updated.person_id,'status',v_updated.status,'revision',v_updated.revision,
    'updatedAt',v_updated.updated_at,'updatedBy',v_updated.updated_by);
  insert into public.conference_participation_operations
  values(v_actor,p_operation_id,'set_status',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,operation_id,source
  ) values(
    v_actor,v_device_authorization,'platform','conference','conference.participation.status_changed',
    'conference_participation',v_updated.id,'platform',
    jsonb_build_object('status',v_current.status,'revision',v_current.revision),
    jsonb_build_object('status',v_updated.status,'revision',v_updated.revision),
    jsonb_build_object(
      'conferenceId',v_updated.conference_id,'personId',v_updated.person_id,
      'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource',
      'grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

create or replace function public.delete_conference_participation(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_current public.conference_participations%rowtype; v_context jsonb; v_session_context jsonb;
  v_actor uuid; v_device_authorization uuid; v_request jsonb;
  v_prior public.conference_participation_operations%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null
     or p_expected_revision<1 then
    raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  begin
    v_session_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    if v_session_context is null or v_session_context->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH'
       or (v_session_context->>'device_id')::uuid is distinct from p_actor_device_id then
      raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
    end if;
    v_actor:=(v_session_context->>'user_id')::uuid;
  exception when invalid_text_representation or null_value_not_allowed then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  if v_device_authorization is null then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations
  where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'delete' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    v_context:=platform_private.require_conference_participation_context(
      p_actor_device_id,(v_prior.result->>'conferenceId')::uuid,'conference.people.manage',false);
    if (v_context->>'actorUserId')::uuid is distinct from v_actor then
      raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
    end if;
    return v_prior.result;
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  if (v_context->>'actorUserId')::uuid is distinct from v_actor then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id for update;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  if (v_context->>'actorUserId')::uuid is distinct from v_actor then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  if v_current.revision<>p_expected_revision then
    raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  perform platform_private.cleanup_conference_accommodation_for_participation(
    p_participation_id,v_actor,v_device_authorization,v_context,
    'participation_deleted',p_operation_id);
  delete from public.conference_participations where id=p_participation_id;
  v_result:=jsonb_build_object(
    'participationId',p_participation_id,'conferenceId',v_current.conference_id,
    'personId',v_current.person_id,'deleted',true);
  insert into public.conference_participation_operations
  values(v_actor,p_operation_id,'delete',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,operation_id,source
  ) values(
    v_actor,v_device_authorization,'platform','conference','conference.participation.deleted',
    'conference_participation',p_participation_id,'platform',
    jsonb_build_object(
      'conferenceId',v_current.conference_id,'personId',v_current.person_id,
      'status',v_current.status,'revision',v_current.revision),null,
    jsonb_build_object(
      'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource',
      'grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

create or replace function public.assign_conference_accommodation(
  p_device uuid,p_conference uuid,p_room uuid,p_participation uuid,
  p_arrival integer,p_leave integer,p_bed text,p_extra_type text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  context jsonb; actor uuid; device_authorization uuid;
  participation public.conference_participations%rowtype;
  room public.conference_accommodation_rooms%rowtype; days integer; used integer;
  row public.conference_accommodation_occupancies%rowtype; result jsonb;
begin
  context:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
  actor:=(context->>'actorUserId')::uuid;
  device_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  days:=platform_private.conference_accommodation_duration(p_conference);
  if p_arrival<1 or p_arrival>days
     or (p_leave is not null and (p_leave<=p_arrival or p_leave>days+1)) then
    raise exception 'ACCOMMODATION_STAY_INVALID' using errcode='22023';
  end if;
  select * into participation from public.conference_participations
  where id=p_participation and conference_id=p_conference for update;
  if not found or participation.status<>'active' then
    raise exception 'ACTIVE_CONFERENCE_PARTICIPATION_REQUIRED' using errcode='42501';
  end if;
  select * into room from public.conference_accommodation_rooms
  where id=p_room and conference_id=p_conference for update;
  if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002'; end if;
  if room.is_closed and (room.closed_day is null or p_arrival>=room.closed_day
     or coalesce(p_leave,days+1)>room.closed_day) then
    raise exception 'ACCOMMODATION_ROOM_UNAVAILABLE' using errcode='55000';
  end if;
  select count(*) into used from public.conference_accommodation_occupancies
  where room_id=p_room and bed_type=p_bed
    and arrival_day<coalesce(p_leave,days+1) and p_arrival<coalesce(leave_day,days+1);
  if (p_bed='base' and used>=room.base_capacity)
     or (p_bed='extra' and used>=room.extra_bed_capacity) then
    raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED' using errcode='55000';
  end if;
  insert into public.conference_accommodation_occupancies(
    conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,
    extra_bed_person_type,created_by,updated_by
  ) values(p_conference,p_room,p_participation,p_arrival,p_leave,p_bed,p_extra_type,actor,actor)
  returning * into row;
  result:=jsonb_build_object(
    'occupancyId',row.id,'revision',row.revision,'roomId',row.room_id,
    'participationId',row.participation_id);
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,new_values,metadata,source
  ) values(
    actor,device_authorization,'platform','conference','conference.accommodation.assigned',
    'accommodation_occupancy',row.id,'platform',to_jsonb(row),
    jsonb_build_object(
      'conferenceId',p_conference,'participationId',p_participation,
      'permissionKey','conference.accommodation.manage','authoritySource',context->>'authoritySource',
      'grantId',context->'grantId'),'rpc');
  return result;
end $$;

create or replace function public.move_conference_accommodation(
  p_device uuid,p_conference uuid,p_occupancy uuid,p_expected bigint,p_room uuid,
  p_arrival integer,p_leave integer,p_bed text,p_extra_type text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  context jsonb; actor uuid; device_authorization uuid;
  participation public.conference_participations%rowtype;
  current public.conference_accommodation_occupancies%rowtype;
  destination public.conference_accommodation_rooms%rowtype;
  days integer; used integer; updated public.conference_accommodation_occupancies%rowtype;
begin
  context:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
  actor:=(context->>'actorUserId')::uuid;
  device_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  days:=platform_private.conference_accommodation_duration(p_conference);
  if p_arrival<1 or p_arrival>days
     or (p_leave is not null and (p_leave<=p_arrival or p_leave>days+1)) then
    raise exception 'ACCOMMODATION_STAY_INVALID' using errcode='22023';
  end if;
  select * into current from public.conference_accommodation_occupancies
  where id=p_occupancy and conference_id=p_conference;
  if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002'; end if;
  select * into participation from public.conference_participations
  where id=current.participation_id and conference_id=p_conference for update;
  if not found or participation.status<>'active' then
    raise exception 'ACTIVE_CONFERENCE_PARTICIPATION_REQUIRED' using errcode='42501';
  end if;
  select * into current from public.conference_accommodation_occupancies
  where id=p_occupancy and conference_id=p_conference;
  if not found or current.participation_id<>participation.id then
    raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002';
  end if;
  perform 1 from public.conference_accommodation_rooms
  where id in(current.room_id,p_room) order by id for update;
  select * into current from public.conference_accommodation_occupancies
  where id=p_occupancy and participation_id=participation.id for update;
  if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002'; end if;
  if current.revision<>p_expected then
    raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  select * into destination from public.conference_accommodation_rooms
  where id=p_room and conference_id=p_conference;
  if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002'; end if;
  if destination.is_closed and (destination.closed_day is null or p_arrival>=destination.closed_day
     or coalesce(p_leave,days+1)>destination.closed_day) then
    raise exception 'ACCOMMODATION_ROOM_UNAVAILABLE' using errcode='55000';
  end if;
  select count(*) into used from public.conference_accommodation_occupancies
  where room_id=p_room and bed_type=p_bed and id<>p_occupancy
    and arrival_day<coalesce(p_leave,days+1) and p_arrival<coalesce(leave_day,days+1);
  if (p_bed='base' and used>=destination.base_capacity)
     or (p_bed='extra' and used>=destination.extra_bed_capacity) then
    raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED' using errcode='55000';
  end if;
  update public.conference_accommodation_occupancies
  set room_id=p_room,arrival_day=p_arrival,leave_day=p_leave,bed_type=p_bed,
      extra_bed_person_type=p_extra_type,revision=revision+1,
      updated_at=statement_timestamp(),updated_by=actor
  where id=p_occupancy returning * into updated;
  insert into platform.audit_events(
    actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,source
  ) values(
    actor,device_authorization,'platform','conference','conference.accommodation.moved',
    'accommodation_occupancy',p_occupancy,'platform',to_jsonb(current),to_jsonb(updated),
    jsonb_build_object(
      'conferenceId',p_conference,'participationId',current.participation_id,
      'oldRoomId',current.room_id,'newRoomId',p_room,
      'permissionKey','conference.accommodation.manage','authoritySource',context->>'authoritySource',
      'grantId',context->'grantId'),'rpc');
  return jsonb_build_object('occupancyId',updated.id,'revision',updated.revision,'roomId',updated.room_id);
end $$;

revoke all on function
  platform_private.prevent_conference_accommodation_occupancy_reparenting(),
  platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid),
  public.set_conference_participation_status(uuid,uuid,uuid,bigint,text),
  public.delete_conference_participation(uuid,uuid,uuid,bigint),
  public.assign_conference_accommodation(uuid,uuid,uuid,uuid,integer,integer,text,text),
  public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text)
from public,anon,authenticated,service_role;

commit;
