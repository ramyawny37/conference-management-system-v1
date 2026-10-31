begin;

create or replace function platform_private.cleanup_conference_transport_for_participation(
  p_participation_id uuid,
  p_actor_user_id uuid,
  p_device_authorization_id uuid,
  p_cause text,
  p_operation_id uuid,
  p_permission_key text
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_assignment public.conference_transport_assignments%rowtype;
  v_removed_ids jsonb:='[]'::jsonb;
begin
  if p_cause not in('accommodation_removed','participation_apologized','participation_deleted','guardian_participation_deleted') then
    raise exception 'CONFERENCE_TRANSPORT_CLEANUP_CAUSE_INVALID' using errcode='22023';
  end if;
  for v_assignment in
    select assignment.* from public.conference_transport_assignments assignment
    where assignment.participation_id=p_participation_id
    order by assignment.id for update
  loop
    perform platform_private.audit_conference_transport_assignment_removal(
      p_actor_user_id,p_device_authorization_id,v_assignment,p_operation_id,p_cause,p_permission_key);
    v_removed_ids:=v_removed_ids||jsonb_build_array(v_assignment.id);
  end loop;
  delete from public.conference_transport_assignments where participation_id=p_participation_id;
  return v_removed_ids;
end $function$;

revoke all on function platform_private.cleanup_conference_transport_for_participation(uuid,uuid,uuid,text,uuid,text) from public,anon,authenticated,service_role;

create or replace function public.remove_conference_accommodation(
 p_device uuid,p_conference uuid,p_occupancy uuid,p_expected bigint
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
 context jsonb; actor uuid; device_authorization uuid;
 current public.conference_accommodation_occupancies%rowtype;
 conference_start date; conference_days integer; effective_day integer;
 removed boolean; result jsonb; removed_transport_ids jsonb;
begin
 context:=platform_private.require_conference_accommodation_context(
   p_device,p_conference,'conference.accommodation.manage',true);
 actor:=(context->>'actorUserId')::uuid;
 device_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device);
 select c.start_date,(c.end_date-c.start_date+1)::integer
   into conference_start,conference_days
   from public.conferences c where c.id=p_conference and c.deleted_at is null;
 if conference_start is null or conference_days is null then
   raise exception 'CONFERENCE_CORE_NOT_FOUND' using errcode='P0002';
 end if;
 effective_day:=greatest(1,least(conference_days+1,(current_date-conference_start+1)::integer));
 select * into current from public.conference_accommodation_occupancies
   where id=p_occupancy and conference_id=p_conference for update;
 if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002';end if;
 if current.revision<>p_expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;
 if exists(
   select 1 from public.conference_participations child_participation
   join public.conference_accommodation_occupancies child_stay on child_stay.participation_id=child_participation.id
   where child_participation.guardian_participation_id=current.participation_id
     and child_stay.conference_id=p_conference and child_stay.bed_type='shared'
     and child_stay.room_id=current.room_id and child_stay.arrival_day=current.arrival_day
     and child_stay.leave_day is not distinct from current.leave_day
 ) then
   raise exception 'ACCOMMODATION_SHARED_CHILD_RESOLUTION_REQUIRED' using errcode='23514';
 end if;
 if current.arrival_day>=effective_day then
   delete from public.conference_accommodation_occupancies where id=current.id;
   removed:=true;
 elsif coalesce(current.leave_day,conference_days+1)>effective_day then
   update public.conference_accommodation_occupancies
      set leave_day=effective_day,revision=revision+1,
          updated_at=statement_timestamp(),updated_by=actor
    where id=current.id;
   removed:=false;
 else
   raise exception 'ACCOMMODATION_HISTORICAL_STAY_IMMUTABLE' using errcode='55000';
 end if;
 removed_transport_ids:=platform_private.cleanup_conference_transport_for_participation(
   current.participation_id,actor,device_authorization,'accommodation_removed',null,'conference.accommodation.manage');
 result:=jsonb_build_object('occupancyId',current.id,'deleted',removed,
   'historicalSegmentPreserved',not removed,'effectiveDay',effective_day,
   'removedTransportAssignmentIds',removed_transport_ids);
 insert into platform.audit_events(
   actor_user_id,actor_device_authorization_id,domain,module,action,
   entity_type,entity_id,scope_type,old_values,new_values,metadata,source)
 values(actor,device_authorization,'platform','conference','conference.accommodation.removed',
   'accommodation_occupancy',current.id,'platform',to_jsonb(current),result,
   jsonb_build_object('conferenceId',p_conference,'participationId',current.participation_id,
     'effectiveDay',effective_day,'historicalSegmentPreserved',not removed,
     'permissionKey','conference.accommodation.manage',
     'authoritySource',context->>'authoritySource','grantId',context->'grantId'),'rpc');
 return result;
end $function$;

revoke all on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint) to service_role;

