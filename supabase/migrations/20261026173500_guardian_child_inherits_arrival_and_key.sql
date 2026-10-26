begin;

create or replace function public.mutate_conference_accommodation_operations(
  p_device uuid,p_operation_id uuid,p_conference uuid,p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 ctx jsonb;actor uuid;authz uuid;occupancy public.conference_accommodation_occupancies%rowtype;
 assignment public.conference_room_assignments%rowtype;holder public.conference_accommodation_occupancies%rowtype;
 holder_participation public.conference_participations%rowtype;old_values jsonb;new_values jsonb;result jsonb;expected bigint;room_id uuid;holder_id uuid;
begin
 if p_operation_id is null or p_operation not in('set_arrival','set_room_key') then raise exception 'ACCOMMODATION_OPERATION_INVALID' using errcode='22023';end if;
 ctx:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
 actor:=(ctx->>'actorUserId')::uuid;authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
 select ae.new_values into result from platform.audit_events ae where actor_user_id=actor and operation_id=p_operation_id and scope_id=p_conference and action=case when p_operation='set_arrival' then 'conference.accommodation.arrival_updated' else 'conference.accommodation.room_key_updated' end limit 1;
 if result is not null then return result||jsonb_build_object('status','duplicate');end if;
 if p_operation='set_arrival' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['occupancyId','expectedRevision','arrived']);
  if jsonb_typeof(p_args->'arrived') is distinct from 'boolean' then raise exception 'ARRIVAL_BOOLEAN_REQUIRED' using errcode='22023';end if;
  expected:=(p_args->>'expectedRevision')::bigint;
  select * into occupancy from public.conference_accommodation_occupancies where id=(p_args->>'occupancyId')::uuid and conference_id=p_conference for update;
  if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002';end if;
  select * into holder_participation from public.conference_participations where id=occupancy.participation_id and conference_id=p_conference;
  if holder_participation.guardian_participation_id is not null then raise exception 'ACCOMMODATION_CHILD_ARRIVAL_INHERITED' using errcode='23514';end if;
  if occupancy.revision<>expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;
  room_id:=occupancy.room_id;old_values:=to_jsonb(occupancy);
  update public.conference_accommodation_occupancies set arrived_at=case when (p_args->>'arrived')::boolean then coalesce(arrived_at,statement_timestamp()) else null end,arrived_by=case when (p_args->>'arrived')::boolean then coalesce(arrived_by,actor) else null end,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=occupancy.id returning * into occupancy;
  new_values:=to_jsonb(occupancy);result:=jsonb_build_object('status','success','occupancyId',occupancy.id,'revision',occupancy.revision,'arrivedAt',occupancy.arrived_at,'arrivedBy',occupancy.arrived_by);
 else
  perform platform_private.require_exact_jsonb_keys(p_args,array['roomId','expectedRevision','holderOccupancyId']);
  room_id:=(p_args->>'roomId')::uuid;expected:=(p_args->>'expectedRevision')::bigint;holder_id:=nullif(p_args->>'holderOccupancyId','')::uuid;
  select * into assignment from public.conference_room_assignments where conference_id=p_conference and public.conference_room_assignments.room_id=(p_args->>'roomId')::uuid for update;
  if not found then raise exception 'ROOM_ASSIGNMENT_NOT_FOUND' using errcode='P0002';end if;
  if assignment.revision<>expected then raise exception 'ROOM_ASSIGNMENT_REVISION_CONFLICT' using errcode='40001';end if;
  if holder_id is not null then
   select * into holder from public.conference_accommodation_occupancies where id=holder_id and conference_id=p_conference and public.conference_accommodation_occupancies.room_id=(p_args->>'roomId')::uuid and arrival_day<=platform_private.conference_operational_day(p_conference) and coalesce(leave_day,platform_private.conference_accommodation_duration(p_conference)+1)>platform_private.conference_operational_day(p_conference) for key share;
   if not found then raise exception 'ROOM_KEY_HOLDER_NOT_CURRENT_OCCUPANT' using errcode='22023';end if;
   select * into holder_participation from public.conference_participations where id=holder.participation_id and conference_id=p_conference;
   if holder_participation.guardian_participation_id is not null then raise exception 'ACCOMMODATION_CHILD_KEY_INHERITED' using errcode='23514';end if;
  end if;
  old_values:=to_jsonb(assignment);
  update public.conference_room_assignments set key_holder_occupancy_id=holder_id,key_delivered_at=case when holder_id is null then null else statement_timestamp() end,key_delivered_by=case when holder_id is null then null else actor end,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=assignment.id returning * into assignment;
  new_values:=to_jsonb(assignment);result:=jsonb_build_object('status','success','roomId',room_id,'roomAssignmentId',assignment.id,'revision',assignment.revision,'keyHolderOccupancyId',assignment.key_holder_occupancy_id,'keyDeliveredAt',assignment.key_delivered_at,'keyDeliveredBy',assignment.key_delivered_by);
 end if;
 insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,scope_id,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference',case when p_operation='set_arrival' then 'conference.accommodation.arrival_updated' else 'conference.accommodation.room_key_updated' end,case when p_operation='set_arrival' then 'accommodation_occupancy' else 'conference_room_assignment' end,case when p_operation='set_arrival' then occupancy.id else assignment.id end,'conference',p_conference,old_values,new_values,jsonb_build_object('conferenceId',p_conference,'roomId',room_id,'permissionKey','conference.accommodation.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
 return result;
end $function$;

update public.conference_accommodation_occupancies o
set arrived_at=null,arrived_by=null,revision=o.revision+1,updated_at=statement_timestamp()
from public.conference_participations cp
where cp.id=o.participation_id and cp.guardian_participation_id is not null and (o.arrived_at is not null or o.arrived_by is not null);

update public.conference_room_assignments ra
set key_holder_occupancy_id=null,key_delivered_at=null,key_delivered_by=null,revision=ra.revision+1,updated_at=statement_timestamp()
where ra.key_holder_occupancy_id in (
 select o.id from public.conference_accommodation_occupancies o
 join public.conference_participations cp on cp.id=o.participation_id
 where cp.guardian_participation_id is not null
);

commit;