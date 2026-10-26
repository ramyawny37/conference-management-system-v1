begin;

-- Every linked child is an independent participation and occupancy, but its
-- room, stay interval and arrival state are always inherited from the exact
-- guardian stay segment. Bed consumption remains the child's own choice.
create or replace function platform_private.enforce_linked_child_guardian_stay()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  child public.conference_participations%rowtype;
  guardian_stay public.conference_accommodation_occupancies%rowtype;
begin
  select * into child from public.conference_participations
   where id=new.participation_id and conference_id=new.conference_id;
  if not found or child.guardian_participation_id is null then return new; end if;

  select * into guardian_stay
    from public.conference_accommodation_occupancies guardian
   where guardian.conference_id=new.conference_id
     and guardian.participation_id=child.guardian_participation_id
     and guardian.room_id=new.room_id
     and guardian.arrival_day=new.arrival_day
     and guardian.leave_day is not distinct from new.leave_day
   order by guardian.id
   limit 1 for key share;
  if not found then
    raise exception 'ACCOMMODATION_CHILD_STAY_INHERITED' using errcode='23514';
  end if;
  if tg_op='INSERT' then
    new.arrived_at:=guardian_stay.arrived_at;
    new.arrived_by:=guardian_stay.arrived_by;
  elsif new.arrived_at is distinct from guardian_stay.arrived_at
     or new.arrived_by is distinct from guardian_stay.arrived_by then
    raise exception 'ACCOMMODATION_CHILD_ARRIVAL_INHERITED' using errcode='23514';
  end if;
  if new.bed_type='extra' and new.extra_bed_person_type is distinct from 'child'
     or new.bed_type<>'extra' and new.extra_bed_person_type is not null then
    raise exception 'ACCOMMODATION_CHILD_BED_TYPE_INVALID' using errcode='23514';
  end if;
  return new;
end $$;

drop trigger if exists conference_accommodation_shared_child_guardian on public.conference_accommodation_occupancies;
drop trigger if exists conference_accommodation_linked_child_guardian on public.conference_accommodation_occupancies;
create trigger conference_accommodation_linked_child_guardian
before insert or update of conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,extra_bed_person_type,arrived_at,arrived_by
on public.conference_accommodation_occupancies for each row
execute function platform_private.enforce_linked_child_guardian_stay();

create or replace function platform_private.sync_guardian_linked_child_stays()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  linked public.conference_accommodation_occupancies%rowtype;
  guardian_before public.conference_accommodation_occupancies%rowtype;
