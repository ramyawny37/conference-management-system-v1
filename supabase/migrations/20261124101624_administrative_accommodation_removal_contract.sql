begin;

-- An explicit room-editor removal is an administrative correction while the
-- conference is mutable. Participation apology/deletion remain effective-day
-- lifecycle operations so consumed stay history keeps its existing contract.
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
    if p_cause='accommodation_removed' then
      delete from public.conference_accommodation_occupancies where id=item.id;
    elsif item.arrival_day>=effective_day then
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
      'effectiveDay',effective_day,'cause',p_cause,'administrativeCorrection',p_cause='accommodation_removed',
      'permissionKey',case when p_cause='accommodation_removed' then 'conference.accommodation.manage' else 'conference.people.manage' end,
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
  end loop;
  if exists(select 1 from public.conference_accommodation_occupancies where id=current.id) then
    raise exception 'ACCOMMODATION_REMOVAL_NOT_APPLIED' using errcode='55000';
  end if;
  return jsonb_build_object('occupancyId',current.id,'deleted',true,
    'familyParticipationIds',to_jsonb(family_ids),'changedParticipationIds',changed_ids,
    'removedTransportAssignmentIds','[]'::jsonb);
end $function$;

revoke all on function platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint)
  from public,anon,authenticated,service_role;
grant execute on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint)
  to service_role;

do $contract$
declare cleanup_definition text; removal_definition text;
begin
  cleanup_definition:=pg_get_functiondef(
    'platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid)'::regprocedure);
  removal_definition:=pg_get_functiondef(
    'public.remove_conference_accommodation(uuid,uuid,uuid,bigint)'::regprocedure);
  if position('if p_cause=''accommodation_removed'' then' in cleanup_definition)=0
     or position('administrativeCorrection' in cleanup_definition)=0 then
    raise exception 'ADMINISTRATIVE_ACCOMMODATION_REMOVAL_CONTRACT_MISSING' using errcode='55000';
  end if;
  if position('ACCOMMODATION_REMOVAL_NOT_APPLIED' in removal_definition)=0
     or position('cleanup_conference_transport_for_participation' in removal_definition)>0 then
    raise exception 'TRUTHFUL_ACCOMMODATION_REMOVAL_CONTRACT_MISSING' using errcode='55000';
  end if;
end $contract$;

commit;
