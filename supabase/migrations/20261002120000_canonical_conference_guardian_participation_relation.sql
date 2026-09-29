begin;

do $$ begin
  if to_regclass('public.conference_participations') is null
     or to_regclass('public.conference_participation_operations') is null
     or to_regprocedure('platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid)') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null then
    raise exception 'P6E_B1_CANONICAL_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end $$;

alter table public.conference_participations
  add column guardian_participation_id uuid null,
  add constraint conference_participations_conference_id_id_key unique(conference_id,id),
  add constraint conference_participations_guardian_not_self check(guardian_participation_id is null or guardian_participation_id<>id),
  add constraint conference_participations_guardian_same_conference_fk
    foreign key(conference_id,guardian_participation_id)
    references public.conference_participations(conference_id,id) on delete restrict;

create index conference_participations_guardian_idx
  on public.conference_participations(conference_id,guardian_participation_id)
  where guardian_participation_id is not null;

create function platform_private.enforce_conference_participation_guardian_one_level()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_guardian public.conference_participations%rowtype;
begin
  if tg_op='UPDATE' and new.guardian_participation_id is not distinct from old.guardian_participation_id then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||new.conference_id::text,0));
  if new.guardian_participation_id is null then return new; end if;
  if new.guardian_participation_id=new.id then
    raise exception 'CONFERENCE_GUARDIAN_SELF_REFERENCE' using errcode='23514';
  end if;
  select * into v_guardian from public.conference_participations
  where id=new.guardian_participation_id and conference_id=new.conference_id for update;
  if not found then raise exception 'CONFERENCE_GUARDIAN_SAME_CONFERENCE_REQUIRED' using errcode='23503'; end if;
  if v_guardian.guardian_participation_id is not null then
    raise exception 'CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED' using errcode='23514';
  end if;
  perform 1 from public.conference_participations
  where conference_id=new.conference_id and guardian_participation_id=new.id for update;
  if found then raise exception 'CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED' using errcode='23514'; end if;
  return new;
end $$;

create trigger conference_participation_guardian_one_level
before insert or update of guardian_participation_id on public.conference_participations
for each row execute function platform_private.enforce_conference_participation_guardian_one_level();

alter table public.conference_participation_operations
  drop constraint conference_participation_operations_operation_check;
alter table public.conference_participation_operations
  add constraint conference_participation_operations_operation_check
  check(operation in('create','create_with_person','set_status','set_guardian','delete'));

create or replace function public.list_conference_participations(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_items jsonb; v_total bigint; v_active bigint; v_apologized bigint;
begin
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.view',false);
  select count(*),count(*) filter(where participation.status='active'),count(*) filter(where participation.status='apologized'),
    coalesce(jsonb_agg(jsonb_build_object('participationId',participation.id,'conferenceId',participation.conference_id,
      'personId',participation.person_id,'status',participation.status,'revision',participation.revision,
      'guardianParticipationId',guardian.id,'guardianPersonId',guardian_person.id,
      'guardianFullName',guardian_person.full_name,'guardianParticipationStatus',guardian.status,
      'createdAt',participation.created_at,'updatedAt',participation.updated_at,'createdBy',participation.created_by,
      'updatedBy',participation.updated_by,'person',jsonb_build_object('personId',person.id,
        'fullName',person.full_name,'phone',person.phone,'gender',person.gender,
        'dateOfBirth',person.date_of_birth,'church',person.church))
      order by participation.created_at,participation.id),'[]'::jsonb)
  into v_total,v_active,v_apologized,v_items
  from public.conference_participations participation
  join platform.people person on person.id=participation.person_id
  left join public.conference_participations guardian on guardian.id=participation.guardian_participation_id
  left join platform.people guardian_person on guardian_person.id=guardian.person_id
  where participation.conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'totalCount',v_total,'activeCount',v_active,
    'apologizedCount',v_apologized,'items',v_items);
end $$;

