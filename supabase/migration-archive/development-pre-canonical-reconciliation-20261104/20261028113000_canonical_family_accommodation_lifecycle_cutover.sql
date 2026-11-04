begin;

-- Family ownership is participation-level.  Only a shared-bed child inherits a guardian stay.
create or replace function platform_private.enforce_linked_child_guardian_stay()
returns trigger language plpgsql security definer set search_path='' as $function$
declare child public.conference_participations%rowtype; guardian_stay public.conference_accommodation_occupancies%rowtype;
begin
 select * into child from public.conference_participations where id=new.participation_id and conference_id=new.conference_id;
 if not found or child.guardian_participation_id is null then return new; end if;
 if new.bed_type<>'shared' then
   if new.bed_type='extra' and new.extra_bed_person_type is distinct from 'child' then raise exception 'ACCOMMODATION_CHILD_BED_TYPE_INVALID' using errcode='23514';end if;
   return new;
 end if;
 select * into guardian_stay from public.conference_accommodation_occupancies guardian where guardian.conference_id=new.conference_id and guardian.participation_id=child.guardian_participation_id and guardian.room_id=new.room_id and guardian.arrival_day=new.arrival_day and guardian.leave_day is not distinct from new.leave_day order by guardian.id limit 1 for key share;
 if not found then raise exception 'ACCOMMODATION_SHARED_CHILD_GUARDIAN_STAY_REQUIRED' using errcode='23514';end if;
 if tg_op='INSERT' then new.arrived_at:=guardian_stay.arrived_at;new.arrived_by:=guardian_stay.arrived_by;
 elsif new.arrived_at is distinct from guardian_stay.arrived_at or new.arrived_by is distinct from guardian_stay.arrived_by then raise exception 'ACCOMMODATION_CHILD_ARRIVAL_INHERITED' using errcode='23514';end if;
 return new;
end $function$;

create or replace function platform_private.require_conference_family_accommodation_leases(
 p_device uuid,p_conference uuid,p_payload jsonb
) returns uuid[] language plpgsql security definer set search_path='' as $function$
declare room_ids uuid[];supplied uuid[];entry jsonb;
begin
 if jsonb_typeof(p_payload->'roomLeaseTokens') is distinct from 'array' then raise exception 'ROOM_LEASE_TOKENS_REQUIRED' using errcode='42501';end if;
 select array_agg(distinct id order by id) into room_ids from (
   select nullif(s.value->>'targetRoomId','')::uuid id from jsonb_array_elements(p_payload->'stays') s
   union select nullif(s.value->>'roomId','')::uuid from jsonb_array_elements(p_payload->'stays') s
   union select o.room_id from public.conference_accommodation_occupancies o join jsonb_array_elements(p_payload->'stays') s on o.id=nullif(s.value->>'occupancyId','')::uuid where o.conference_id=p_conference
   union select nullif(c.value->>'targetRoomId','')::uuid from jsonb_array_elements(p_payload->'children') c
   union select nullif(p_payload->'roomDraft'->>'roomId','')::uuid
 ) rooms where id is not null;
 if room_ids is null then raise exception 'FAMILY_ACCOMMODATION_ROOMS_REQUIRED' using errcode='22023';end if;
 select array_agg(distinct (token->>'roomId')::uuid order by (token->>'roomId')::uuid) into supplied from jsonb_array_elements(p_payload->'roomLeaseTokens') token;
 if supplied is distinct from room_ids then raise exception 'ROOM_LEASE_SCOPE_MISMATCH' using errcode='42501';end if;
 for entry in select value from jsonb_array_elements(p_payload->'roomLeaseTokens') order by value->>'roomId' loop
   perform platform_private.require_conference_room_lease(p_device,p_conference,(entry->>'roomId')::uuid,(entry->>'token')::uuid);
 end loop;
 return room_ids;
end $function$;

