begin;

do $$
begin
  if to_regclass('reservations.conference_person_links') is null
     or to_regclass('public.conference_participations') is null
     or to_regclass('public.conference_accommodation_occupancies') is null
     or to_regprocedure('public.create_conference_participation_with_person(uuid,uuid,uuid,text,text,text,date,text)') is null
     or to_regprocedure('reservations_private.read_scoped(uuid,text,jsonb)') is null then
    raise exception 'P6I_C1B1_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end $$;

-- Historical Reservations projections are intentionally disposable.  Keep only
-- the identity needed to make a new booking map to one canonical participation.
truncate table reservations.conference_person_links;
alter table reservations.conference_person_links
  rename column conference_person_id to conference_participation_id;
alter table reservations.conference_person_links
  add constraint conference_person_links_canonical_participation_fk
  foreign key(conference_participation_id,conference_id)
  references public.conference_participations(id,conference_id)
  on delete cascade;

create index conference_person_links_canonical_participation_idx
  on reservations.conference_person_links(conference_id,conference_participation_id);

create function reservations_private.link_booking_to_canonical_participation(
  p_booking_id uuid,p_operation_id uuid,p_context jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_booking reservations.bookings%rowtype;
  v_participant reservations.participants%rowtype;
  v_event reservations.events%rowtype;
  v_link reservations.conference_person_links%rowtype;
  v_created jsonb;
  v_device uuid:=nullif(p_context->>'actorDeviceId','')::uuid;
begin
  select * into v_link
  from reservations.conference_person_links
  where booking_id=p_booking_id;
  if found then
    return jsonb_build_object(
      'bookingId',v_link.booking_id,'participantId',v_link.participant_id,
      'conferenceId',v_link.conference_id,
      'conferenceParticipationId',v_link.conference_participation_id,'linked',true
    );
  end if;

  select * into v_booking from reservations.bookings where id=p_booking_id for key share;
  if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if;
  select * into v_participant from reservations.participants where id=v_booking.participant_id for key share;
  select * into v_event from reservations.events where id=v_booking.event_id for key share;
  if v_event.conference_id is null then
    raise exception 'RESERVATIONS_EVENT_CONFERENCE_REQUIRED' using errcode='22023';
  end if;

  v_created:=public.create_conference_participation_with_person(
    v_device,p_operation_id,v_event.conference_id,v_participant.full_name,
    v_participant.phone,null,null,nullif(v_participant.church,'')
  );

  insert into reservations.conference_person_links(
    booking_id,participant_id,conference_id,conference_participation_id
  ) values(
    v_booking.id,v_participant.id,v_event.conference_id,
    (v_created->>'participationId')::uuid
  ) returning * into v_link;

  return jsonb_build_object(
    'bookingId',v_link.booking_id,'participantId',v_link.participant_id,
    'conferenceId',v_link.conference_id,
    'conferenceParticipationId',v_link.conference_participation_id,'linked',true
  );
end $$;

-- Switch the active booking lifecycle to the canonical operation, then remove
-- both generations of the legacy snapshot projection function.
do $$
declare
  v_signature regprocedure:='reservations.mutate(uuid,text,jsonb)'::regprocedure;
  v_definition text;
begin
  select pg_get_functiondef(v_signature) into v_definition;
  if (length(v_definition)-length(replace(v_definition,
       'reservations_private.project_booking_to_conference(','')))
       / length('reservations_private.project_booking_to_conference(') <> 1 then
    raise exception 'P6I_C1B1_BOOKING_LIFECYCLE_PRECONDITION_FAILED' using errcode='55000';
  end if;
  v_definition:=replace(
    v_definition,
    'reservations_private.project_booking_to_conference(',
    'reservations_private.link_booking_to_canonical_participation('
  );
  execute v_definition;
end $$;

drop function reservations_private.project_booking_to_conference(uuid,uuid,jsonb);
drop function if exists reservations_private.project_booking_to_conference_pre_scope_partition(uuid,uuid,jsonb);

-- Linking an existing standalone Event remains a Reservations capability, but
-- its historical booking rows are deliberately not backfilled into Conference.
-- Only bookings created after the link enter the canonical participation path.
create or replace function reservations_private.link_standalone_event_to_conference(
  p_device_id uuid,p_args jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_operation_id uuid:=nullif(p_args->>'p_operation_id','')::uuid;
  v_event_id uuid:=nullif(p_args->>'p_event_id','')::uuid;
  v_conference_id uuid:=nullif(p_args->>'p_conference_id','')::uuid;
  v_expected_revision bigint:=(p_args->>'p_expected_revision')::bigint;
  v_context jsonb; v_replay jsonb; v_event reservations.events%rowtype;
  v_new_event reservations.events%rowtype; v_old_partition uuid; v_new_partition uuid;
  v_organization_id uuid; v_actor uuid; v_result jsonb;
begin
  if p_args is null or jsonb_typeof(p_args)<>'object'
     or p_args ?| array['organization_id','p_organization_id','scope_partition_id','p_scope_partition_id',
       'device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then
    raise exception 'RESERVATIONS_SCOPE_OVERRIDE_DENIED' using errcode='42501';
  end if;
  perform platform_private.require_exact_jsonb_keys(
    p_args,array['p_operation_id','p_event_id','p_expected_revision','p_conference_id']
  );
  if v_operation_id is null or v_event_id is null or v_conference_id is null then
    raise exception 'RESERVATIONS_LINK_ARGUMENTS_REQUIRED' using errcode='22023';
  end if;
  v_context:=reservations_private.conference_context(
    p_device_id,v_conference_id,'reservations.event.manage'
  );
  v_new_partition:=v_conference_id;
  v_organization_id:=(v_context->>'organizationId')::uuid;
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_context:=v_context||jsonb_build_object(
    'scopeType','conference','scopePartitionId',v_new_partition,'conferenceId',v_conference_id,
    'eventId',v_event_id,'organizationId',v_organization_id
  );
  v_replay:=reservations_private.begin_operation(
    v_operation_id,v_context,'link_standalone_event_to_conference',p_args
  );
  if v_replay is not null then return v_replay; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('reservations-link-event:'||v_event_id::text,0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('reservations-link-conference:'||v_conference_id::text,0)
  );
  select * into v_event from reservations.events where id=v_event_id for update;
  if not found then raise exception 'RESERVATIONS_EVENT_NOT_FOUND' using errcode='P0002'; end if;
  if v_event.scope_type<>'standalone' or v_event.conference_id is not null
     or v_event.organization_id is not null then
    raise exception 'RESERVATIONS_EVENT_NOT_STANDALONE' using errcode='22023';
  end if;
  if v_event.revision<>v_expected_revision then
    raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001';
  end if;
  if exists(select 1 from reservations.events where conference_id=v_conference_id and id<>v_event_id) then
    raise exception 'RESERVATIONS_TARGET_CONFERENCE_ALREADY_HAS_EVENT' using errcode='40001';
  end if;
  v_old_partition:=v_event.scope_partition_id;
  if v_old_partition is null or v_old_partition=v_new_partition then
    raise exception 'RESERVATIONS_SCOPE_PARTITION_INVALID' using errcode='22023';
  end if;
  if exists(select 1 from reservations.scope_partition_links
    where old_scope_partition_id=v_old_partition or event_id=v_event_id or conference_id=v_conference_id) then
    raise exception 'RESERVATIONS_SCOPE_LINK_CONFLICT' using errcode='40001';
  end if;
  if exists(select 1 from reservations.booking_number_counters where scope_partition_id=v_new_partition)
     and exists(select 1 from reservations.booking_number_counters where scope_partition_id=v_old_partition) then
    raise exception 'RESERVATIONS_TARGET_PARTITION_COUNTER_CONFLICT' using errcode='40001';
  end if;
  set constraints all deferred;
  perform set_config('reservations.scope_relink_guard',
    v_event_id::text||':'||v_old_partition::text||':'||v_new_partition::text,true);
  update reservations.events set scope_type='conference',scope_partition_id=v_new_partition,
    conference_id=v_conference_id,organization_id=v_organization_id,revision=revision+1,
    updated_at=statement_timestamp(),updated_by=v_actor where id=v_event_id;
  update reservations.event_periods set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.booking_types set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.participants set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.bookings set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.payments set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.attendance_records set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.operational_reviews set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  update reservations.booking_number_counters set scope_partition_id=v_new_partition where scope_partition_id=v_old_partition;
  insert into reservations.scope_partition_links(
    old_scope_partition_id,new_scope_partition_id,event_id,conference_id,organization_id,operation_id,linked_by
  ) values(v_old_partition,v_new_partition,v_event_id,v_conference_id,v_organization_id,v_operation_id,v_actor);
  select * into v_new_event from reservations.events where id=v_event_id;
  v_result:=jsonb_build_object('eventId',v_event_id,'conferenceId',v_conference_id,
    'scopeType','conference','oldScopePartitionId',v_old_partition,
    'scopePartitionId',v_new_partition,'revision',v_new_event.revision);
  perform reservations_private.audit(v_context,'event.linked_to_conference','event',v_event_id,
    v_operation_id,to_jsonb(v_event),to_jsonb(v_new_event));
  return reservations_private.complete_operation(
    v_operation_id,v_context,'link_standalone_event_to_conference',p_args,v_result
  );
end $$;

create function reservations_private.get_booking_accommodation_canonical(
  p_booking_id uuid
) returns jsonb
language sql stable security definer set search_path='' as $$
  select case
    when link.booking_id is null then jsonb_build_object(
      'bookingId',p_booking_id,'linked',false,
      'readyForAccommodation',false,'accommodated',false
    )
    else jsonb_strip_nulls(jsonb_build_object(
      'bookingId',p_booking_id,'conferenceId',link.conference_id,
      'conferenceParticipationId',link.conference_participation_id,
      'linked',true,'readyForAccommodation',true,
      'accommodated',occupancy.id is not null,
      'roomId',room.id,'roomNumber',room.room_number,
      'houseLabel',house.name,'floorLabel',floor.name
    ))
  end
  from (select p_booking_id as requested_booking_id) request
  left join reservations.conference_person_links link
    on link.booking_id=request.requested_booking_id
  left join public.conference_accommodation_occupancies occupancy
    on occupancy.conference_id=link.conference_id
   and occupancy.participation_id=link.conference_participation_id
  left join public.conference_accommodation_rooms room
    on room.conference_id=occupancy.conference_id and room.id=occupancy.room_id
  left join public.conference_accommodation_floors floor
    on floor.conference_id=room.conference_id and floor.id=room.floor_id
  left join public.conference_accommodation_houses house
    on house.conference_id=floor.conference_id and house.id=floor.house_id;
$$;

-- Replace only the active accommodation branch in the established scoped read
-- owner.  All other Reservations reads retain their existing implementation.
do $$
declare
  v_signature regprocedure:='reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure;
  v_definition text;
  v_branch text;
  v_start integer;
  v_end integer;
begin
  select pg_get_functiondef(v_signature) into v_definition;
  v_branch:='elsif p_operation=''get_booking_accommodation'' then'
    ||E'\n  perform platform_private.require_exact_jsonb_keys(p_args,array[''p_booking_id'']);'
    ||E'\n  if v_context->>''scopeType''=''standalone'' then return reservations_private.standalone_accommodation_not_applicable(v_booking_id); end if;'
    ||E'\n  return reservations_private.get_booking_accommodation_canonical(v_booking_id);'
    ||E'\n elsif p_operation=''get_dashboard_summary'' then';
  v_start:=regexp_instr(v_definition,
    'elsif[[:space:]]+p_operation[[:space:]]*=[[:space:]]*''get_booking_accommodation''[[:space:]]+then',
    1,1,0,'i');
  v_end:=regexp_instr(v_definition,
    'elsif[[:space:]]+p_operation[[:space:]]*=[[:space:]]*''get_dashboard_summary''[[:space:]]+then',
    1,1,1,'i');
  if v_start=0 or v_end<=v_start then
    raise exception 'P6I_C1B1_READ_CUTOVER_PRECONDITION_FAILED' using errcode='55000';
  end if;
  v_definition:=left(v_definition,v_start-1)||v_branch||substring(v_definition from v_end);
  if position('conference_snapshots' in v_definition)>0
     or position('get_booking_accommodation_canonical' in v_definition)=0 then
    raise exception 'P6I_C1B1_READ_CUTOVER_FAILED' using errcode='55000';
  end if;
  execute v_definition;
end $$;

revoke all on function
  reservations_private.link_booking_to_canonical_participation(uuid,uuid,jsonb),
  reservations_private.link_standalone_event_to_conference(uuid,jsonb),
  reservations_private.get_booking_accommodation_canonical(uuid)
from public,anon,authenticated,service_role;
grant execute on function
  reservations_private.link_booking_to_canonical_participation(uuid,uuid,jsonb),
  reservations_private.link_standalone_event_to_conference(uuid,jsonb),
  reservations_private.get_booking_accommodation_canonical(uuid)
to postgres;

do $$
begin
  if exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in('reservations','reservations_private')
      and p.prokind='f'
      and pg_get_functiondef(p.oid) like '%conference_snapshots%'
  ) then raise exception 'P6I_C1B1_RESERVATIONS_SNAPSHOT_FUNCTION_REMAINS' using errcode='55000'; end if;
  if exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in('reservations','reservations_private')
      and p.prokind='f'
      and pg_get_functiondef(p.oid) like '%public.sync_operations%'
  ) then raise exception 'P6I_C1B1_RESERVATIONS_SYNC_PROJECTION_REMAINS' using errcode='55000'; end if;
  if to_regprocedure('reservations_private.project_booking_to_conference(uuid,uuid,jsonb)') is not null
     or to_regprocedure('reservations_private.project_booking_to_conference_pre_scope_partition(uuid,uuid,jsonb)') is not null then
    raise exception 'P6I_C1B1_LEGACY_PROJECTION_FUNCTION_REMAINS' using errcode='55000';
  end if;
  if pg_get_functiondef('reservations_private.link_standalone_event_to_conference(uuid,jsonb)'::regprocedure)
       like '%link_booking_to_canonical_participation%' then
    raise exception 'P6I_C1B1_HISTORICAL_BOOKING_BACKFILL_REMAINS' using errcode='55000';
  end if;
end $$;

commit;