begin
  if tg_op='DELETE' then
    delete from public.conference_accommodation_occupancies child_stay
    using public.conference_participations child
    where child.id=child_stay.participation_id
      and child.conference_id=old.conference_id
      and child.guardian_participation_id=old.participation_id
      and child_stay.conference_id=old.conference_id
      and child_stay.room_id=old.room_id
      and child_stay.arrival_day=old.arrival_day
      and child_stay.leave_day is not distinct from old.leave_day;
    return old;
  end if;

  if tg_op='INSERT' then
    select * into guardian_before
      from public.conference_accommodation_occupancies prior
     where prior.conference_id=new.conference_id
       and prior.participation_id=new.participation_id
       and prior.leave_day=new.arrival_day
     order by prior.arrival_day desc,prior.id
     limit 1;
    if not found then return new; end if;

    for linked in
      select child_stay.*
        from public.conference_accommodation_occupancies child_stay
        join public.conference_participations child on child.id=child_stay.participation_id
       where child.conference_id=new.conference_id
         and child.guardian_participation_id=new.participation_id
         and child_stay.conference_id=new.conference_id
         and child_stay.room_id=guardian_before.room_id
         and child_stay.arrival_day=guardian_before.arrival_day
         and child_stay.leave_day is not distinct from guardian_before.leave_day
       order by child_stay.id for update of child_stay
    loop
      if not platform_private.conference_room_has_capacity(new.conference_id,new.room_id,linked.bed_type,new.arrival_day,new.leave_day,null) then
        raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED' using errcode='55000';
      end if;
      insert into public.conference_accommodation_occupancies(
        conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,
        extra_bed_person_type,arrived_at,arrived_by,created_by,updated_by
      ) values(
        new.conference_id,new.room_id,linked.participation_id,new.arrival_day,new.leave_day,
        linked.bed_type,linked.extra_bed_person_type,new.arrived_at,new.arrived_by,
        linked.created_by,new.updated_by
      );
    end loop;
    return new;
  end if;

  if new.room_id is distinct from old.room_id
     or new.arrival_day is distinct from old.arrival_day
     or new.leave_day is distinct from old.leave_day
     or new.arrived_at is distinct from old.arrived_at
     or new.arrived_by is distinct from old.arrived_by then
    for linked in
      select child_stay.*
        from public.conference_accommodation_occupancies child_stay
        join public.conference_participations child on child.id=child_stay.participation_id
       where child.conference_id=new.conference_id
         and child.guardian_participation_id=new.participation_id
         and child_stay.conference_id=old.conference_id
         and child_stay.room_id=old.room_id
         and child_stay.arrival_day=old.arrival_day
         and child_stay.leave_day is not distinct from old.leave_day
       order by child_stay.id for update of child_stay
    loop
      if not platform_private.conference_room_has_capacity(new.conference_id,new.room_id,linked.bed_type,new.arrival_day,new.leave_day,linked.id) then
        raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED' using errcode='55000';
      end if;
      update public.conference_accommodation_occupancies
         set room_id=new.room_id,arrival_day=new.arrival_day,leave_day=new.leave_day,
             arrived_at=new.arrived_at,arrived_by=new.arrived_by,revision=revision+1,
             updated_at=statement_timestamp(),updated_by=new.updated_by
       where id=linked.id;
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists conference_accommodation_sync_guardian_children on public.conference_accommodation_occupancies;
drop trigger if exists conference_accommodation_sync_guardian_linked_children on public.conference_accommodation_occupancies;
create trigger conference_accommodation_sync_guardian_linked_children
after insert or delete or update of room_id,arrival_day,leave_day,arrived_at,arrived_by
on public.conference_accommodation_occupancies for each row
execute function platform_private.sync_guardian_linked_child_stays();

drop function if exists platform_private.enforce_shared_child_guardian_stay();
drop function if exists platform_private.sync_guardian_shared_child_stays();