create or replace function public.save_conference_family_accommodation_draft(
 p_device uuid,p_operation_id uuid,p_conference uuid,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
 ctx jsonb;actor uuid;authz uuid;stay jsonb;child_draft jsonb;room_ids uuid[];v_room_id uuid;result jsonb;mutation jsonb;room_draft jsonb;resolved_children jsonb:='[]'::jsonb;mutation_results jsonb:='[]'::jsonb;
 guardian_draft jsonb;guardian_participation public.conference_participations%rowtype;child_participation public.conference_participations%rowtype;
 guardian_stay public.conference_accommodation_occupancies%rowtype;v_guardian_person_id uuid;v_child_person_id uuid;
 draft_room public.conference_accommodation_rooms%rowtype;draft_assignment public.conference_room_assignments%rowtype;
begin
 ctx:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.manage',true);
 perform platform_private.require_conference_participation_context(p_device,p_conference,'conference.people.manage',true);
 actor:=(ctx->>'actorUserId')::uuid;authz:=platform_private.validated_phase1c_device_authorization(actor,p_device);
 perform platform_private.require_exact_jsonb_keys(p_payload,array['roomDraft','guardian','children','stays','roomLeaseTokens']);
 if p_operation_id is null or jsonb_typeof(p_payload->'stays')<>'array' or jsonb_typeof(p_payload->'roomLeaseTokens')<>'array' then raise exception 'FAMILY_ACCOMMODATION_DRAFT_INVALID' using errcode='22023';end if;
 select ae.new_values into result from platform.audit_events ae where ae.actor_user_id=actor and ae.operation_id=p_operation_id and ae.scope_id=p_conference and ae.action='conference.accommodation.family_draft_saved' limit 1;
 if result is not null then return result||jsonb_build_object('status','duplicate');end if;
 -- Existing participation locks always precede room and occupancy locks.
 perform 1 from public.conference_participations cp where cp.conference_id=p_conference and cp.id in(
   select nullif(p_payload->'guardian'->>'participationId','')::uuid
   union select nullif(c.value->>'participationId','')::uuid from jsonb_array_elements(p_payload->'children') c
   union select nullif(c.value->>'guardianParticipationId','')::uuid from jsonb_array_elements(p_payload->'children') c
   union select nullif(s.value->>'participationId','')::uuid from jsonb_array_elements(p_payload->'stays') s
   union select o.participation_id from public.conference_accommodation_occupancies o join jsonb_array_elements(p_payload->'stays') s on o.id=nullif(s.value->>'occupancyId','')::uuid where o.conference_id=p_conference
 ) order by cp.id for update;
 room_ids:=platform_private.require_conference_family_accommodation_leases(p_device,p_conference,p_payload);
 foreach v_room_id in array room_ids loop perform 1 from public.conference_accommodation_rooms where id=v_room_id for update; end loop;
	 guardian_draft:=p_payload->'guardian';
	 if guardian_draft is not null and jsonb_typeof(guardian_draft)<>'null' then
	   perform platform_private.require_exact_jsonb_keys(guardian_draft,array['draftId','participationId','personId','fullName','phone','church','gender','dateOfBirth']);
   if nullif(guardian_draft->>'participationId','') is not null then
     select * into guardian_participation from public.conference_participations where id=(guardian_draft->>'participationId')::uuid and conference_id=p_conference and status='active';
   else
     if nullif(guardian_draft->>'personId','') is not null then v_guardian_person_id:=(guardian_draft->>'personId')::uuid;
     else if nullif(trim(guardian_draft->>'fullName'),'') is null then raise exception 'FAMILY_GUARDIAN_NAME_REQUIRED' using errcode='22023';end if;insert into platform.people(full_name,phone,church,gender,date_of_birth,created_by,updated_by) values(trim(guardian_draft->>'fullName'),nullif(trim(guardian_draft->>'phone'),''),nullif(trim(guardian_draft->>'church'),''),nullif(guardian_draft->>'gender',''),nullif(guardian_draft->>'dateOfBirth','')::date,actor,actor) returning id into v_guardian_person_id;end if;
     select * into guardian_participation from public.conference_participations cp where cp.conference_id=p_conference and cp.person_id=v_guardian_person_id and cp.status='active';
     if not found then insert into public.conference_participations(conference_id,person_id,status,created_by,updated_by) values(p_conference,v_guardian_person_id,'active',actor,actor) returning * into guardian_participation;end if;
   end if;
   if guardian_participation.id is null or guardian_participation.guardian_participation_id is not null then raise exception 'FAMILY_GUARDIAN_PARTICIPATION_INVALID' using errcode='23514';end if;
 end if;
	 for child_draft in select value from jsonb_array_elements(p_payload->'children') loop
	   perform platform_private.require_exact_jsonb_keys(child_draft,array['draftId','guardianDraftId','guardianParticipationId','participationId','personId','fullName','targetRoomId','arrivalDay','leaveDay','bedType']);
	   if nullif(child_draft->>'guardianDraftId','') is not null and (guardian_draft is null or child_draft->>'guardianDraftId' is distinct from guardian_draft->>'draftId') then raise exception 'FAMILY_CHILD_GUARDIAN_DRAFT_MISMATCH' using errcode='23514';end if;
   if nullif(child_draft->>'guardianParticipationId','') is not null then select * into guardian_participation from public.conference_participations where id=(child_draft->>'guardianParticipationId')::uuid and conference_id=p_conference and status='active';end if;
   if guardian_participation.id is null then raise exception 'FAMILY_CHILD_GUARDIAN_REQUIRED' using errcode='23514';end if;
   if nullif(child_draft->>'participationId','') is not null then
     select * into child_participation from public.conference_participations where id=(child_draft->>'participationId')::uuid and conference_id=p_conference and status='active';
   else
     if nullif(child_draft->>'personId','') is not null then v_child_person_id:=(child_draft->>'personId')::uuid;
     else if nullif(trim(child_draft->>'fullName'),'') is null then raise exception 'FAMILY_CHILD_NAME_REQUIRED' using errcode='22023';end if;insert into platform.people(full_name,created_by,updated_by) values(trim(child_draft->>'fullName'),actor,actor) returning id into v_child_person_id;end if;
     select * into child_participation from public.conference_participations cp where cp.conference_id=p_conference and cp.person_id=v_child_person_id and cp.status='active';
     if not found then insert into public.conference_participations(conference_id,person_id,guardian_participation_id,status,created_by,updated_by) values(p_conference,v_child_person_id,guardian_participation.id,'active',actor,actor) returning * into child_participation;end if;
   end if;
   if child_participation.id is null then raise exception 'FAMILY_CHILD_PARTICIPATION_INVALID' using errcode='23514';end if;
   if child_participation.guardian_participation_id is null then update public.conference_participations set guardian_participation_id=guardian_participation.id,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where id=child_participation.id returning * into child_participation;
   elsif child_participation.guardian_participation_id is distinct from guardian_participation.id then raise exception 'FAMILY_CHILD_GUARDIAN_MISMATCH' using errcode='23514';end if;
   resolved_children:=resolved_children||jsonb_build_array(child_draft||jsonb_build_object('resolvedParticipationId',child_participation.id,'resolvedGuardianParticipationId',guardian_participation.id));
 end loop;
	 room_draft:=p_payload->'roomDraft';
	 if room_draft is not null and jsonb_typeof(room_draft)<>'null' then
	   perform platform_private.require_exact_jsonb_keys(room_draft,array['roomId','expectedRevision','expectedAssignmentRevision','structure']);
	   select * into draft_assignment from public.conference_room_assignments where conference_id=p_conference and room_id=(room_draft->>'roomId')::uuid for update;
	   if not found then raise exception 'ROOM_ASSIGNMENT_NOT_FOUND' using errcode='P0002';end if;
	   if draft_assignment.revision<>(room_draft->>'expectedAssignmentRevision')::bigint then raise exception 'ROOM_ASSIGNMENT_REVISION_CONFLICT' using errcode='40001';end if;
	   select * into draft_room from public.conference_accommodation_rooms where id=(room_draft->>'roomId')::uuid for update;
	   if not found then raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002';end if;
	   if draft_room.revision<>(room_draft->>'expectedRevision')::bigint then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;
	 end if;
	 if room_draft is not null and jsonb_typeof(room_draft)<>'null' and room_draft->'structure' is not null and jsonb_typeof(room_draft->'structure')<>'null' then
   perform public.save_conference_accommodation_room_draft(p_device,gen_random_uuid(),p_conference,(room_draft->>'roomId')::uuid,(room_draft->>'expectedRevision')::bigint,(room_draft->>'expectedAssignmentRevision')::bigint,room_draft->'structure','[]'::jsonb,'[]'::jsonb,'[]'::jsonb);
 end if;
	 for stay in select value from jsonb_array_elements(p_payload->'stays') loop
	   if stay->>'operation'='assign' then perform platform_private.require_exact_jsonb_keys(stay,array['operation','sourceRoomId','targetRoomId','roomId','participationId','guardianDraftId','arrivalDay','leaveDay','bedType','extraBedPersonType']);
	   elsif stay->>'operation'='move' then perform platform_private.require_exact_jsonb_keys(stay,array['operation','sourceRoomId','targetRoomId','roomId','occupancyId','expectedRevision','arrivalDay','leaveDay','bedType','extraBedPersonType']);
	   elsif stay->>'operation'='replace' then perform platform_private.require_exact_jsonb_keys(stay,array['operation','sourceRoomId','targetRoomId','roomId','occupancyId','expectedRevision','participationId','effectiveDay','bedType','extraBedPersonType']);
	   elsif stay->>'operation'='remove' then perform platform_private.require_exact_jsonb_keys(stay,array['operation','sourceRoomId','targetRoomId','roomId','occupancyId','expectedRevision']);
	   else raise exception 'FAMILY_ACCOMMODATION_OPERATION_INVALID' using errcode='22023';end if;
	   case stay->>'operation'
    when 'assign' then
      if nullif(stay->>'guardianDraftId','') is not null then
        if guardian_participation.id is null or stay->>'guardianDraftId' is distinct from guardian_draft->>'draftId' then raise exception 'FAMILY_GUARDIAN_DRAFT_ASSIGNMENT_INVALID' using errcode='23514';end if;
        mutation:=public.assign_conference_accommodation(p_device,p_conference,(stay->>'targetRoomId')::uuid,guardian_participation.id,(stay->>'arrivalDay')::integer,nullif(stay->>'leaveDay','')::integer,stay->>'bedType',nullif(stay->>'extraBedPersonType',''));
      else mutation:=public.assign_conference_accommodation(p_device,p_conference,(stay->>'targetRoomId')::uuid,(stay->>'participationId')::uuid,(stay->>'arrivalDay')::integer,nullif(stay->>'leaveDay','')::integer,stay->>'bedType',nullif(stay->>'extraBedPersonType',''));end if;
    when 'move' then mutation:=public.move_conference_accommodation(p_device,p_conference,(stay->>'occupancyId')::uuid,(stay->>'expectedRevision')::bigint,(stay->>'targetRoomId')::uuid,(stay->>'arrivalDay')::integer,nullif(stay->>'leaveDay','')::integer,stay->>'bedType',nullif(stay->>'extraBedPersonType',''));
    when 'replace' then mutation:=public.replace_conference_accommodation(p_device,gen_random_uuid(),p_conference,(stay->>'occupancyId')::uuid,(stay->>'expectedRevision')::bigint,(stay->>'participationId')::uuid,(stay->>'effectiveDay')::integer,stay->>'bedType',nullif(stay->>'extraBedPersonType',''));
    when 'remove' then mutation:=public.remove_conference_accommodation(p_device,p_conference,(stay->>'occupancyId')::uuid,(stay->>'expectedRevision')::bigint);
	    else raise exception 'FAMILY_ACCOMMODATION_OPERATION_INVALID' using errcode='22023';
	   end case;
	   mutation_results:=mutation_results||jsonb_build_array(mutation);
 end loop;
 for child_draft in select value from jsonb_array_elements(resolved_children) loop
   if child_draft->>'bedType'='shared' then
     select * into guardian_stay from public.conference_accommodation_occupancies where conference_id=p_conference and participation_id=(child_draft->>'resolvedGuardianParticipationId')::uuid and room_id=(child_draft->>'targetRoomId')::uuid and arrival_day=(child_draft->>'arrivalDay')::integer and leave_day is not distinct from nullif(child_draft->>'leaveDay','')::integer for key share;
     if not found then raise exception 'ACCOMMODATION_SHARED_CHILD_GUARDIAN_STAY_REQUIRED' using errcode='23514';end if;
   end if;
   mutation:=public.assign_conference_accommodation(p_device,p_conference,(child_draft->>'targetRoomId')::uuid,(child_draft->>'resolvedParticipationId')::uuid,(child_draft->>'arrivalDay')::integer,nullif(child_draft->>'leaveDay','')::integer,child_draft->>'bedType',case when child_draft->>'bedType'='extra' then 'child' else null end);
 end loop;
	 result:=jsonb_build_object('status','success','operationId',p_operation_id,'roomIds',to_jsonb(room_ids),'mutations',mutation_results,'children',resolved_children);
 insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,scope_id,new_values,metadata,operation_id,source) values(actor,authz,'platform','conference','conference.accommodation.family_draft_saved','conference',p_conference,'conference',p_conference,result,jsonb_build_object('roomIds',room_ids,'permissionKey','conference.accommodation.manage'),p_operation_id,'rpc');
 return result;
