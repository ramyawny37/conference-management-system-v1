begin;

create or replace function public.add_conference_guardian_child_accommodation(
 p_device uuid,p_operation_id uuid,p_conference uuid,p_args jsonb
) returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 ctx jsonb;people_ctx jsonb;actor uuid;authz uuid;guardian public.conference_participations%rowtype;child public.conference_participations%rowtype;
 guardian_stay public.conference_accommodation_occupancies%rowtype;child_stay public.conference_accommodation_occupancies%rowtype;
 person_id uuid;room_id uuid;bed text;result jsonb;old_values jsonb;new_values jsonb;
begin
 perform platform_private.require_exact_jsonb_keys(p_args,array['roomId','guardianParticipationId','childPersonId','childFullName','bedType']);
 ctx:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
 people_ctx:=platform_private.require_conference_participation_context(p_device,p_conference,'conference.people.manage',true);
 actor:=(ctx->>'actorUserId')::uuid;
 if actor is distinct from (people_ctx->>'actorUserId')::uuid then raise exception 'CONFERENCE_OPERATION_ACTOR_MISMATCH' using errcode='42501';end if;
 authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
 select ae.new_values into result from platform.audit_events ae where ae.actor_user_id=actor and ae.operation_id=p_operation_id and ae.scope_id=p_conference and ae.action='conference.accommodation.guardian_child_added' limit 1;
 if result is not null then return result||jsonb_build_object('status','duplicate');end if;
 room_id:=(p_args->>'roomId')::uuid;bed:=p_args->>'bedType';
 if room_id is null or nullif(trim(p_args->>'guardianParticipationId'),'') is null or bed not in('shared','base','extra') then raise exception 'ACCOMMODATION_GUARDIAN_CHILD_INVALID' using errcode='22023';end if;
 if (nullif(p_args->>'childPersonId','') is null)=(nullif(trim(p_args->>'childFullName'),'') is null) then raise exception 'ACCOMMODATION_CHILD_PERSON_OR_NAME_REQUIRED' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||p_conference::text||':'||(p_args->>'guardianParticipationId'),0));
 select * into guardian from public.conference_participations where id=(p_args->>'guardianParticipationId')::uuid and conference_id=p_conference and status='active' for update;
 if not found or guardian.guardian_participation_id is not null then raise exception 'ACCOMMODATION_GUARDIAN_NOT_ACTIVE' using errcode='23514';end if;
 select * into guardian_stay from public.conference_accommodation_occupancies where conference_id=p_conference and room_id=room_id and participation_id=guardian.id and arrival_day<=platform_private.conference_operational_day(p_conference) and coalesce(leave_day,platform_private.conference_accommodation_duration(p_conference)+1)>platform_private.conference_operational_day(p_conference) for update;
 if not found then raise exception 'ACCOMMODATION_SHARED_CHILD_GUARDIAN_STAY_REQUIRED' using errcode='23514';end if;
 if nullif(p_args->>'childPersonId','') is not null then
   person_id:=(p_args->>'childPersonId')::uuid;
   perform 1 from platform.people where id=person_id for key share;
   if not found then raise exception 'CONFERENCE_PERSON_NOT_FOUND' using errcode='P0002';end if;
 else
   insert into platform.people(full_name,created_by,updated_by) values(trim(p_args->>'childFullName'),actor,actor) returning id into person_id;
 end if;
 select * into child from public.conference_participations where conference_id=p_conference and person_id=person_id and status='active' for update;
 if not found then
   insert into public.conference_participations(conference_id,person_id,guardian_participation_id,status,created_by,updated_by) values(p_conference,person_id,guardian.id,'active',actor,actor) returning * into child;
 elsif child.guardian_participation_id is null then
   update public.conference_participations set guardian_participation_id=guardian.id,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=child.id returning * into child;
 elsif child.guardian_participation_id is distinct from guardian.id then
   raise exception 'CONFERENCE_CHILD_GUARDIAN_MISMATCH' using errcode='23514';
 end if;
 select * into child_stay from public.conference_accommodation_occupancies where conference_id=p_conference and participation_id=child.id and arrival_day<=platform_private.conference_operational_day(p_conference) and coalesce(leave_day,platform_private.conference_accommodation_duration(p_conference)+1)>platform_private.conference_operational_day(p_conference) for update;
 if found then
   if child_stay.room_id is distinct from room_id or child_stay.arrival_day is distinct from guardian_stay.arrival_day or child_stay.leave_day is distinct from guardian_stay.leave_day or child_stay.bed_type is distinct from bed then raise exception 'ACCOMMODATION_CHILD_ALREADY_ASSIGNED_DIFFERENTLY' using errcode='23514';end if;
 else
   perform public.assign_conference_accommodation(p_device,p_conference,room_id,child.id,guardian_stay.arrival_day,guardian_stay.leave_day,bed,case when bed='extra' then 'child' else null end);
 end if;
 result:=jsonb_build_object('status','success','roomId',room_id,'guardianParticipationId',guardian.id,'childParticipationId',child.id,'bedType',bed);
 insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,scope_id,old_values,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.accommodation.guardian_child_added','conference_participation',child.id,'conference',p_conference,old_values,result,jsonb_build_object('conferenceId',p_conference,'roomId',room_id,'guardianParticipationId',guardian.id,'permissionKey','conference.accommodation.manage','peoplePermissionKey','conference.people.manage','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),p_operation_id,'rpc');
 return result;
end $function$;

do $block$
declare d text;needle text:='if p_operation_id is null or p_operation not in(''set_arrival'',''set_room_key'') then';
begin
 select pg_get_functiondef('public.mutate_conference_accommodation_operations(uuid,uuid,uuid,text,jsonb)'::regprocedure) into d;
 if position(needle in d)=0 then raise exception 'MUTATE_ACCOMMODATION_OPERATIONS_SHAPE_CHANGED';end if;
 d:=replace(d,needle,'if p_operation_id is null or p_operation not in(''set_arrival'',''set_room_key'',''add_guardian_child'') then');
 d:=replace(d,'case when p_operation=''set_arrival'' then ''conference.accommodation.arrival_updated'' else ''conference.accommodation.room_key_updated'' end','case when p_operation=''set_arrival'' then ''conference.accommodation.arrival_updated'' when p_operation=''set_room_key'' then ''conference.accommodation.room_key_updated'' else ''conference.accommodation.guardian_child_added'' end');
 d:=replace(d,'if p_operation=''set_arrival'' then','if p_operation=''add_guardian_child'' then return public.add_conference_guardian_child_accommodation(p_device,p_operation_id,p_conference,p_args); end if; if p_operation=''set_arrival'' then');
 execute d;
end $block$;

revoke all on function public.add_conference_guardian_child_accommodation(uuid,uuid,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.add_conference_guardian_child_accommodation(uuid,uuid,uuid,jsonb) to service_role;
commit;
