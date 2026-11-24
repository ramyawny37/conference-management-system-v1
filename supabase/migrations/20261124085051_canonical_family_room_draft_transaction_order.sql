begin;

-- The family draft is the single room-editor write boundary. Validate every
-- stay first, then free occupied beds before structure changes and additions.
do $family_draft_order$
declare
  definition text;
  old_structure text;
  ordered_loop text;
  structure_before_mutation text;
  structure_after_mutations text;
begin
  if to_regprocedure('public.save_conference_family_accommodation_draft(uuid,uuid,uuid,jsonb)') is null then
    return;
  end if;
  definition:=pg_get_functiondef(
    'public.save_conference_family_accommodation_draft(uuid,uuid,uuid,jsonb)'::regprocedure);

  if position('structure_applied boolean:=false' in definition)>0 then return; end if;

  definition:=replace(
    definition,
    'draft_room public.conference_accommodation_rooms%rowtype;draft_assignment public.conference_room_assignments%rowtype;',
    'draft_room public.conference_accommodation_rooms%rowtype;draft_assignment public.conference_room_assignments%rowtype;structure_applied boolean:=false;');

  old_structure:='if room_draft is not null and jsonb_typeof(room_draft)<>''null'' and room_draft->''structure'' is not null and jsonb_typeof(room_draft->''structure'')<>''null'' then
   perform public.save_conference_accommodation_room_draft(p_device,gen_random_uuid(),p_conference,(room_draft->>''roomId'')::uuid,(room_draft->>''expectedRevision'')::bigint,(room_draft->>''expectedAssignmentRevision'')::bigint,room_draft->''structure'',''[]''::jsonb,''[]''::jsonb,''[]''::jsonb);
 end if;';
  if position(old_structure in definition)=0 then
    raise exception 'FAMILY_DRAFT_STRUCTURE_BLOCK_CHANGED' using errcode='55000';
  end if;
  definition:=replace(definition,old_structure,'');

  ordered_loop:='for stay in select value from jsonb_array_elements(p_payload->''stays'') order by case value->>''operation'' when ''remove'' then 1 when ''move'' then 2 when ''replace'' then 3 when ''assign'' then 4 else 5 end loop';
  if position('for stay in select value from jsonb_array_elements(p_payload->''stays'') loop' in definition)=0 then
    raise exception 'FAMILY_DRAFT_STAY_LOOP_CHANGED' using errcode='55000';
  end if;
  definition:=replace(
    definition,
    'for stay in select value from jsonb_array_elements(p_payload->''stays'') loop',
    ordered_loop);

  -- Client revisions were checked under locks before stay mutations.
  -- Re-read revisions after removal because key cleanup may increment them.
  structure_before_mutation:='if not structure_applied and stay->>''operation''<>''remove'' and not(
     stay->>''operation''=''move''
     and room_draft is not null and jsonb_typeof(room_draft)<>''null''
     and room_draft->''structure'' is not null and jsonb_typeof(room_draft->''structure'')<>''null''
     and coalesce((room_draft->''structure''->>''baseCapacity'')::integer,draft_room.base_capacity)<=draft_room.base_capacity
     and coalesce((room_draft->''structure''->>''extraBedCapacity'')::integer,draft_assignment.extra_bed_capacity)<=draft_assignment.extra_bed_capacity
   ) then
     if room_draft is not null and jsonb_typeof(room_draft)<>''null'' and room_draft->''structure'' is not null and jsonb_typeof(room_draft->''structure'')<>''null'' then
       perform public.save_conference_accommodation_room_draft(p_device,gen_random_uuid(),p_conference,(room_draft->>''roomId'')::uuid,(select revision from public.conference_accommodation_rooms where id=(room_draft->>''roomId'')::uuid),(select revision from public.conference_room_assignments where conference_id=p_conference and room_id=(room_draft->>''roomId'')::uuid),room_draft->''structure'',''[]''::jsonb,''[]''::jsonb,''[]''::jsonb);
     end if;
     structure_applied:=true;
   end if;
   case stay->>''operation''';
  if position('case stay->>''operation''' in definition)=0 then
    raise exception 'FAMILY_DRAFT_MUTATION_CASE_CHANGED' using errcode='55000';
  end if;
  definition:=replace(definition,'case stay->>''operation''',structure_before_mutation);

  structure_after_mutations:='end loop;
 if not structure_applied then
   if room_draft is not null and jsonb_typeof(room_draft)<>''null'' and room_draft->''structure'' is not null and jsonb_typeof(room_draft->''structure'')<>''null'' then
     perform public.save_conference_accommodation_room_draft(p_device,gen_random_uuid(),p_conference,(room_draft->>''roomId'')::uuid,(select revision from public.conference_accommodation_rooms where id=(room_draft->>''roomId'')::uuid),(select revision from public.conference_room_assignments where conference_id=p_conference and room_id=(room_draft->>''roomId'')::uuid),room_draft->''structure'',''[]''::jsonb,''[]''::jsonb,''[]''::jsonb);
   end if;
   structure_applied:=true;
 end if;
 for child_draft in select value from jsonb_array_elements(resolved_children) loop';
  if position('end loop;
 for child_draft in select value from jsonb_array_elements(resolved_children) loop' in definition)=0 then
    raise exception 'FAMILY_DRAFT_CHILD_LOOP_CHANGED' using errcode='55000';
  end if;
  definition:=replace(
    definition,
    'end loop;
 for child_draft in select value from jsonb_array_elements(resolved_children) loop',
    structure_after_mutations);
  execute definition;
end $family_draft_order$;

-- Removing accommodation changes accommodation only. Transport remains owned
-- by participation lifecycle operations (apology/deletion), not by room edits.
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
  return jsonb_build_object('occupancyId',current.id,'deleted',true,
    'familyParticipationIds',to_jsonb(family_ids),'changedParticipationIds',changed_ids,
    'removedTransportAssignmentIds','[]'::jsonb);
end $function$;

revoke all on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint)
  from public,anon,authenticated,service_role;
grant execute on function public.remove_conference_accommodation(uuid,uuid,uuid,bigint)
  to service_role;

do $contract$
declare definition text;
begin
  if to_regprocedure('public.save_conference_family_accommodation_draft(uuid,uuid,uuid,jsonb)') is not null then
    definition:=pg_get_functiondef(
      'public.save_conference_family_accommodation_draft(uuid,uuid,uuid,jsonb)'::regprocedure);
    if position('when ''remove'' then 1' in definition)=0
       or position('structure_applied boolean:=false' in definition)=0 then
      raise exception 'FAMILY_DRAFT_ORDER_CONTRACT_MISSING' using errcode='55000';
    end if;
  end if;
  definition:=pg_get_functiondef(
    'public.remove_conference_accommodation(uuid,uuid,uuid,bigint)'::regprocedure);
  if position('cleanup_conference_transport_for_participation' in definition)>0 then
    raise exception 'ACCOMMODATION_REMOVAL_TRANSPORT_COUPLING_REMAINS' using errcode='55000';
  end if;
end $contract$;

commit;