end $function$;

revoke all on function public.save_conference_family_accommodation_draft(uuid,uuid,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.save_conference_family_accommodation_draft(uuid,uuid,uuid,jsonb) to service_role;

do $lifecycle$
declare d text;
begin
 d:=pg_get_functiondef('public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text)'::regprocedure);
 if position('if participation.guardian_participation_id is not null then' in d)=0 or position('cp.guardian_participation_id=participation.id' in d)=0 then raise exception 'FAMILY_MOVE_SHAPE_CHANGED';end if;
 d:=replace(d,'if participation.guardian_participation_id is not null then','if participation.guardian_participation_id is not null and current.bed_type=''shared'' then');
 d:=replace(d,'cp.guardian_participation_id=participation.id','cp.guardian_participation_id=participation.id and o.bed_type=''shared''');
 execute d;
 d:=pg_get_functiondef('public.replace_conference_accommodation(uuid,uuid,uuid,uuid,bigint,uuid,integer,text,text)'::regprocedure);
 if position('and cp.guardian_participation_id=old_stay.participation_id' in d)=0 then raise exception 'FAMILY_REPLACE_SHAPE_CHANGED';end if;
 d:=replace(d,'and cp.guardian_participation_id=old_stay.participation_id','and cp.guardian_participation_id=old_stay.participation_id and o.bed_type=''shared''');
 if position('if room.key_holder_occupancy_id=child_stay.id then' in d)>0 then
   d:=replace(d,'if room.key_holder_occupancy_id=child_stay.id then
     update public.conference_accommodation_rooms
       set key_holder_occupancy_id=null,updated_at=statement_timestamp(),updated_by=actor
       where id=room.id;
   end if;',
   'update public.conference_room_assignments set key_holder_occupancy_id=null,key_delivered_at=null,key_delivered_by=null,revision=revision+1,updated_at=statement_timestamp(),updated_by=actor where conference_id=p_conference and room_id=old_stay.room_id and key_holder_occupancy_id=child_stay.id;');
 end if;
 execute d;
 d:=pg_get_functiondef('public.remove_conference_accommodation(uuid,uuid,uuid,bigint)'::regprocedure);
 if position('if current.revision<>p_expected then' in d)=0 then raise exception 'FAMILY_REMOVE_SHAPE_CHANGED';end if;
 d:=replace(d,'if current.revision<>p_expected then raise exception ''ACCOMMODATION_REVISION_CONFLICT'' using errcode=''40001'';end if;',
 'if current.revision<>p_expected then raise exception ''ACCOMMODATION_REVISION_CONFLICT'' using errcode=''40001'';end if; if exists(select 1 from public.conference_participations cp join public.conference_accommodation_occupancies child on child.participation_id=cp.id where cp.guardian_participation_id=current.participation_id and child.conference_id=p_conference and child.bed_type=''shared'' and child.room_id=current.room_id and child.arrival_day=current.arrival_day and child.leave_day is not distinct from current.leave_day) then raise exception ''ACCOMMODATION_SHARED_CHILD_RESOLUTION_REQUIRED'' using errcode=''23514'';end if;');
 execute d;
end $lifecycle$;

do $dispatch$
declare d text;marker text;branch text;
begin
 d:=pg_get_functiondef('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure);
 if position('p_operation=''save_conference_family_accommodation_draft''' in d)>0 then return;end if;
 marker:='elsif p_operation=''save_conference_accommodation_room_draft'' then';
 branch:='elsif p_operation=''save_conference_family_accommodation_draft'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_conference_id'',''p_payload'']); perform platform_private.require_conference_family_accommodation_leases(p_actor_device_id,(p_args->>''p_conference_id'')::uuid,p_args->''p_payload''); return public.save_conference_family_accommodation_draft(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_conference_id'')::uuid,p_args->''p_payload''); '||marker;
 if position(marker in d)=0 then raise exception 'FAMILY_DISPATCH_MARKER_MISSING';end if;
 execute replace(d,marker,branch);
end $dispatch$;

revoke all on function platform_private.require_conference_family_accommodation_leases(uuid,uuid,jsonb) from public,anon,authenticated,service_role;

-- Marker names retained here to make the cutover explicit: conference_accommodation_linked_child_guardian
-- and conference_accommodation_sync_guardian_linked_children are superseded by the shared-only trigger above.
-- move_conference_accommodation, replace_conference_accommodation and remove_conference_accommodation
-- must no longer cascade independently bedded children.

commit;