create function public.set_conference_participation_guardian(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,
  p_expected_revision bigint,p_guardian_participation_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_child public.conference_participations%rowtype; v_updated public.conference_participations%rowtype;
  v_guardian public.conference_participations%rowtype; v_context jsonb; v_actor uuid; v_device_authorization uuid;
  v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_result jsonb;
  v_guardian_person platform.people%rowtype;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null or p_expected_revision<1 then
    raise exception 'CONFERENCE_GUARDIAN_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select * into v_child from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_child.conference_id,'conference.people.manage',true);
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  if v_device_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision,
    'guardianParticipationId',p_guardian_participation_id);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations
  where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'set_guardian' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    return v_prior.result;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||v_child.conference_id::text,0));
  perform 1 from public.conference_participations
  where id in(p_participation_id,p_guardian_participation_id) order by id for update;
  select * into v_child from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_child.conference_id,'conference.people.manage',true);
  if (v_context->>'actorUserId')::uuid is distinct from v_actor then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  if v_child.revision<>p_expected_revision then
    raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  if p_guardian_participation_id is not null then
    if p_guardian_participation_id=p_participation_id then
      raise exception 'CONFERENCE_GUARDIAN_SELF_REFERENCE' using errcode='23514';
    end if;
    select * into v_guardian from public.conference_participations where id=p_guardian_participation_id;
    if not found or v_guardian.conference_id<>v_child.conference_id then
      raise exception 'CONFERENCE_GUARDIAN_SAME_CONFERENCE_REQUIRED' using errcode='23503';
    end if;
    if v_guardian.guardian_participation_id is not null
       or exists(select 1 from public.conference_participations
         where conference_id=v_child.conference_id and guardian_participation_id=v_child.id) then
      raise exception 'CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED' using errcode='23514';
    end if;
  end if;
  update public.conference_participations
  set guardian_participation_id=p_guardian_participation_id,revision=revision+1,
      updated_at=statement_timestamp(),updated_by=v_actor
  where id=p_participation_id returning * into v_updated;
  if v_updated.guardian_participation_id is not null then
    select * into v_guardian from public.conference_participations
    where id=v_updated.guardian_participation_id;
    select * into v_guardian_person from platform.people where id=v_guardian.person_id;
  end if;
  v_result:=jsonb_build_object('participationId',v_updated.id,'conferenceId',v_updated.conference_id,
    'personId',v_updated.person_id,'status',v_updated.status,'revision',v_updated.revision,
    'guardianParticipationId',v_guardian.id,'guardianPersonId',v_guardian_person.id,
    'guardianFullName',v_guardian_person.full_name,'guardianParticipationStatus',v_guardian.status,
    'updatedAt',v_updated.updated_at,'updatedBy',v_updated.updated_by);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
  values(v_actor,p_operation_id,'set_guardian',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
    entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
  values(v_actor,v_device_authorization,'platform','conference','conference.participation.guardian_changed',
    'conference_participation',v_updated.id,'platform',
    jsonb_build_object('guardianParticipationId',v_child.guardian_participation_id,'revision',v_child.revision),
    jsonb_build_object('guardianParticipationId',v_updated.guardian_participation_id,'revision',v_updated.revision),
    jsonb_build_object('conferenceId',v_updated.conference_id,'permissionKey','conference.people.manage',
      'authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $$;

create or replace function public.get_conference_accommodation(p_device uuid,p_conference uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare context jsonb; result jsonb;
begin
  context:=platform_private.require_conference_accommodation_context(p_device,p_conference,'conference.accommodation.view',false);
  select coalesce(jsonb_agg(jsonb_build_object('houseId',h.id,'name',h.name,'description',h.description,'position',h.position,'revision',h.revision,'floors',
    (select coalesce(jsonb_agg(jsonb_build_object('floorId',f.id,'name',f.name,'position',f.position,'revision',f.revision,'rooms',
      (select coalesce(jsonb_agg(jsonb_build_object('roomId',r.id,'roomNumber',r.room_number,'baseCapacity',r.base_capacity,'extraBedCapacity',r.extra_bed_capacity,'notes',r.notes,'isClosed',r.is_closed,'closedDay',r.closed_day,'position',r.position,'revision',r.revision,'occupancies',
        (select coalesce(jsonb_agg(jsonb_build_object('occupancyId',o.id,'revision',o.revision,'arrivalDay',o.arrival_day,'leaveDay',o.leave_day,'bedType',o.bed_type,'extraBedPersonType',o.extra_bed_person_type,'participationId',p.id,'participationStatus',p.status,
          'guardianParticipationId',guardian.id,'guardianPersonId',guardian_person.id,
          'guardianFullName',guardian_person.full_name,'guardianParticipationStatus',guardian.status,
          'person',jsonb_build_object('personId',pe.id,'fullName',pe.full_name,'phone',pe.phone,'gender',pe.gender,'dateOfBirth',pe.date_of_birth,'church',pe.church)) order by pe.full_name,o.id),'[]')
          from public.conference_accommodation_occupancies o
          join public.conference_participations p on p.id=o.participation_id
          join platform.people pe on pe.id=p.person_id
          left join public.conference_participations guardian on guardian.id=p.guardian_participation_id
          left join platform.people guardian_person on guardian_person.id=guardian.person_id
          where o.room_id=r.id)
      ) order by r.position,r.id),'[]') from public.conference_accommodation_rooms r where r.floor_id=f.id)
    ) order by f.position,f.id),'[]') from public.conference_accommodation_floors f where f.house_id=h.id)
  ) order by h.position,h.id),'[]') into result from public.conference_accommodation_houses h where h.conference_id=p_conference;
  return jsonb_build_object('conferenceId',p_conference,'houses',result);
end $$;

create or replace function public.delete_conference_participation(
  p_actor_device_id uuid,p_operation_id uuid,p_participation_id uuid,p_expected_revision bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_current public.conference_participations%rowtype; v_deleted public.conference_participations%rowtype;
  v_affected public.conference_participations[]; v_context jsonb; v_session_context jsonb;
  v_actor uuid; v_device_authorization uuid; v_request jsonb;
  v_prior public.conference_participation_operations%rowtype; v_result jsonb;
  v_deleted_ids jsonb:='[]'::jsonb;
begin
  if p_operation_id is null or p_participation_id is null or p_expected_revision is null or p_expected_revision<1 then
    raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  begin
    v_session_context:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;
    if v_session_context is null or v_session_context->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH'
       or (v_session_context->>'device_id')::uuid is distinct from p_actor_device_id then
      raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
    end if;
    v_actor:=(v_session_context->>'user_id')::uuid;
  exception when invalid_text_representation or null_value_not_allowed then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  if v_device_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501'; end if;
  v_request:=jsonb_build_object('participationId',p_participation_id,'expectedRevision',p_expected_revision);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations
  where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then
    if v_prior.operation<>'delete' or v_prior.request<>v_request then
      raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023';
    end if;
    v_context:=platform_private.require_conference_participation_context(
      p_actor_device_id,(v_prior.result->>'conferenceId')::uuid,'conference.people.manage',false);
    if (v_context->>'actorUserId')::uuid is distinct from v_actor then
      raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
    end if;
    return v_prior.result;
  end if;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=platform_private.require_conference_participation_context(
    p_actor_device_id,v_current.conference_id,'conference.people.manage',true);
  if (v_context->>'actorUserId')::uuid is distinct from v_actor then
    raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('conference-guardian:'||v_current.conference_id::text,0));
  perform 1 from public.conference_participations
  where id=p_participation_id or guardian_participation_id=p_participation_id order by id for update;
  select * into v_current from public.conference_participations where id=p_participation_id;
  if not found then raise exception 'CONFERENCE_PARTICIPATION_NOT_FOUND' using errcode='P0002'; end if;
  if v_current.revision<>p_expected_revision then
    raise exception 'CONFERENCE_PARTICIPATION_REVISION_CONFLICT' using errcode='40001';
  end if;
  select array_agg(participation order by participation.id) into v_affected
  from public.conference_participations participation
  where participation.id=p_participation_id or participation.guardian_participation_id=p_participation_id;
  foreach v_deleted in array v_affected loop
    perform platform_private.cleanup_conference_accommodation_for_participation(
      v_deleted.id,v_actor,v_device_authorization,v_context,'participation_deleted',p_operation_id);
    v_deleted_ids:=v_deleted_ids||jsonb_build_array(v_deleted.id);
  end loop;
  delete from public.conference_participations where guardian_participation_id=p_participation_id;
  delete from public.conference_participations where id=p_participation_id;
  v_result:=jsonb_build_object('participationId',p_participation_id,'conferenceId',v_current.conference_id,
    'personId',v_current.person_id,'deleted',true,'deletedParticipationIds',v_deleted_ids);
  insert into public.conference_participation_operations(actor_user_id,operation_id,operation,request,result,created_at)
  values(v_actor,p_operation_id,'delete',v_request,v_result,statement_timestamp());
  foreach v_deleted in array v_affected loop
    insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,
      entity_id,scope_type,old_values,new_values,metadata,operation_id,source)
    values(v_actor,v_device_authorization,'platform','conference','conference.participation.deleted',
      'conference_participation',v_deleted.id,'platform',jsonb_build_object(
        'conferenceId',v_deleted.conference_id,'personId',v_deleted.person_id,'status',v_deleted.status,
        'revision',v_deleted.revision,'guardianParticipationId',v_deleted.guardian_participation_id),null,
      jsonb_build_object('requestedParticipationId',p_participation_id,
        'cascade',v_deleted.id<>p_participation_id,'permissionKey','conference.people.manage',
        'authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  end loop;
  return v_result;
end $$;

revoke all on table public.conference_participations,public.conference_participation_operations
  from public,anon,authenticated,service_role;
revoke all on function platform_private.enforce_conference_participation_guardian_one_level(),
  public.list_conference_participations(uuid,uuid),
  public.set_conference_participation_guardian(uuid,uuid,uuid,bigint,uuid),
  public.get_conference_accommodation(uuid,uuid),
  public.delete_conference_participation(uuid,uuid,uuid,bigint)
  from public,anon,authenticated,service_role;

do $$
declare v_signature regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure;
  v_definition text; v_marker text:='elsif p_operation=''list_conference_participations'' then';
  v_branch text:='elsif p_operation=''set_conference_participation_guardian'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_participation_id'',''p_expected_revision'',''p_guardian_participation_id'']); return public.set_conference_participation_guardian(p_actor_device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_participation_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,(p_args->>''p_guardian_participation_id'')::uuid); elsif p_operation=''list_conference_participations'' then';
  v_occurrences integer;
begin
  v_definition:=pg_get_functiondef(v_signature);
  if position('p_operation=''set_conference_participation_guardian''' in v_definition)<>0 then
    raise exception 'P6E_B1_GUARDIAN_ROUTE_ALREADY_EXISTS' using errcode='55000';
  end if;
  v_occurrences:=(length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker);
  if v_occurrences<>1 then raise exception 'P6E_B1_CANONICAL_ROUTER_PRECONDITION_FAILED' using errcode='55000'; end if;
  execute replace(v_definition,v_marker,v_branch);
  if position('p_operation=''set_conference_participation_guardian''' in pg_get_functiondef(v_signature))=0 then
    raise exception 'P6E_B1_CANONICAL_ROUTER_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end $$;

comment on column public.conference_participations.guardian_participation_id
is 'Optional same-Conference one-level guardian Participation; canonical relationship only, never Person or Accommodation ownership.';

commit;
