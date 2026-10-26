begin;

drop function if exists public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb);

create function public.save_conference_accommodation_room_draft(
  p_device uuid,
  p_operation_id uuid,
  p_conference uuid,
  p_room uuid,
  p_expected_revision bigint,
  p_expected_assignment_revision bigint,
  p_structure jsonb,
  p_assignments jsonb,
  p_updates jsonb,
  p_replacements jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  ctx jsonb; actor uuid; authz uuid;
  room public.conference_accommodation_rooms%rowtype;
  room_assignment public.conference_room_assignments%rowtype;
  item jsonb; mutation_result jsonb; assignment_results jsonb:='[]'; update_results jsonb:='[]'; replacement_results jsonb:='[]';
  structure_result jsonb; result jsonb; old_values jsonb; extra_capacity integer; days integer;
begin
  if p_operation_id is null then raise exception 'ACCOMMODATION_OPERATION_ID_REQUIRED' using errcode='22023'; end if;
  if p_assignments is null or jsonb_typeof(p_assignments)<>'array' then raise exception 'ACCOMMODATION_ROOM_DRAFT_ASSIGNMENTS_INVALID' using errcode='22023'; end if;
  if p_updates is null or jsonb_typeof(p_updates)<>'array' then raise exception 'ACCOMMODATION_ROOM_DRAFT_UPDATES_INVALID' using errcode='22023'; end if;
  if p_replacements is null or jsonb_typeof(p_replacements)<>'array' then raise exception 'ACCOMMODATION_ROOM_DRAFT_REPLACEMENTS_INVALID' using errcode='22023'; end if;
  if (p_structure is null or jsonb_typeof(p_structure)='null') and jsonb_array_length(p_assignments)=0 and jsonb_array_length(p_updates)=0 and jsonb_array_length(p_replacements)=0 then raise exception 'ACCOMMODATION_ROOM_DRAFT_EMPTY' using errcode='22023'; end if;

  ctx:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
  actor:=(ctx->>'actorUserId')::uuid;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  select new_values into result from platform.audit_events where actor_user_id=actor and operation_id=p_operation_id and scope_id=p_conference and action='conference.accommodation.room_draft_saved' limit 1;
  if result is not null then return result||jsonb_build_object('status','duplicate'); end if;

  -- Match move_conference_accommodation: participation locks first, then room and stay locks.
  perform 1
  from public.conference_participations p
  where p.conference_id=p_conference and p.id in (
    select (value->>'participationId')::uuid from jsonb_array_elements(p_assignments)
    union
    select (value->>'participationId')::uuid from jsonb_array_elements(p_replacements)
    union
    select o.participation_id from public.conference_accommodation_occupancies o join jsonb_array_elements(p_replacements) u on o.id=(u.value->>'occupancyId')::uuid where o.conference_id=p_conference
    union
    select o.participation_id from public.conference_accommodation_occupancies o join jsonb_array_elements(p_updates) u on o.id=(u.value->>'occupancyId')::uuid where o.conference_id=p_conference
  )
  order by p.id for update;

  select * into room_assignment from public.conference_room_assignments where conference_id=p_conference and room_id=p_room for update;
  if not found then raise exception 'ROOM_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if;
  if room_assignment.revision<>p_expected_assignment_revision then raise exception 'ROOM_ASSIGNMENT_REVISION_CONFLICT' using errcode='40001'; end if;
  select * into room from public.conference_accommodation_rooms where id=p_room for update;
  if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002'; end if;
  if room.revision<>p_expected_revision then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if;
  perform 1 from public.conference_accommodation_occupancies o where o.conference_id=p_conference and o.id in(select (value->>'occupancyId')::uuid from jsonb_array_elements(p_updates) union select (value->>'occupancyId')::uuid from jsonb_array_elements(p_replacements)) order by o.id for update;
  old_values:=jsonb_build_object('room',to_jsonb(room),'assignment',to_jsonb(room_assignment));

  if p_structure is not null and jsonb_typeof(p_structure)<>'null' then
    perform platform_private.require_exact_jsonb_keys(p_structure,array['roomNumber','baseCapacity','extraBedCapacity','notes','isClosed','closedDay','position']);
    extra_capacity:=(p_structure->>'extraBedCapacity')::integer;
    if extra_capacity<0 then raise exception 'ACCOMMODATION_CAPACITY_INVALID' using errcode='22023'; end if;
    -- Increases must precede stay mutations; decreases are checked against the final draft below.
    if extra_capacity>room_assignment.extra_bed_capacity then
      update public.conference_room_assignments set extra_bed_capacity=extra_capacity,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=room_assignment.id;
    end if;
    if (p_structure->>'baseCapacity')::integer>=room.base_capacity and (room.room_number is distinct from p_structure->>'roomNumber' or room.base_capacity is distinct from (p_structure->>'baseCapacity')::integer or coalesce(room.notes,'') is distinct from coalesce(p_structure->>'notes','') or room.is_closed is distinct from (p_structure->>'isClosed')::boolean or room.closed_day is distinct from (p_structure->>'closedDay')::integer or room.position is distinct from (p_structure->>'position')::integer) then
      structure_result:=public.mutate_conference_accommodation_structure(p_device,'update_room',jsonb_build_object('p_conference_id',p_conference,'p_room_id',p_room,'p_expected_revision',p_expected_revision,'p_room_number',p_structure->>'roomNumber','p_base_capacity',p_structure->'baseCapacity','p_extra_bed_capacity',room.extra_bed_capacity,'p_notes',p_structure->'notes','p_is_closed',p_structure->'isClosed','p_closed_day',p_structure->'closedDay','p_position',p_structure->'position'));
    end if;
  end if;

  -- Reject ambiguous simultaneous edits and guardians with linked children; replacement never rewrites person identity.
  if exists(select 1 from jsonb_array_elements(p_replacements) r join jsonb_array_elements(p_updates) u on r.value->>'occupancyId'=u.value->>'occupancyId') then raise exception 'ACCOMMODATION_REPLACEMENT_UPDATE_CONFLICT' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_replacements) r join public.conference_accommodation_occupancies o on o.id=(r.value->>'occupancyId')::uuid join public.conference_participations child on child.guardian_participation_id=o.participation_id and child.conference_id=p_conference join public.conference_accommodation_occupancies child_stay on child_stay.participation_id=child.id and child_stay.conference_id=p_conference and child_stay.room_id=p_room and child_stay.arrival_day=o.arrival_day and child_stay.leave_day is not distinct from o.leave_day) then raise exception 'ACCOMMODATION_GUARDIAN_REPLACEMENT_REQUIRES_CHILD_REASSIGNMENT' using errcode='23514'; end if;
  for item in select value from jsonb_array_elements(p_replacements) order by value->>'occupancyId' loop
    perform platform_private.require_exact_jsonb_keys(item,array['occupancyId','expectedRevision','participationId','effectiveDay','bedType','extraBedPersonType']);
    if not exists(select 1 from public.conference_accommodation_occupancies where id=(item->>'occupancyId')::uuid and conference_id=p_conference and room_id=p_room) then raise exception 'ACCOMMODATION_REPLACEMENT_ROOM_MISMATCH' using errcode='22023'; end if;
    mutation_result:=public.replace_conference_accommodation(p_device,gen_random_uuid(),p_conference,(item->>'occupancyId')::uuid,(item->>'expectedRevision')::bigint,(item->>'participationId')::uuid,(item->>'effectiveDay')::integer,item->>'bedType',item->>'extraBedPersonType');
    replacement_results:=replacement_results||jsonb_build_array(mutation_result);
  end loop;
  for item in select value from jsonb_array_elements(p_updates) order by value->>'occupancyId' loop
    perform platform_private.require_exact_jsonb_keys(item,array['occupancyId','expectedRevision','arrivalDay','leaveDay','bedType','extraBedPersonType']);
    mutation_result:=public.move_conference_accommodation(p_device,p_conference,(item->>'occupancyId')::uuid,(item->>'expectedRevision')::bigint,p_room,(item->>'arrivalDay')::integer,(item->>'leaveDay')::integer,item->>'bedType',item->>'extraBedPersonType');
    update_results:=update_results||jsonb_build_array(mutation_result);
  end loop;
  for item in select value from jsonb_array_elements(p_assignments) order by value->>'participationId' loop
    perform platform_private.require_exact_jsonb_keys(item,array['participationId','arrivalDay','leaveDay','bedType','extraBedPersonType']);
    mutation_result:=public.assign_conference_accommodation(p_device,p_conference,p_room,(item->>'participationId')::uuid,(item->>'arrivalDay')::integer,(item->>'leaveDay')::integer,item->>'bedType',item->>'extraBedPersonType');
    assignment_results:=assignment_results||jsonb_build_array(mutation_result);
  end loop;

  if extra_capacity is not null and extra_capacity<room_assignment.extra_bed_capacity then
    days:=platform_private.conference_accommodation_duration(p_conference);
    if exists(select 1 from generate_series(1,days) d(day) join public.conference_accommodation_occupancies o on o.conference_id=p_conference and o.room_id=p_room and o.bed_type='extra' and o.arrival_day<=d.day and d.day<coalesce(o.leave_day,days+1) group by d.day having count(*)>extra_capacity) then raise exception 'ACCOMMODATION_CAPACITY_CONFLICT' using errcode='55000'; end if;
    update public.conference_room_assignments set extra_bed_capacity=extra_capacity,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=room_assignment.id;
  end if;
  if p_structure is not null and jsonb_typeof(p_structure)<>'null' and (p_structure->>'baseCapacity')::integer<room.base_capacity then
    structure_result:=public.mutate_conference_accommodation_structure(p_device,'update_room',jsonb_build_object('p_conference_id',p_conference,'p_room_id',p_room,'p_expected_revision',p_expected_revision,'p_room_number',p_structure->>'roomNumber','p_base_capacity',p_structure->'baseCapacity','p_extra_bed_capacity',room.extra_bed_capacity,'p_notes',p_structure->'notes','p_is_closed',p_structure->'isClosed','p_closed_day',p_structure->'closedDay','p_position',p_structure->'position'));
  end if;

  result:=jsonb_build_object('status','success','operationId',p_operation_id,'roomId',p_room,'structureChanged',p_structure is not null and jsonb_typeof(p_structure)<>'null','structure',structure_result,'assignments',assignment_results,'updates',update_results,'replacements',replacement_results);
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,scope_id,old_values,new_values,metadata,operation_id,source)
  values(actor,authz,'platform','conference','conference.accommodation.room_draft_saved','accommodation_room',p_room,'conference',p_conference,old_values,result,jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
  return result;
end $$;

do $dispatch$
declare d text; old_signature text; new_signature text; old_call text; new_call text;
begin
  d:=pg_get_functiondef('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure);
  old_signature:='array[''p_operation_id'',''p_conference_id'',''p_room_id'',''p_expected_revision'',''p_expected_assignment_revision'',''p_structure'',''p_assignments'',''p_updates'',''p_room_lease_tokens'']';
  new_signature:='array[''p_operation_id'',''p_conference_id'',''p_room_id'',''p_expected_revision'',''p_expected_assignment_revision'',''p_structure'',''p_assignments'',''p_updates'',''p_replacements'',''p_room_lease_tokens'']';
  old_call:='return public.save_conference_accommodation_room_draft(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_room_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,(p_args->>''p_expected_assignment_revision'')::bigint,p_args->''p_structure'',p_args->''p_assignments'',p_args->''p_updates'');';
  new_call:='return public.save_conference_accommodation_room_draft(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,(p_args->>''p_room_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,(p_args->>''p_expected_assignment_revision'')::bigint,p_args->''p_structure'',p_args->''p_assignments'',p_args->''p_updates'',p_args->''p_replacements'');';
  if position(old_signature in d)=0 or position(old_call in d)=0 then raise exception 'ACCOMMODATION_ROOM_DRAFT_V4_DISPATCH_MARKER_MISSING'; end if;
  execute replace(replace(d,old_signature,new_signature),old_call,new_call);
end $dispatch$;

revoke all on function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb,jsonb) to service_role;

commit;
