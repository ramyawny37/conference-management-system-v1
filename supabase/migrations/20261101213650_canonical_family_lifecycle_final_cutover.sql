begin;

-- Family ownership belongs to the event participation, while the affected stay
-- (room and half-open period) decides which children accompany a guardian move.
do $move_contract$
declare definition text;
begin
  definition:=pg_get_functiondef(
    'public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text)'::regprocedure);
  if position('cp.guardian_participation_id=participation.id and o.bed_type=''shared''' in definition)=0 then
    raise exception 'FAMILY_MOVE_FINAL_CUTOVER_SHAPE_CHANGED' using errcode='55000';
  end if;
  definition:=replace(
    definition,
    'cp.guardian_participation_id=participation.id and o.bed_type=''shared''',
    'cp.guardian_participation_id=participation.id');
  execute definition;
end $move_contract$;

create or replace function platform_private.cleanup_conference_accommodation_for_participation(
  p_participation_id uuid,p_actor_user_id uuid,p_device_authorization_id uuid,
  p_authority_context jsonb,p_cause text,p_operation_id uuid
) returns uuid language plpgsql security definer set search_path='' as $function$
declare
  item public.conference_accommodation_occupancies%rowtype;
  first_changed uuid; effective_day integer; conference_start date; conference_days integer;
begin
  if p_cause not in('accommodation_removed','participation_apologized','participation_deleted') then
    raise exception 'PARTICIPATION_ACCOMMODATION_CLEANUP_CAUSE_INVALID' using errcode='22023';
  end if;
  select c.start_date,(c.end_date-c.start_date+1)::integer into conference_start,conference_days
  from public.conference_participations p join public.conferences c on c.id=p.conference_id
  where p.id=p_participation_id;
  if conference_start is null then return null; end if;
  effective_day:=greatest(1,least(conference_days+1,(current_date-conference_start+1)::integer));
  for item in
    select * from public.conference_accommodation_occupancies
    where participation_id=p_participation_id order by room_id,arrival_day,id for update
  loop
    if item.arrival_day>=effective_day then
      delete from public.conference_accommodation_occupancies where id=item.id;
    elsif coalesce(item.leave_day,conference_days+1)>effective_day then
      update public.conference_accommodation_occupancies
      set leave_day=effective_day,revision=revision+1,updated_at=statement_timestamp(),updated_by=p_actor_user_id
      where id=item.id;
    else
      continue;
    end if;
    first_changed:=coalesce(first_changed,item.id);
    insert into platform.audit_events(
      actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,
      scope_type,old_values,new_values,metadata,operation_id,source)
    values(p_actor_user_id,p_device_authorization_id,'platform','conference',
      'conference.accommodation.participation_cleanup','accommodation_occupancy',item.id,'platform',
      to_jsonb(item),null,jsonb_build_object('conferenceId',item.conference_id,
      'participationId',p_participation_id,'occupancyId',item.id,'previousRoomId',item.room_id,
      'effectiveDay',effective_day,'cause',p_cause,'permissionKey',
      case when p_cause='accommodation_removed' then 'conference.accommodation.manage' else 'conference.people.manage' end,
      'authoritySource',p_authority_context->>'authoritySource','grantId',p_authority_context->'grantId'),
      p_operation_id,'rpc');
  end loop;
  return first_changed;
end $function$;

