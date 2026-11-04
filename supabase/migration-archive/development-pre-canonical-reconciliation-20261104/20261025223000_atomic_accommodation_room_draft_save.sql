begin;

-- One transaction owns the room editor Save action. The caller may submit a
-- structural delta, new occupancies, or both. A failure in any nested canonical
-- operation aborts the whole PostgreSQL transaction.
create or replace function public.save_conference_accommodation_room_draft(
  p_device uuid,p_operation_id uuid,p_conference uuid,p_room uuid,
  p_expected_revision bigint,p_structure jsonb,p_assignments jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;actor uuid;authz uuid;room public.conference_accommodation_rooms%rowtype;
 item jsonb;assignment_result jsonb;assignment_results jsonb:='[]'::jsonb;
 structure_result jsonb;result jsonb;old_values jsonb;
begin
 if p_operation_id is null then raise exception 'ACCOMMODATION_OPERATION_ID_REQUIRED' using errcode='22023';end if;
 if (p_structure is null or jsonb_typeof(p_structure)='null') and coalesce(jsonb_array_length(p_assignments),0)=0 then
  raise exception 'ACCOMMODATION_ROOM_DRAFT_EMPTY' using errcode='22023';
 end if;
 if p_assignments is null or jsonb_typeof(p_assignments)<>'array' then
  raise exception 'ACCOMMODATION_ROOM_DRAFT_ASSIGNMENTS_INVALID' using errcode='22023';
 end if;
 ctx:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
 actor:=(ctx->>'actorUserId')::uuid;
 authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
 select new_values into result from platform.audit_events
  where actor_user_id=actor and operation_id=p_operation_id and scope_id=p_conference
    and action='conference.accommodation.room_draft_saved' limit 1;
 if result is not null then return result||jsonb_build_object('status','duplicate');end if;

 select * into room from public.conference_accommodation_rooms
  where id=p_room and conference_id=p_conference for update;
 if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002';end if;
 if room.revision<>p_expected_revision then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;
 old_values:=to_jsonb(room);

 if p_structure is not null and jsonb_typeof(p_structure)<>'null' then
  perform platform_private.require_exact_jsonb_keys(p_structure,array['roomNumber','baseCapacity','extraBedCapacity','notes','isClosed','closedDay','position']);
  structure_result:=public.mutate_conference_accommodation_structure(p_device,'update_room',jsonb_build_object(
   'p_conference_id',p_conference,'p_room_id',p_room,'p_expected_revision',p_expected_revision,
   'p_room_number',p_structure->>'roomNumber','p_base_capacity',p_structure->'baseCapacity',
   'p_extra_bed_capacity',p_structure->'extraBedCapacity','p_notes',p_structure->'notes',
   'p_is_closed',p_structure->'isClosed','p_closed_day',p_structure->'closedDay','p_position',p_structure->'position'));
 end if;

 for item in select value from jsonb_array_elements(p_assignments) loop
  perform platform_private.require_exact_jsonb_keys(item,array['participationId','arrivalDay','leaveDay','bedType','extraBedPersonType']);
  assignment_result:=public.assign_conference_accommodation(
   p_device,p_conference,p_room,(item->>'participationId')::uuid,
   (item->>'arrivalDay')::integer,(item->>'leaveDay')::integer,
   item->>'bedType',item->>'extraBedPersonType');
  assignment_results:=assignment_results||jsonb_build_array(assignment_result);
 end loop;

 result:=jsonb_build_object('status','success','operationId',p_operation_id,'roomId',p_room,
  'structureChanged',p_structure is not null and jsonb_typeof(p_structure)<>'null','structure',structure_result,'assignments',assignment_results);
 insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,
  entity_type,entity_id,scope_type,scope_id,old_values,new_values,metadata,operation_id,source)
 values(actor,authz,'platform','conference','conference.accommodation.room_draft_saved',
  'accommodation_room',p_room,'conference',p_conference,old_values,result,
  jsonb_build_object('conferenceId',p_conference,'permissionKey','conference.accommodation.manage',
   'authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
 return result;
end $$;

do $dispatch$
declare d text;marker text;branch text;
begin
 d:=pg_get_functiondef('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure);
 if position('p_operation=''save_conference_accommodation_room_draft''' in d)=0 then
  marker:='elsif p_operation=''replace_conference_accommodation'' then';
  branch:=$body$elsif p_operation='save_conference_accommodation_room_draft' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_room_id','p_expected_revision','p_structure','p_assignments','p_room_lease_tokens']);
    perform platform_private.require_accommodation_operation_leases(p_actor_device_id,(p_args->>'p_conference_id')::uuid,'assign_conference_accommodation',jsonb_build_object('p_room_id',p_args->>'p_room_id','p_room_lease_tokens',p_args->'p_room_lease_tokens'));
    return public.save_conference_accommodation_room_draft(p_actor_device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_conference_id')::uuid,(p_args->>'p_room_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_structure',p_args->'p_assignments');
  elsif p_operation='replace_conference_accommodation' then$body$;
  if position(marker in d)=0 then raise exception 'ACCOMMODATION_ROOM_DRAFT_DISPATCH_MARKER_MISSING';end if;
  execute replace(d,marker,branch);
 end if;
end $dispatch$;

revoke all on function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,jsonb,jsonb) to service_role;

commit;