create or replace function public.set_conference_participation_status(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,
  p_expected_revision bigint,p_status text
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_current public.conference_participations%rowtype;
  v_updated public.conference_participations%rowtype;
  v_child public.conference_participations%rowtype;
  v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb;
  v_prior public.conference_participation_operations%rowtype; v_result jsonb;
  v_removed_transport_ids jsonb:='[]'::jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null
     or p_expected_revision<1 or p_status not in('active','apologized') then
    raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision,'status',p_status);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'set_status' or v_prior.request<>v_request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;
    return v_prior.result;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||v_current.conference_id::text,0));
  perform 1 from public.conference_participations where id=p_participation_id or guardian_participation_id=p_participation_id order by id for update;
  select * into v_current from public.conference_participations where id=p_participation_id for update;
  if v_current.revision<>p_expected_revision then raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';end if;
  if v_current.status='active' and p_status='apologized' then
    perform platform_private.cleanup_conference_accommodation_for_participation(p_participation_id,v_actor,v_device_authorization,v_context,'participation_apologized',p_operation_id);
    v_removed_transport_ids:=v_removed_transport_ids||platform_private.cleanup_conference_transport_for_participation(p_participation_id,v_actor,v_device_authorization,'participation_apologized',p_operation_id,'conference.people.manage');
    for v_child in select child.* from public.conference_participations child where child.guardian_participation_id=p_participation_id order by child.id loop
      if not exists(select 1 from public.conference_accommodation_occupancies stay where stay.participation_id=v_child.id) then
        v_removed_transport_ids:=v_removed_transport_ids||platform_private.cleanup_conference_transport_for_participation(v_child.id,v_actor,v_device_authorization,'participation_apologized',p_operation_id,'conference.people.manage');
      end if;
    end loop;
  end if;
  update public.conference_participations set status=p_status,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor
  where id=p_participation_id returning * into v_updated;
  v_result:=jsonb_build_object('participationId',v_updated.id,'conferenceId',v_updated.conference_id,'personId',v_updated.person_id,
    'status',v_updated.status,'revision',v_updated.revision,'updatedAt',v_updated.updated_at,'updatedBy',v_updated.updated_by,
    'removedTransportAssignmentIds',v_removed_transport_ids);
  insert into public.conference_participation_operations values(v_actor,p_operation_id,'set_status',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(v_actor,v_device_authorization,'platform','conference','conference.participation.status_changed','conference_participation',v_updated.id,'platform',
    jsonb_build_object('status',v_current.status,'revision',v_current.revision),jsonb_build_object('status',v_updated.status,'revision',v_updated.revision),
    jsonb_build_object('conferenceId',v_updated.conference_id,'personId',v_updated.person_id,'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $function$;

revoke all on function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) to service_role;

create or replace function public.delete_conference_participation(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_current public.conference_participations%rowtype; v_child public.conference_participations%rowtype;
  v_context jsonb; v_session_context jsonb; v_actor uuid; v_authorization uuid;
  v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_result jsonb;
  v_restaurant public.conference_restaurant_participation_overrides%rowtype;
  v_unlinked_child_ids jsonb:='[]'::jsonb; v_removed_transport_ids jsonb:='[]'::jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null or p_expected_revision<1 then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023';end if;
  begin
    v_session_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    if v_session_context is null or v_session_context->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (v_session_context->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
    v_actor:=(v_session_context->>'user_id')::uuid;
  exception when invalid_text_representation or null_value_not_allowed then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end;
  v_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  if v_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'delete' or v_prior.request<>v_request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';end if;
    v_context:=platform_private.require_conference_participation_context(p_actor_device_id,(v_prior.result->>'conferenceId')::uuid,'conference.people.manage',false);
    return v_prior.result;
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002';end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||v_current.conference_id::text,0));
  perform 1 from public.conference_participations where id=p_participation_id or guardian_participation_id=p_participation_id order by id for update;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if v_current.revision<>p_expected_revision then raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';end if;
  for v_restaurant in select item.* from public.conference_restaurant_participation_overrides item where item.participation_id=p_participation_id order by item.id for update loop
    insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
    values(v_actor,v_authorization,'platform','conference','conference.restaurant.participation_override_removed','conference_restaurant_participation_override',v_restaurant.id,'platform',to_jsonb(v_restaurant),null,jsonb_build_object('conferenceId',v_restaurant.conference_id,'reason','participation_deleted','permissionKey','conference.people.manage'),p_operation_id,'rpc');
  end loop;
  delete from public.conference_restaurant_participation_overrides where participation_id=p_participation_id;
  perform platform_private.cleanup_conference_accommodation_for_participation(p_participation_id,v_actor,v_authorization,v_context,'participation_deleted',p_operation_id);
  v_removed_transport_ids:=platform_private.cleanup_conference_transport_for_participation(p_participation_id,v_actor,v_authorization,'participation_deleted',p_operation_id,'conference.people.manage');
  for v_child in select child.* from public.conference_participations child where child.guardian_participation_id=p_participation_id order by child.id loop
    if not exists(select 1 from public.conference_accommodation_occupancies stay where stay.participation_id=v_child.id) then
      v_removed_transport_ids:=v_removed_transport_ids||platform_private.cleanup_conference_transport_for_participation(v_child.id,v_actor,v_authorization,'guardian_participation_deleted',p_operation_id,'conference.people.manage');
    end if;
    update public.conference_participations set guardian_participation_id=null,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_child.id;
    v_unlinked_child_ids:=v_unlinked_child_ids||jsonb_build_array(v_child.id);
    insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
    values(v_actor,v_authorization,'platform','conference','conference.participation.guardian_changed','conference_participation',v_child.id,'platform',jsonb_build_object('guardianParticipationId',p_participation_id,'revision',v_child.revision),jsonb_build_object('guardianParticipationId',null,'revision',v_child.revision+1),jsonb_build_object('conferenceId',v_child.conference_id,'reason','guardian_participation_deleted','permissionKey','conference.people.manage'),p_operation_id,'rpc');
  end loop;
  delete from public.conference_participations where id=p_participation_id;
  v_result:=jsonb_build_object('participationId',p_participation_id,'conferenceId',v_current.conference_id,'personId',v_current.person_id,'deleted',true,
    'deletedParticipationIds',jsonb_build_array(p_participation_id),'unlinkedChildParticipationIds',v_unlinked_child_ids,'removedTransportAssignmentIds',v_removed_transport_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at) values(v_actor,p_operation_id,'delete',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(v_actor,v_authorization,'platform','conference','conference.participation.deleted','conference_participation',v_current.id,'platform',jsonb_build_object('conferenceId',v_current.conference_id,'personId',v_current.person_id,'status',v_current.status,'revision',v_current.revision,'guardianParticipationId',v_current.guardian_participation_id),null,jsonb_build_object('requestedParticipationId',p_participation_id,'cascade',false,'permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $function$;

revoke all on function public.delete_conference_participation(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function public.delete_conference_participation(uuid,uuid,uuid,bigint) to service_role;

do $contract$
begin
  if to_regprocedure('platform_private.cleanup_conference_transport_for_participation(uuid,uuid,uuid,text,uuid,text)') is null
     or to_regprocedure('public.remove_conference_accommodation(uuid,uuid,uuid,bigint)') is null
     or to_regprocedure('public.set_conference_participation_status(uuid,uuid,uuid,bigint,text)') is null
     or to_regprocedure('public.delete_conference_participation(uuid,uuid,uuid,bigint)') is null then
    raise exception 'CONFERENCE_OPERATIONAL_LIFECYCLE_CONTRACT_INCOMPLETE' using errcode='55000';
  end if;
end $contract$;

commit;