create or replace function public.remove_conference_accommodation(
  p_device uuid,p_conference uuid,p_occupancy uuid,p_expected bigint
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  context jsonb; actor uuid; v_authorization uuid;
  current public.conference_accommodation_occupancies%rowtype;
  member record; family_ids uuid[]; changed_ids jsonb:='[]'::jsonb;
  removed_transport_ids jsonb:='[]'::jsonb;
begin
  context:=platform_private.require_conference_accommodation_context(
    p_device,p_conference,'conference.accommodation.manage',true);
  actor:=(context->>'actorUserId')::uuid;
  v_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_device);
  select * into current from public.conference_accommodation_occupancies
  where id=p_occupancy and conference_id=p_conference for update;
  if not found then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='P0002'; end if;
  if current.revision<>p_expected then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001'; end if;

  if exists(select 1 from public.conference_participations where id=current.participation_id and guardian_participation_id is null) then
    select array_agg(id order by id) into family_ids from public.conference_participations
    where conference_id=p_conference
      and (id=current.participation_id or guardian_participation_id=current.participation_id);
  else
    family_ids:=array[current.participation_id];
  end if;
  perform 1 from public.conference_participations where id=any(family_ids) order by id for update;
  perform 1 from public.conference_accommodation_rooms where id in(
    select distinct room_id from public.conference_accommodation_occupancies where participation_id=any(family_ids)
  ) order by id for update;
  for member in select unnest(family_ids) participation_id loop
    if platform_private.cleanup_conference_accommodation_for_participation(
      member.participation_id,actor,v_authorization,context,'accommodation_removed',null) is not null then
      changed_ids:=changed_ids||jsonb_build_array(member.participation_id);
    end if;
    removed_transport_ids:=removed_transport_ids||platform_private.cleanup_conference_transport_for_participation(
      member.participation_id,actor,v_authorization,'accommodation_removed',null,'conference.accommodation.manage');
  end loop;
  return jsonb_build_object('occupancyId',current.id,'deleted',true,'familyParticipationIds',to_jsonb(family_ids),
    'changedParticipationIds',changed_ids,'removedTransportAssignmentIds',removed_transport_ids);
end $function$;

