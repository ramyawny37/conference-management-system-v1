begin;

alter table reservations.public_registration_requests
  add column decision_operation_id uuid,
  add column decision_intent_digest bytea check(decision_intent_digest is null or octet_length(decision_intent_digest)=32),
  add column decision_result jsonb;

create unique index public_registration_requests_decision_operation_uidx
  on reservations.public_registration_requests(decision_operation_id) where decision_operation_id is not null;

create function reservations_private.decide_public_registration_request(
  p_device_id uuid,p_operation_id uuid,p_request_id uuid,p_expected_revision bigint,
  p_decision text,p_person_id uuid,p_reason text
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  r reservations.public_registration_requests%rowtype;
  replay_request reservations.public_registration_requests%rowtype;
  v_event reservations.events%rowtype;
  v_context jsonb; v_candidates jsonb; v_booking_args jsonb; v_booking_result jsonb; v_result jsonb;
  v_intent bytea; v_actor uuid; v_person_id uuid; v_booking_id uuid;
  v_revision bigint; v_age integer;
begin
  if p_device_id is null or p_operation_id is null or p_request_id is null or p_expected_revision is null
     or p_decision not in('approve_existing','approve_new','reject','waitlist')
     or (p_decision='approve_existing' and p_person_id is null)
     or (p_decision<>'approve_existing' and p_person_id is not null)
     or char_length(coalesce(p_reason,''))>1000 then
    raise exception 'PUBLIC_REGISTRATION_DECISION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  v_intent:=extensions.digest(convert_to(jsonb_build_object(
    'requestId',p_request_id,'expectedRevision',p_expected_revision,'decision',p_decision,
    'personId',p_person_id,'reason',nullif(btrim(coalesce(p_reason,'')),'')
  )::text,'UTF8'),'sha256');

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-decision:'||p_operation_id::text,0));
  select * into replay_request from reservations.public_registration_requests where decision_operation_id=p_operation_id;
  if found then
    v_context:=reservations_private.resolve_event_scope(p_device_id,replay_request.event_id,'reservations.booking.create');
    if replay_request.decision_intent_digest<>v_intent then
      raise exception 'PUBLIC_REGISTRATION_DECISION_IDEMPOTENCY_CONFLICT' using errcode='40001';
    end if;
    return replay_request.decision_result;
  end if;

  select * into r from reservations.public_registration_requests where id=p_request_id for update;
  if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  v_context:=reservations_private.resolve_event_scope(p_device_id,r.event_id,'reservations.booking.create');
  v_actor:=(v_context->>'actorUserId')::uuid;
  if r.revision<>p_expected_revision then raise exception 'PUBLIC_REGISTRATION_REVISION_CONFLICT' using errcode='40001'; end if;
  if (p_decision='waitlist' and r.state not in('submitted','under_review'))
     or (p_decision in('approve_existing','approve_new','reject') and r.state not in('submitted','under_review','waitlisted')) then
    raise exception 'PUBLIC_REGISTRATION_STATE_CONFLICT' using errcode='40001';
  end if;

  if p_decision in('reject','waitlist') then
    update reservations.public_registration_requests
    set state=case when p_decision='reject' then 'rejected' else 'waitlisted' end,
        decision_reason=nullif(btrim(coalesce(p_reason,'')),''),decided_at=statement_timestamp(),
        decided_by=v_actor,decided_by_device_id=p_device_id,decision_operation_id=p_operation_id,
        decision_intent_digest=v_intent,revision=revision+1,updated_at=statement_timestamp()
    where id=r.id returning revision into v_revision;
    v_result:=jsonb_build_object('requestId',r.id,'state',case when p_decision='reject' then 'rejected' else 'waitlisted' end,'revision',v_revision);
    update reservations.public_registration_requests set decision_result=v_result where id=r.id;
    perform reservations_private.audit(v_context,'public_registration_request.'||case when p_decision='reject' then 'rejected' else 'waitlisted' end,'public_registration_request',r.id,p_operation_id,to_jsonb(r),v_result);
    return v_result;
  end if;

  select * into v_event from reservations.events
  where id=r.event_id and id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid
  for key share;
  if not found then raise exception 'PUBLIC_REGISTRATION_EVENT_SCOPE_CONFLICT' using errcode='40001'; end if;
  if r.submitted_date_of_birth is null or r.submitted_date_of_birth>v_event.start_date then
    raise exception 'PUBLIC_REGISTRATION_DATE_OF_BIRTH_INVALID' using errcode='22023';
  end if;
  v_age:=extract(year from pg_catalog.age(v_event.start_date,r.submitted_date_of_birth))::integer;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reservations-person-name:'||platform_private.person_name_key(r.submitted_full_name),0));
  if platform_private.person_phone_key(r.submitted_phone)<>'' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reservations-person-phone:'||platform_private.person_phone_key(r.submitted_phone),0));
  end if;
  v_candidates:=platform_private.reservations_person_identity_candidates(r.submitted_full_name,r.submitted_phone,10);
  if p_decision='approve_existing' and not exists(
    select 1 from jsonb_array_elements(v_candidates) candidate where candidate->>'personId'=p_person_id::text
  ) then
    raise exception 'PUBLIC_REGISTRATION_PERSON_CANDIDATE_STALE' using errcode='40001';
  end if;

  v_booking_args:=jsonb_strip_nulls(jsonb_build_object(
    'p_operation_id',p_operation_id,'p_event_id',r.event_id,'p_booking_type_id',r.booking_type_id,
    'p_full_name',r.submitted_full_name,'p_phone',r.submitted_phone,'p_age',v_age,
    'p_church',r.submitted_church,'p_governorate',r.submitted_governorate,
    'p_city_or_village',r.submitted_city_or_village,'p_service_sector',r.submitted_service_sector,
    'p_service_sector_other',r.submitted_service_sector_other,'p_notes',r.submitted_notes,
    'p_gender',r.submitted_gender,'p_date_of_birth',r.submitted_date_of_birth,
    'p_person_id',case when p_decision='approve_existing' then p_person_id else null end
  ));
  v_booking_result:=reservations.mutate(p_device_id,'create_booking',v_booking_args);
  if p_decision='approve_new' and coalesce((v_booking_result->>'identityResolutionRequired')::boolean,false) then
    if nullif(v_booking_result->>'identityResolutionToken','') is null then
      raise exception 'PUBLIC_REGISTRATION_IDENTITY_RESOLUTION_STALE' using errcode='40001';
    end if;
    v_booking_result:=reservations.mutate(
      p_device_id,'create_booking',
      v_booking_args || jsonb_build_object(
        'p_identity_resolution_token',v_booking_result->>'identityResolutionToken',
        'p_identity_resolution_decision','different'
      )
    );
  end if;
  v_booking_id:=nullif(v_booking_result->>'bookingId','')::uuid;
  if v_booking_id is null then raise exception 'PUBLIC_REGISTRATION_IDENTITY_RESOLUTION_STALE' using errcode='40001'; end if;
  select participant.person_id into v_person_id
  from reservations.bookings booking
  join reservations.participants participant on participant.id=booking.participant_id and participant.scope_partition_id=booking.scope_partition_id
  where booking.id=v_booking_id and booking.event_id=r.event_id and booking.scope_partition_id=(v_context->>'scopePartitionId')::uuid;
  if v_person_id is null then raise exception 'PUBLIC_REGISTRATION_BOOKING_LINK_INVALID' using errcode='40001'; end if;

  update reservations.public_registration_requests
  set state='approved',resolved_person_id=v_person_id,booking_id=v_booking_id,
      decision_reason=nullif(btrim(coalesce(p_reason,'')),''),decided_at=statement_timestamp(),
      decided_by=v_actor,decided_by_device_id=p_device_id,decision_operation_id=p_operation_id,
      decision_intent_digest=v_intent,revision=revision+1,updated_at=statement_timestamp()
  where id=r.id returning revision into v_revision;
  v_result:=jsonb_build_object('requestId',r.id,'state','approved','revision',v_revision,
    'resolvedPersonId',v_person_id,'bookingId',v_booking_id,'bookingNumber',v_booking_result->>'bookingNumber');
  update reservations.public_registration_requests set decision_result=v_result where id=r.id;
  perform reservations_private.audit(v_context,'public_registration_request.approved','public_registration_request',r.id,p_operation_id,to_jsonb(r),v_result);
  return v_result;