-- Child bed updates are deliberately executed before guardian stay updates.
-- Their inherited fields must still match the current guardian segment, then
-- the guardian trigger advances both rows and their revisions atomically.
create or replace function public.save_conference_accommodation_room_draft(
  p_device uuid,
  p_operation_id uuid,
  p_conference uuid,
  p_room uuid,
  p_expected_revision bigint,
  p_expected_assignment_revision bigint,
  p_structure jsonb,
  p_assignments jsonb,
  p_updates jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  ctx jsonb; actor uuid; authz uuid;
  room public.conference_accommodation_rooms%rowtype;
  room_assignment public.conference_room_assignments%rowtype;
  item jsonb; mutation_result jsonb; assignment_results jsonb:='[]'; update_results jsonb:='[]';
  structure_result jsonb; result jsonb; old_values jsonb; extra_capacity integer; days integer;
begin
  if p_operation_id is null then raise exception 'ACCOMMODATION_OPERATION_ID_REQUIRED' using errcode='22023'; end if;
  if p_assignments is null or jsonb_typeof(p_assignments)<>'array' then raise exception 'ACCOMMODATION_ROOM_DRAFT_ASSIGNMENTS_INVALID' using errcode='22023'; end if;
  if p_updates is null or jsonb_typeof(p_updates)<>'array' then raise exception 'ACCOMMODATION_ROOM_DRAFT_UPDATES_INVALID' using errcode='22023'; end if;
  if (p_structure is null or jsonb_typeof(p_structure)='null') and jsonb_array_length(p_assignments)=0 and jsonb_array_length(p_updates)=0 then raise exception 'ACCOMMODATION_ROOM_DRAFT_EMPTY' using errcode='22023'; end if;
  ctx:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
  actor:=(ctx->>'actorUserId')::uuid;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  select new_values into result from platform.audit_events where actor_user_id=actor and operation_id=p_operation_id and scope_id=p_conference and action='conference.accommodation.room_draft_saved' limit 1;
  if result is not null then return result||jsonb_build_object('status','duplicate'); end if;

  perform 1 from public.conference_participations p
   where p.conference_id=p_conference and p.id in(
     select (value->>'participationId')::uuid from jsonb_array_elements(p_assignments)
     union
     select o.participation_id from public.conference_accommodation_occupancies o join jsonb_array_elements(p_updates) u on o.id=(u.value->>'occupancyId')::uuid where o.conference_id=p_conference
     union
     select child.guardian_participation_id from public.conference_accommodation_occupancies o join jsonb_array_elements(p_updates) u on o.id=(u.value->>'occupancyId')::uuid join public.conference_participations child on child.id=o.participation_id where o.conference_id=p_conference and child.guardian_participation_id is not null
   ) order by p.id for update;
  select * into room_assignment from public.conference_room_assignments where conference_id=p_conference and room_id=p_room for update;
  if not found then raise exception 'ROOM_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if;
  if room_assignment.revision<>p_expected_assignment_revision then raise exception 'ROOM_ASSIGNMENT_REVISION_CONFLICT' using errcode='40001'; end if;
  select * into room from public.conference_accommodation_rooms where id=p_room for update;
  if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002'; end if;
  if room.revision<>p_expected_revision then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if;
  perform 1 from public.conference_accommodation_occupancies o where o.conference_id=p_conference and o.id in(select (value->>'occupancyId')::uuid from jsonb_array_elements(p_updates)) order by o.id for update;
  old_values:=jsonb_build_object('room',to_jsonb(room),'assignment',to_jsonb(room_assignment));

  if p_structure is not null and jsonb_typeof(p_structure)<>'null' then
    perform platform_private.require_exact_jsonb_keys(p_structure,array['roomNumber','baseCapacity','extraBedCapacity','notes','isClosed','closedDay','position']);
    extra_capacity:=(p_structure->>'extraBedCapacity')::integer;
    if extra_capacity<0 then raise exception 'ACCOMMODATION_CAPACITY_INVALID' using errcode='22023'; end if;
    if extra_capacity>room_assignment.extra_bed_capacity then update public.conference_room_assignments set extra_bed_capacity=extra_capacity,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=room_assignment.id; end if;
    if (p_structure->>'baseCapacity')::integer>=room.base_capacity and (room.room_number is distinct from p_structure->>'roomNumber' or room.base_capacity is distinct from (p_structure->>'baseCapacity')::integer or coalesce(room.notes,'') is distinct from coalesce(p_structure->>'notes','') or room.is_closed is distinct from (p_structure->>'isClosed')::boolean or room.closed_day is distinct from (p_structure->>'closedDay')::integer or room.position is distinct from (p_structure->>'position')::integer) then
      structure_result:=public.mutate_conference_accommodation_structure(p_device,'update_room',jsonb_build_object('p_conference_id',p_conference,'p_room_id',p_room,'p_expected_revision',p_expected_revision,'p_room_number',p_structure->>'roomNumber','p_base_capacity',p_structure->'baseCapacity','p_extra_bed_capacity',room.extra_bed_capacity,'p_notes',p_structure->'notes','p_is_closed',p_structure->'isClosed','p_closed_day',p_structure->'closedDay','p_position',p_structure->'position'));
    end if;
  end if;

  for item in
    select u.value from jsonb_array_elements(p_updates) u
    join public.conference_accommodation_occupancies o on o.id=(u.value->>'occupancyId')::uuid and o.conference_id=p_conference
    join public.conference_participations part on part.id=o.participation_id
    order by (part.guardian_participation_id is null),u.value->>'occupancyId'
  loop
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
  result:=jsonb_build_object('status','success','operationId',p_operation_id,'roomId',p_room,'structureChanged',p_structure is not null and jsonb_typeof(p_structure)<>'null','structure',structure_result,'assignments',assignment_results,'updates',update_results);
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,scope_id,old_values,new_values,metadata,operation_id,source)
  values(actor,authz,'platform','conference','conference.accommodation.room_draft_saved','accommodation_room',p_room,'conference',p_conference,old_values,result,jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
  return result;
end $$;

revoke all on function platform_private.enforce_linked_child_guardian_stay() from public,anon,authenticated,service_role;
revoke all on function platform_private.sync_guardian_linked_child_stays() from public,anon,authenticated,service_role;
revoke all on function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb) to service_role;

comment on function platform_private.enforce_linked_child_guardian_stay() is
  'Rejects independent linked-child room, stay interval, arrival state, or invalid child bed classification changes.';
comment on function platform_private.sync_guardian_linked_child_stays() is
  'Atomically inherits guardian room, stay segment and arrival state for all linked children while preserving child bed choice and downstream module data.';

commit;