create or replace function public.set_conference_participation_status(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,
  p_expected_revision bigint,p_status text
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  current public.conference_participations%rowtype; member public.conference_participations%rowtype;
  context jsonb; actor uuid; v_authorization uuid; request jsonb; prior public.conference_participation_operations%rowtype;
  family_ids uuid[]; changed_ids jsonb:='[]'::jsonb; removed_transport_ids jsonb:='[]'::jsonb; result jsonb;
begin
  if p_operation_id is null or p_expected_revision<1 or p_status not in('active','apologized') then
    raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  select * into current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  context:=platform_private.require_conference_participation_context(
    p_actor_device_id,current.conference_id,'conference.people.manage',true);
  actor:=(context->>'actorUserId')::uuid;
  v_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);
  request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision,'status',p_status);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then
    if prior.operation<>'set_status' or prior.request<>request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if;
    return prior.result;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||current.conference_id::text,0));
  perform 1 from public.conference_participations where id=p_participation_id or guardian_participation_id=p_participation_id order by id for update;
  select * into current from public.conference_participations where id=p_participation_id;
  if current.revision<>p_expected_revision then raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001'; end if;
  if p_status='active' and current.guardian_participation_id is not null and exists(
    select 1 from public.conference_participations guardian
    where guardian.id=current.guardian_participation_id and guardian.status<>'active') then
    raise exception 'ACTIVE_CHILD_GUARDIAN_REQUIRED' using errcode='23514';
  end if;
  if p_status='apologized' and current.guardian_participation_id is null then
    select array_agg(id order by id) into family_ids from public.conference_participations
    where conference_id=current.conference_id and (id=current.id or guardian_participation_id=current.id);
  else family_ids:=array[current.id]; end if;
  for member in select * from public.conference_participations where id=any(family_ids) order by id loop
    if p_status='apologized' and member.status='active' then
      perform platform_private.cleanup_conference_accommodation_for_participation(
        member.id,actor,v_authorization,context,'participation_apologized',p_operation_id);
      removed_transport_ids:=removed_transport_ids||platform_private.cleanup_conference_transport_for_participation(
        member.id,actor,v_authorization,'participation_apologized',p_operation_id,'conference.people.manage');
    end if;
    update public.conference_participations set status=p_status,revision=revision+1,
      updated_at=statement_timestamp(),updated_by=actor where id=member.id;
    changed_ids:=changed_ids||jsonb_build_array(member.id);
  end loop;
  result:=jsonb_build_object('participationId',current.id,'conferenceId',current.conference_id,'status',p_status,
    'revision',current.revision+1,'changedParticipationIds',changed_ids,
    'removedTransportAssignmentIds',removed_transport_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
  values(actor,p_operation_id,'set_status',request,result,statement_timestamp());
  return result;
end $function$;

create or replace function public.delete_conference_participation(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  current public.conference_participations%rowtype; member public.conference_participations%rowtype;
  context jsonb; session_context jsonb; actor uuid; v_authorization uuid; request jsonb;
  prior public.conference_participation_operations%rowtype; family_ids uuid[];
  removed_transport_ids jsonb:='[]'::jsonb; result jsonb;
begin
  if p_operation_id is null or p_expected_revision<1 then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  begin
    session_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    if session_context is null or session_context->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH'
       or (session_context->>'device_id')::uuid is distinct from p_actor_device_id then
      raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
    actor:=(session_context->>'user_id')::uuid;
  exception when invalid_text_representation or null_value_not_allowed then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end;
  v_authorization:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);
  if v_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into prior from public.conference_participation_operations where actor_user_id=actor and operation_id=p_operation_id;
  if found then
    if prior.operation<>'delete' or prior.request<>request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if;
    return prior.result;
  end if;
  select * into current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  context:=platform_private.require_conference_participation_context(
    p_actor_device_id,current.conference_id,'conference.people.manage',true);
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||current.conference_id::text,0));
  perform 1 from public.conference_participations where id=current.id or guardian_participation_id=current.id order by id for update;
  select * into current from public.conference_participations where id=p_participation_id;
  if current.revision<>p_expected_revision then raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001'; end if;
  if current.guardian_participation_id is null then
    select array_agg(id order by id) into family_ids from public.conference_participations
    where conference_id=current.conference_id and (id=current.id or guardian_participation_id=current.id);
  else family_ids:=array[current.id]; end if;
  for member in select * from public.conference_participations where id=any(family_ids) order by id loop
    perform platform_private.cleanup_conference_accommodation_for_participation(
      member.id,actor,v_authorization,context,'participation_deleted',p_operation_id);
    removed_transport_ids:=removed_transport_ids||platform_private.cleanup_conference_transport_for_participation(
      member.id,actor,v_authorization,'participation_deleted',p_operation_id,'conference.people.manage');
    delete from public.conference_restaurant_participation_overrides where participation_id=member.id;
  end loop;
  delete from public.conference_participations where id=any(family_ids) and id<>current.id;
  delete from public.conference_participations where id=current.id;
  result:=jsonb_build_object('participationId',current.id,'conferenceId',current.conference_id,
    'personId',current.person_id,'deleted',true,'deletedParticipationIds',to_jsonb(family_ids),
    'removedTransportAssignmentIds',removed_transport_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
  values(actor,p_operation_id,'delete',request,result,statement_timestamp());
  return result;
end $function$;

revoke all on function platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;
revoke all on function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) from public,anon,authenticated,service_role;
revoke all on function public.delete_conference_participation(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint) to service_role;
grant execute on function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) to service_role;
grant execute on function public.delete_conference_participation(uuid,uuid,uuid,bigint) to service_role;

do $contract$
declare definition text;
begin
  definition:=pg_get_functiondef('public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text)'::regprocedure);
  if position('cp.guardian_participation_id=participation.id and o.bed_type=''shared''' in definition)>0 then
    raise exception 'FAMILY_MOVE_SHARED_ONLY_FILTER_REMAINS' using errcode='55000'; end if;
  definition:=pg_get_functiondef('public.delete_conference_participation(uuid,uuid,uuid,bigint)'::regprocedure);
  if position('guardian_participation_id=null' in definition)>0 then
    raise exception 'FAMILY_DELETE_UNLINK_PATH_REMAINS' using errcode='55000'; end if;
end $contract$;

commit;
;