end $$;

revoke all on function reservations_private.decide_public_registration_request(uuid,uuid,uuid,bigint,text,uuid,text)
  from public,anon,authenticated,service_role;

do $patch$
declare
  v_oid oid:='platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure;
  v_def text; v_new text;
  v_anchor text:=E'    case p_operation\n    when \'list_public_registration_requests\' then';
  v_insert text:=E'    case p_operation\n    when \'decide_public_registration_request\' then\n      perform platform_private.require_exact_jsonb_keys(p_args,array[\'p_operation_id\',\'p_request_id\',\'p_expected_revision\',\'p_decision\'],array[\'p_person_id\',\'p_reason\']);\n      return reservations_private.decide_public_registration_request(v_session.device_id,(p_args->>\'p_operation_id\')::uuid,(p_args->>\'p_request_id\')::uuid,(p_args->>\'p_expected_revision\')::bigint,p_args->>\'p_decision\',nullif(p_args->>\'p_person_id\',\'\')::uuid,p_args->>\'p_reason\');\n    when \'list_public_registration_requests\' then';
begin
  select pg_get_functiondef(v_oid) into v_def;
  if position('when ''decide_public_registration_request'' then' in v_def)>0 then raise exception 'PUBLIC_REGISTRATION_DECISION_DISPATCH_ALREADY_PRESENT'; end if;
  if length(v_def)-length(replace(v_def,v_anchor,''))<>length(v_anchor) then raise exception 'PUBLIC_REGISTRATION_DECISION_DISPATCH_ANCHOR_MISMATCH'; end if;
  v_new:=replace(v_def,v_anchor,v_insert); execute v_new;
  select pg_get_functiondef(v_oid) into v_def;
  if position('when ''decide_public_registration_request'' then' in v_def)=0
     or not has_function_privilege('service_role',v_oid,'execute')
     or has_function_privilege('anon',v_oid,'execute') or has_function_privilege('authenticated',v_oid,'execute') then
    raise exception 'PUBLIC_REGISTRATION_DECISION_DISPATCH_POSTCONDITION_FAILED';
  end if;
end $patch$;

commit;
