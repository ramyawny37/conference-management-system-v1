-- Canonical writer: reject operational review updates on apologized/deleted bookings.
-- Lock booking before updating review to serialize against cancellation/deletion.
CREATE OR REPLACE FUNCTION reservations_private.mutate_scoped(p_device_id uuid, p_operation text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_context jsonb; v_replay jsonb; v_result jsonb; v_event reservations.events%rowtype; v_period reservations.event_periods%rowtype; v_type reservations.booking_types%rowtype; v_booking reservations.bookings%rowtype; v_payment reservations.payments%rowtype; v_operation reservations.operations%rowtype; v_id uuid; v_revision bigint; v_actor uuid; v_partition uuid; v_number text; v_operation_id uuid:=(p_args->>'p_operation_id')::uuid; v_count integer; v_identity_profile jsonb; v_identity_candidates jsonb; v_identity_challenge reservations_private.manual_person_identity_challenges%rowtype; v_person_id uuid;
begin
 if p_args is null or jsonb_typeof(p_args)<>'object' or p_args ?| array['scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id'] then raise exception 'RESERVATIONS_SCOPE_OVERRIDE_DENIED' using errcode='42501'; end if;
 if p_operation='delete_event' and v_operation_id is not null then
  select * into v_operation from reservations.operations where operation_id=v_operation_id;
  if found then
   v_context:=public.require_effective_module_permission(p_device_id,'reservations','reservations.event.manage',null,null)||jsonb_build_object('scopePartitionId',v_operation.scope_partition_id);
   return reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  end if;
 end if;
 if p_operation='delete_event_period' and v_operation_id is not null then
  select * into v_operation from reservations.operations where operation_id=v_operation_id;
  if found then
   v_context:=public.require_effective_module_permission(p_device_id,'reservations','reservations.event.manage',null,null)||jsonb_build_object('scopePartitionId',v_operation.scope_partition_id);
   return reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  end if;
 end if;
 if p_operation='delete_booking' and v_operation_id is not null then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision']);
  select * into v_operation from reservations.operations where operation_id=v_operation_id;
  if found then
   v_context:=public.require_effective_module_permission(p_device_id,'reservations','reservations.booking.delete',null,null)||jsonb_build_object('scopePartitionId',v_operation.scope_partition_id);
   return reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  end if;
 end if;
 if p_operation='create_event' then
  if p_args->>'p_scope_type'='standalone' then
   return reservations_private.create_standalone_event_scoped(p_device_id,p_args-'p_scope_type');
  elsif p_args->>'p_scope_type'<>'conference' or (p_args->>'p_conference_id')::uuid is null then raise exception 'RESERVATIONS_CREATE_EVENT_SCOPE_INVALID' using errcode='22023'; end if;
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_scope_type','p_conference_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']);
  v_context:=reservations_private.conference_context(p_device_id,(p_args->>'p_conference_id')::uuid,'reservations.event.manage'); v_actor:=(v_context->>'actorUserId')::uuid; v_partition:=(v_context->>'scopePartitionId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,'create_event',p_args); if v_replay is not null then return v_replay; end if;
  insert into reservations.events(scope_type,scope_partition_id,conference_id,name,start_date,end_date,location,capacity,status,notes,created_by,updated_by) values('conference',v_partition,(p_args->>'p_conference_id')::uuid,btrim(p_args->>'p_name'),(p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,coalesce(p_args->>'p_location',''),(p_args->>'p_capacity')::integer,p_args->>'p_status',coalesce(p_args->>'p_notes',''),v_actor,v_actor) returning id,revision into v_id,v_revision;
  v_result:=jsonb_build_object('eventId',v_id,'revision',v_revision,'scopeType','conference','scopePartitionId',v_partition); perform reservations_private.audit(v_context||jsonb_build_object('scopeType','conference','scopePartitionId',v_partition),'event.created','event',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,'create_event',p_args,v_result);
 end if;
 if p_operation='update_event' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage');
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if v_event.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if;
  update reservations.events set name=btrim(p_args->>'p_name'),start_date=(p_args->>'p_start_date')::date,end_date=(p_args->>'p_end_date')::date,location=coalesce(p_args->>'p_location',''),capacity=(p_args->>'p_capacity')::integer,status=p_args->>'p_status',notes=coalesce(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid where id=v_event.id returning revision into v_revision; if exists(select 1 from reservations.event_periods where event_id=v_event.id and (starts_on<(p_args->>'p_start_date')::date or ends_on>(p_args->>'p_end_date')::date)) then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE' using errcode='22023'; end if; v_result:=jsonb_build_object('eventId',v_event.id,'revision',v_revision); perform reservations_private.audit(v_context,'event.updated','event',v_event.id,v_operation_id,to_jsonb(v_event),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='delete_event' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid for update; if v_event.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; if exists(select 1 from reservations.bookings where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id) then raise exception 'RESERVATIONS_EVENT_HAS_DEPENDENCIES' using errcode='55000'; end if; delete from reservations.event_periods where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id; delete from reservations.booking_types where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id; delete from reservations.events where id=v_event.id; v_result:=jsonb_build_object('eventId',v_event.id,'deleted',true); perform reservations_private.audit(v_context,'event.deleted','event',v_event.id,v_operation_id,to_jsonb(v_event),null); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='create_event_period' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_kind','p_label','p_starts_on','p_ends_on','p_display_order']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid for key share; if ((coalesce(p_args->>'p_kind','')!~'^[a-z][a-z0-9_-]{0,39}$' or length(btrim(coalesce(p_args->>'p_label',''))) not between 1 and 120) or length(btrim(coalesce(p_args->>'p_label',''))) not between 1 and 120) or (p_args->>'p_starts_on')::date<v_event.start_date or (p_args->>'p_ends_on')::date>v_event.end_date then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE' using errcode='22023'; end if; insert into reservations.event_periods(scope_partition_id,event_id,kind,label,starts_on,ends_on,display_order,created_by,updated_by) values(v_event.scope_partition_id,v_event.id,p_args->>'p_kind',btrim(p_args->>'p_label'),(p_args->>'p_starts_on')::date,(p_args->>'p_ends_on')::date,(p_args->>'p_display_order')::integer,(v_context->>'actorUserId')::uuid,(v_context->>'actorUserId')::uuid) returning id,revision into v_id,v_revision; v_result:=jsonb_build_object('periodId',v_id,'revision',v_revision); perform reservations_private.audit(v_context,'event_period.created','event_period',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation in ('update_event_period','delete_event_period') then
  perform platform_private.require_exact_jsonb_keys(p_args,case when p_operation='update_event_period' then array['p_operation_id','p_period_id','p_expected_revision','p_kind','p_label','p_starts_on','p_ends_on','p_display_order'] else array['p_operation_id','p_period_id','p_expected_revision'] end); v_context:=reservations_private.resolve_event_period_scope(p_device_id,(p_args->>'p_period_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_period from reservations.event_periods where id=(v_context->>'periodId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if v_period.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; if p_operation='delete_event_period' then delete from reservations.event_periods where id=v_period.id; v_result:=jsonb_build_object('periodId',v_period.id,'deleted',true); else select * into v_event from reservations.events where id=v_period.event_id; if ((coalesce(p_args->>'p_kind','')!~'^[a-z][a-z0-9_-]{0,39}$' or length(btrim(coalesce(p_args->>'p_label',''))) not between 1 and 120) or length(btrim(coalesce(p_args->>'p_label',''))) not between 1 and 120) or (p_args->>'p_starts_on')::date<v_event.start_date or (p_args->>'p_ends_on')::date>v_event.end_date then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE' using errcode='22023'; end if; update reservations.event_periods set kind=p_args->>'p_kind',label=btrim(p_args->>'p_label'),starts_on=(p_args->>'p_starts_on')::date,ends_on=(p_args->>'p_ends_on')::date,display_order=(p_args->>'p_display_order')::integer,revision=revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid where id=v_period.id returning revision into v_revision; v_result:=jsonb_build_object('periodId',v_period.id,'revision',v_revision); end if; perform reservations_private.audit(v_context,'event_period.'||case when p_operation='delete_event_period' then 'deleted' else 'updated' end,'event_period',v_period.id,v_operation_id,to_jsonb(v_period),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='create_booking_type' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_name','p_code','p_price','p_active','p_display_order','p_eligible_attendance_segments']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for key share; if jsonb_typeof(p_args->'p_eligible_attendance_segments') is distinct from 'array' or jsonb_array_length(p_args->'p_eligible_attendance_segments')=0 or exists(select 1 from jsonb_array_elements_text(p_args->'p_eligible_attendance_segments') segment(value) where not exists(select 1 from reservations.event_periods period where period.event_id=v_event.id and period.scope_partition_id=v_event.scope_partition_id and period.kind=segment.value)) then raise exception 'RESERVATIONS_BOOKING_TYPE_PERIOD_INVALID' using errcode='23514'; end if; insert into reservations.booking_types(scope_partition_id,event_id,name,code,price,active,display_order,eligible_attendance_segments,created_by,updated_by) values(v_event.scope_partition_id,v_event.id,btrim(p_args->>'p_name'),btrim(p_args->>'p_code'),(p_args->>'p_price')::numeric,(p_args->>'p_active')::boolean,(p_args->>'p_display_order')::integer,coalesce((select array_agg(value) from jsonb_array_elements_text(p_args->'p_eligible_attendance_segments') s(value)),'{}'::text[]),(v_context->>'actorUserId')::uuid,(v_context->>'actorUserId')::uuid) returning id,revision into v_id,v_revision; v_result:=jsonb_build_object('bookingTypeId',v_id,'revision',v_revision); perform reservations_private.audit(v_context,'booking_type.created','booking_type',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='update_booking_type' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_type_id','p_expected_revision','p_name','p_code','p_price','p_active','p_display_order','p_eligible_attendance_segments']); v_context:=reservations_private.resolve_booking_type_scope(p_device_id,(p_args->>'p_booking_type_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_type from reservations.booking_types where id=(v_context->>'bookingTypeId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_TYPE_NOT_FOUND' using errcode='P0002'; end if; if v_type.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; if jsonb_typeof(p_args->'p_eligible_attendance_segments') is distinct from 'array' or jsonb_array_length(p_args->'p_eligible_attendance_segments')=0 or exists(select 1 from jsonb_array_elements_text(p_args->'p_eligible_attendance_segments') segment(value) where not exists(select 1 from reservations.event_periods period where period.event_id=v_type.event_id and period.scope_partition_id=v_type.scope_partition_id and period.kind=segment.value)) then raise exception 'RESERVATIONS_BOOKING_TYPE_PERIOD_INVALID' using errcode='23514'; end if;
  update reservations.booking_types set name=btrim(p_args->>'p_name'),code=btrim(p_args->>'p_code'),price=(p_args->>'p_price')::numeric,active=(p_args->>'p_active')::boolean,display_order=(p_args->>'p_display_order')::integer,eligible_attendance_segments=coalesce((select array_agg(value) from jsonb_array_elements_text(p_args->'p_eligible_attendance_segments') s(value)),'{}'::text[]),revision=revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid where id=v_type.id and event_id=v_type.event_id and scope_partition_id=v_type.scope_partition_id returning revision into v_revision; v_result:=jsonb_build_object('bookingTypeId',v_type.id,'revision',v_revision); perform reservations_private.audit(v_context,'booking_type.updated','booking_type',v_type.id,v_operation_id,to_jsonb(v_type),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='create_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_booking_type_id','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes'],array['p_person_id','p_person_update_revision','p_gender','p_date_of_birth','p_identity_resolution_token','p_identity_resolution_decision']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.booking.create'); v_actor:=(v_context->>'actorUserId')::uuid;
  select * into v_event from reservations.events where id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found or v_event.status in('closed','full') then raise exception 'RESERVATIONS_EVENT_NOT_ACCEPTING_BOOKINGS' using errcode='22023'; end if; select * into v_type from reservations.booking_types where id=(p_args->>'p_booking_type_id')::uuid and event_id=v_event.id and scope_partition_id=v_event.scope_partition_id for key share; if not found or not v_type.active then raise exception 'RESERVATIONS_BOOKING_TYPE_INACTIVE' using errcode='22023'; end if; select count(*) into v_count from reservations.bookings where event_id=v_event.id and scope_partition_id=v_event.scope_partition_id and lifecycle_status='active'; if v_event.capacity is not null and v_count>=v_event.capacity then raise exception 'RESERVATIONS_EVENT_CAPACITY_REACHED' using errcode='22023'; end if;
  if p_args ? 'p_person_update_revision' and nullif(p_args->>'p_person_id','') is null then raise exception 'PERSON_UPDATE_REQUIRES_EXPLICIT_ID' using errcode='22023'; end if; 
  -- Serialize identities sharing either normalized key. This closes the race
  -- between candidate discovery and canonical person creation across events.
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; perform pg_advisory_xact_lock(hashtextextended('reservations-person-name:'||platform_private.person_name_key(p_args->>'p_full_name'),0));
  if platform_private.person_phone_key(p_args->>'p_phone')<>'' then
    perform pg_advisory_xact_lock(hashtextextended('reservations-person-phone:'||platform_private.person_phone_key(p_args->>'p_phone'),0));
  end if;
  v_identity_profile:=jsonb_strip_nulls(jsonb_build_object(
    'fullName',btrim(p_args->>'p_full_name'),'phone',nullif(btrim(coalesce(p_args->>'p_phone','')),''),
    'gender',nullif(p_args->>'p_gender',''),'dateOfBirth',nullif(p_args->>'p_date_of_birth',''),
    'church',nullif(btrim(coalesce(p_args->>'p_church','')),''),
    'governorate',nullif(btrim(coalesce(p_args->>'p_governorate','')),''),
    'cityOrVillage',nullif(btrim(coalesce(p_args->>'p_city_or_village','')),''),
    'serviceSector',nullif(btrim(coalesce(p_args->>'p_service_sector','')),''),
    'serviceSectorOther',nullif(btrim(coalesce(p_args->>'p_service_sector_other','')),'')
  ));
  v_identity_candidates:=platform_private.reservations_person_identity_candidates(
    p_args->>'p_full_name',p_args->>'p_phone',10
  );
  delete from reservations_private.manual_person_identity_challenges
    where expires_at<=statement_timestamp();

  if nullif(p_args->>'p_identity_resolution_token','') is not null then
    select * into v_identity_challenge
    from reservations_private.manual_person_identity_challenges
    where token=(p_args->>'p_identity_resolution_token')::uuid
      and operation_id=v_operation_id and device_id=p_device_id and event_id=v_event.id
      and expires_at>statement_timestamp()
    for update;
    if not found
       or v_identity_challenge.input_profile<>v_identity_profile
       or v_identity_challenge.candidates<>v_identity_candidates then
      raise exception 'RESERVATIONS_PERSON_IDENTITY_RESOLUTION_STALE' using errcode='40001';
    end if;
    if p_args->>'p_identity_resolution_decision'='different' then
      if nullif(p_args->>'p_person_id','') is not null then
        raise exception 'RESERVATIONS_PERSON_IDENTITY_DECISION_INVALID' using errcode='22023';
      end if;
    elsif p_args->>'p_identity_resolution_decision'='existing' then
      if nullif(p_args->>'p_person_id','') is null
         or not exists(
           select 1 from jsonb_array_elements(v_identity_candidates) candidate
           where candidate->>'personId'=p_args->>'p_person_id'
         ) then
        raise exception 'RESERVATIONS_PERSON_IDENTITY_DECISION_INVALID' using errcode='22023';
      end if;
    else
      raise exception 'RESERVATIONS_PERSON_IDENTITY_DECISION_REQUIRED' using errcode='22023';
    end if;
    delete from reservations_private.manual_person_identity_challenges
      where token=v_identity_challenge.token;
  elsif nullif(p_args->>'p_person_id','') is null and jsonb_array_length(v_identity_candidates)>0 then
    insert into reservations_private.manual_person_identity_challenges(
      operation_id,device_id,event_id,input_profile,candidates
    ) values(v_operation_id,p_device_id,v_event.id,v_identity_profile,v_identity_candidates)
    on conflict(operation_id,device_id,event_id) do update set
      token=gen_random_uuid(),input_profile=excluded.input_profile,
      candidates=excluded.candidates,created_at=statement_timestamp(),
      expires_at=statement_timestamp()+interval '10 minutes'
    returning * into v_identity_challenge;
    return jsonb_build_object(
      'identityResolutionRequired',true,
      'identityResolutionToken',v_identity_challenge.token,
      'candidates',v_identity_challenge.candidates
    );
  end if;

  v_number:=reservations_private.allocate_booking_number(v_event.scope_partition_id,extract(year from v_event.start_date)::integer); perform set_config('reservations.scope_partition_id',v_event.scope_partition_id::text,true); if p_args ? 'p_person_id' and nullif(p_args->>'p_person_id','') is not null and not exists(select 1 from platform.people where id=(p_args->>'p_person_id')::uuid) then raise exception 'PLATFORM_PERSON_NOT_FOUND' using errcode='23503'; end if; if nullif(p_args->>'p_person_id','') is null then insert into platform.people(full_name,phone,church,gender,date_of_birth,governorate,city_or_village,service_sector,service_sector_other,created_by,updated_by) values(btrim(p_args->>'p_full_name'),nullif(btrim(coalesce(p_args->>'p_phone','')),''),nullif(btrim(coalesce(p_args->>'p_church','')),''),nullif(p_args->>'p_gender',''),nullif(p_args->>'p_date_of_birth','')::date,nullif(btrim(coalesce(p_args->>'p_governorate','')),''),nullif(btrim(coalesce(p_args->>'p_city_or_village','')),''),nullif(btrim(coalesce(p_args->>'p_service_sector','')),''),nullif(btrim(coalesce(p_args->>'p_service_sector_other','')),''),v_actor,v_actor) returning id into v_person_id; insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,new_values,metadata,operation_id,source) values(v_actor,(select id from platform.user_device_authorizations where device_id=p_device_id and user_id=v_actor and status='approved' limit 1),'platform','reservations','platform.person.created','person',v_person_id,'platform',jsonb_build_object('id',v_person_id,'fullName',btrim(p_args->>'p_full_name'),'phone',nullif(btrim(coalesce(p_args->>'p_phone','')),''),'church',nullif(btrim(coalesce(p_args->>'p_church','')),'')),jsonb_build_object('eventId',v_event.id,'permissionKey','reservations.booking.create'),v_operation_id,'rpc'); else v_person_id:=(p_args->>'p_person_id')::uuid;
  if exists (
    select 1 from reservations.bookings existing_booking
    join reservations.participants existing_participant
      on existing_participant.id=existing_booking.participant_id
     and existing_participant.scope_partition_id=existing_booking.scope_partition_id
    where existing_booking.scope_partition_id=v_event.scope_partition_id
      and existing_booking.event_id=v_event.id
      and existing_participant.person_id=v_person_id
      and existing_booking.lifecycle_status='active'
  ) then
    raise exception 'RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT' using errcode='23505';
  end if;

  if p_args ? 'p_person_update_revision' then
    if (p_args->>'p_person_update_revision') is null or (p_args->>'p_person_update_revision') !~ '^[0-9]+$' then raise exception 'PERSON_REVISION_REQUIRED' using errcode='22023'; end if;
    perform public.require_effective_module_permission(p_device_id,'reservations','reservations.people.manage',null,null);
    perform platform_private.update_canonical_person(p_device_id,v_actor,v_person_id,(p_args->>'p_person_update_revision')::bigint,jsonb_build_object('fullName',p_args->>'p_full_name','phone',p_args->>'p_phone','church',p_args->>'p_church','governorate',p_args->>'p_governorate','cityOrVillage',p_args->>'p_city_or_village','serviceSector',p_args->>'p_service_sector','serviceSectorOther',p_args->>'p_service_sector_other') || case when p_args ? 'p_gender' then jsonb_build_object('gender',p_args->>'p_gender') else '{}'::jsonb end || case when p_args ? 'p_date_of_birth' then jsonb_build_object('dateOfBirth',p_args->>'p_date_of_birth') else '{}'::jsonb end,v_operation_id,'reservations','reservations.people.manage',jsonb_build_object('eventId',v_event.id));
  end if;
  end if;  insert into reservations.participants(scope_partition_id,person_id,full_name,phone,age,church,governorate,city_or_village,service_sector,service_sector_other,gender_snapshot,date_of_birth_snapshot,notes,created_by,updated_by) values(v_event.scope_partition_id,v_person_id,btrim(p_args->>'p_full_name'),btrim(p_args->>'p_phone'),(p_args->>'p_age')::integer,coalesce(p_args->>'p_church',''),btrim(p_args->>'p_governorate'),coalesce(p_args->>'p_city_or_village',''),p_args->>'p_service_sector',nullif(btrim(p_args->>'p_service_sector_other'),''),nullif(p_args->>'p_gender',''),nullif(p_args->>'p_date_of_birth','')::date,nullif(p_args->>'p_notes',''),v_actor,v_actor) returning id into v_id; insert into reservations.bookings(scope_partition_id,booking_number,participant_id,event_id,booking_type_id,booking_type_name_snapshot,price_snapshot,attendance_segments_snapshot,notes,created_by,updated_by) values(v_event.scope_partition_id,v_number,v_id,v_event.id,v_type.id,v_type.name,v_type.price,v_type.eligible_attendance_segments,nullif(p_args->>'p_notes',''),v_actor,v_actor) returning id,revision into v_booking.id,v_revision; insert into reservations.operational_reviews(scope_partition_id,booking_id,created_by,updated_by) values(v_event.scope_partition_id,v_booking.id,v_actor,v_actor); v_result:=jsonb_build_object('participantId',v_id,'bookingId',v_booking.id,'bookingNumber',v_number,'revision',v_revision); perform reservations_private.audit(v_context,'booking.created','booking',v_booking.id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='cancel_booking' then return reservations_private.cancel_booking_scoped(p_device_id,p_args); end if;
 if p_operation='disburse_refund' then return reservations_private.disburse_refund_scoped(p_device_id,p_args); end if; if p_operation='redeem_person_credit' then return reservations_private.redeem_person_credit_scoped(p_device_id,p_args); end if; if p_operation='update_participant_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes'],array['p_gender','p_date_of_birth','p_person_update_revision']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.update'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; if v_booking.lifecycle_status<>'active' then raise exception 'RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE' using errcode='55000'; end if;
  select * into v_type from reservations.booking_types where id=(p_args->>'p_booking_type_id')::uuid and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id for key share; if not found then raise exception 'RESERVATIONS_BOOKING_TYPE_EVENT_MISMATCH' using errcode='22023'; end if; if v_type.id<>v_booking.booking_type_id and not v_type.active then raise exception 'RESERVATIONS_BOOKING_TYPE_INACTIVE' using errcode='22023'; end if;
  if p_args ? 'p_person_update_revision' then if (p_args->>'p_person_update_revision') is null or (p_args->>'p_person_update_revision') !~ '^[0-9]+$' then raise exception 'PERSON_REVISION_REQUIRED' using errcode='22023'; end if; perform platform_private.update_canonical_person(p_device_id,v_actor,(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id),(p_args->>'p_person_update_revision')::bigint,jsonb_build_object('fullName',p_args->>'p_full_name','phone',p_args->>'p_phone','church',p_args->>'p_church','governorate',p_args->>'p_governorate','cityOrVillage',p_args->>'p_city_or_village','serviceSector',p_args->>'p_service_sector','serviceSectorOther',p_args->>'p_service_sector_other') || case when p_args ? 'p_gender' then jsonb_build_object('gender',p_args->>'p_gender') else '{}'::jsonb end || case when p_args ? 'p_date_of_birth' then jsonb_build_object('dateOfBirth',p_args->>'p_date_of_birth') else '{}'::jsonb end,v_operation_id,'reservations','reservations.people.manage',jsonb_build_object('eventId',v_booking.event_id)); end if; update reservations.participants set full_name=btrim(p_args->>'p_full_name'),phone=btrim(p_args->>'p_phone'),age=(p_args->>'p_age')::integer,church=coalesce(p_args->>'p_church',''),governorate=btrim(p_args->>'p_governorate'),city_or_village=coalesce(p_args->>'p_city_or_village',''),service_sector=p_args->>'p_service_sector',service_sector_other=nullif(btrim(p_args->>'p_service_sector_other'),''),gender_snapshot=case when p_args ? 'p_gender' then nullif(p_args->>'p_gender','') else gender_snapshot end,date_of_birth_snapshot=case when p_args ? 'p_date_of_birth' then nullif(p_args->>'p_date_of_birth','')::date else date_of_birth_snapshot end,notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; update reservations.bookings set booking_type_id=v_type.id,booking_type_name_snapshot=v_type.name,notes=nullif(p_args->>'p_notes',''),revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor where id=v_booking.id and event_id=v_booking.event_id and scope_partition_id=v_booking.scope_partition_id returning revision into v_revision; v_result:=jsonb_build_object('bookingId',v_booking.id,'bookingTypeId',v_type.id,'revision',v_revision); perform reservations_private.audit(v_context,'booking.updated','booking',v_booking.id,v_operation_id,to_jsonb(v_booking),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;

 if p_operation='delete_booking' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision']);
  v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.booking.delete');
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args);
  if v_replay is not null then return v_replay; end if;
  select * into v_booking from reservations.bookings
   where id=(v_context->>'bookingId')::uuid
     and event_id=(v_context->>'eventId')::uuid
     and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update;
  if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if;
  if v_booking.revision<>(p_args->>'p_expected_revision')::bigint then
    raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001';
  end if;
  if v_booking.lifecycle_status='deleted' then
    raise exception 'RESERVATIONS_BOOKING_ALREADY_DELETED' using errcode='55000';
  end if;
  if exists(
    select 1 from reservations.events e
    join reservations.participants p
      on p.id=v_booking.participant_id and p.scope_partition_id=v_booking.scope_partition_id
    join public.conference_participations cp
      on cp.conference_id=e.conference_id and cp.person_id=p.person_id
    where e.id=v_booking.event_id and e.scope_partition_id=v_booking.scope_partition_id
      and e.scope_type='conference'
  ) then
    raise exception 'RESERVATIONS_CONFERENCE_PERSON_MANUAL_ACTION_REQUIRED' using errcode='55000';
  end if;

  if v_booking.lifecycle_status='active'
     and not exists(select 1 from reservations.booking_cancellation_settlements s
                    where s.booking_id=v_booking.id and s.scope_partition_id=v_booking.scope_partition_id) then
    insert into reservations.booking_cancellation_settlements(
      scope_partition_id,booking_id,person_id,collected_amount,
      non_refundable_amount,refunded_amount,credit_amount,pending_refund_amount,
      reason,created_by,created_by_device_id,operation_id
    )
    select v_booking.scope_partition_id,v_booking.id,p.person_id,
      coalesce(pay.collected,0),0,0,0,coalesce(pay.collected,0),
      'حذف من الفعالية',v_actor,p_device_id,v_operation_id
    from reservations.participants p
    left join lateral(
      select sum(z.amount) collected
      from reservations.payments z
      where z.booking_id=v_booking.id
        and z.scope_partition_id=v_booking.scope_partition_id
        and z.status='active'
    ) pay on true
    where p.id=v_booking.participant_id
      and p.scope_partition_id=v_booking.scope_partition_id;
  end if;

  update reservations.bookings set
    lifecycle_status='deleted',
    deleted_at=statement_timestamp(),
    deleted_by=v_actor,
    deleted_by_device_id=p_device_id,
    revision=revision+1,
    updated_at=statement_timestamp(),
    updated_by=v_actor
  where id=v_booking.id
    and event_id=v_booking.event_id
    and scope_partition_id=v_booking.scope_partition_id
  returning revision into v_revision;

  v_result:=jsonb_build_object(
    'bookingId',v_booking.id,'deleted',true,'status','deleted','revision',v_revision
  );
  perform reservations_private.audit(
    v_context,'booking.deleted','booking',v_booking.id,v_operation_id,to_jsonb(v_booking),v_result
  );
  return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='record_payment' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_amount','p_payment_date','p_payment_method','p_payment_method_other','p_reference','p_notes']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.payment.record'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.lifecycle_status<>'active' then raise exception 'RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE' using errcode='55000'; end if;
  insert into reservations.payments(scope_partition_id,booking_id,amount,payment_date,payment_method,payment_method_other,reference,notes,created_by,created_by_device_id) values(v_booking.scope_partition_id,v_booking.id,(p_args->>'p_amount')::numeric,(p_args->>'p_payment_date')::date,p_args->>'p_payment_method',nullif(btrim(p_args->>'p_payment_method_other'),''),nullif(p_args->>'p_reference',''),nullif(p_args->>'p_notes',''),v_actor,p_device_id) returning id into v_id; v_result:=jsonb_build_object('paymentId',v_id,'status','active'); perform reservations_private.audit(v_context,'payment.recorded','payment',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='void_payment' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_payment_id','p_void_reason']); v_context:=reservations_private.resolve_payment_scope(p_device_id,(p_args->>'p_payment_id')::uuid,'reservations.payment.void'); v_actor:=(v_context->>'actorUserId')::uuid;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.lifecycle_status<>'active' then raise exception 'RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE' using errcode='55000'; end if; select * into v_payment from reservations.payments where id=(v_context->>'paymentId')::uuid and booking_id=(v_context->>'bookingId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_PAYMENT_NOT_FOUND' using errcode='P0002'; end if; if v_payment.status<>'active' or nullif(btrim(p_args->>'p_void_reason'),'') is null then raise exception 'RESERVATIONS_PAYMENT_VOID_INVALID' using errcode='22023'; end if;
  update reservations.payments set status='voided',voided_at=statement_timestamp(),void_reason=btrim(p_args->>'p_void_reason'),voided_by=v_actor,voided_by_device_id=p_device_id where id=v_payment.id and booking_id=v_payment.booking_id and scope_partition_id=v_payment.scope_partition_id; v_result:=jsonb_build_object('paymentId',v_payment.id,'status','voided'); perform reservations_private.audit(v_context,'payment.voided','payment',v_payment.id,v_operation_id,to_jsonb(v_payment),v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='update_attendance' then if exists(select 1 from reservations.bookings where id=(p_args->>'p_booking_id')::uuid and lifecycle_status<>'active') then raise exception 'RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE' using errcode='55000'; end if;
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_segment','p_attended','p_attendance_date','p_notes']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.attendance.manage'); v_actor:=(v_context->>'actorUserId')::uuid;
  select * into v_booking from reservations.bookings where id=(v_context->>'bookingId')::uuid and event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if; if v_booking.lifecycle_status<>'active' then raise exception 'RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE' using errcode='55000'; end if; if cardinality(v_booking.attendance_segments_snapshot)=0 then raise exception 'RESERVATIONS_ATTENDANCE_NOT_APPLICABLE' using errcode='22023'; end if; if not (p_args->>'p_segment'=any(v_booking.attendance_segments_snapshot)) then raise exception 'RESERVATIONS_ATTENDANCE_SEGMENT_INELIGIBLE' using errcode='22023'; end if;
  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; insert into reservations.attendance_records(scope_partition_id,booking_id,segment,attended,attendance_date,notes,created_by,updated_by) values(v_booking.scope_partition_id,v_booking.id,p_args->>'p_segment',(p_args->>'p_attended')::boolean,case when (p_args->>'p_attended')::boolean then coalesce((p_args->>'p_attendance_date')::date,current_date) end,nullif(p_args->>'p_notes',''),v_actor,v_actor) on conflict(booking_id,segment) do update set attended=excluded.attended,attendance_date=excluded.attendance_date,notes=excluded.notes,revision=reservations.attendance_records.revision+1,updated_at=statement_timestamp(),updated_by=v_actor returning id,revision into v_id,v_revision; v_result:=jsonb_build_object('attendanceId',v_id,'revision',v_revision,'attended',(p_args->>'p_attended')::boolean); perform reservations_private.audit(v_context,'attendance.corrected','attendance',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='update_operational_review' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_review_status']); v_context:=reservations_private.resolve_booking_scope(p_device_id,(p_args->>'p_booking_id')::uuid,'reservations.operations.manage'); v_actor:=(v_context->>'actorUserId')::uuid;
  select * into v_booking from reservations.bookings b where b.id=(v_context->>'bookingId')::uuid and b.scope_partition_id=(v_context->>'scopePartitionId')::uuid for update;
  if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND' using errcode='P0002'; end if;
  if v_booking.lifecycle_status<>'active' then raise exception 'RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE' using errcode='55000'; end if;
  select o.id,o.revision into v_id,v_revision from reservations.operational_reviews o where o.booking_id=(v_context->>'bookingId')::uuid and o.scope_partition_id=(v_context->>'scopePartitionId')::uuid for update; if not found then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if;
  update reservations.operational_reviews o set review_status=p_args->>'p_review_status',reviewed_at=case when p_args->>'p_review_status'='completed' then statement_timestamp() end,reviewed_by=case when p_args->>'p_review_status'='completed' then v_actor end,reviewed_by_device_id=case when p_args->>'p_review_status'='completed' then p_device_id end,revision=o.revision+1,updated_at=statement_timestamp(),updated_by=v_actor where o.id=v_id and o.booking_id=(v_context->>'bookingId')::uuid and o.scope_partition_id=(v_context->>'scopePartitionId')::uuid and o.revision=(p_args->>'p_expected_revision')::bigint returning o.id,o.revision into v_id,v_revision; if not found then raise exception 'RESERVATIONS_REVISION_CONFLICT' using errcode='40001'; end if; v_result:=jsonb_build_object('operationalReviewId',v_id,'revision',v_revision,'status',p_args->>'p_review_status'); perform reservations_private.audit(v_context,'operational_review.updated','operational_review',v_id,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 if p_operation='reorder_event_periods' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_period_ids']); v_context:=reservations_private.resolve_event_scope(p_device_id,(p_args->>'p_event_id')::uuid,'reservations.event.manage'); v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; if jsonb_typeof(p_args->'p_period_ids')<>'array' or (select count(*) from jsonb_array_elements_text(p_args->'p_period_ids'))<>(select count(*) from reservations.event_periods where event_id=(v_context->>'eventId')::uuid and scope_partition_id=(v_context->>'scopePartitionId')::uuid) or (select count(distinct value) from jsonb_array_elements_text(p_args->'p_period_ids') s(value))<>(select count(*) from jsonb_array_elements_text(p_args->'p_period_ids')) or exists(select 1 from jsonb_array_elements_text(p_args->'p_period_ids') x left join reservations.event_periods p on p.id=x::uuid and p.event_id=(v_context->>'eventId')::uuid and p.scope_partition_id=(v_context->>'scopePartitionId')::uuid where p.id is null) then raise exception 'RESERVATIONS_PERIOD_ORDER_INVALID' using errcode='22023'; end if; update reservations.event_periods p set display_order=x.ordinality-1,revision=p.revision+1,updated_at=statement_timestamp(),updated_by=(v_context->>'actorUserId')::uuid from jsonb_array_elements_text(p_args->'p_period_ids') with ordinality x(id,ordinality) where p.id=x.id::uuid and p.event_id=(v_context->>'eventId')::uuid and p.scope_partition_id=(v_context->>'scopePartitionId')::uuid; v_result:=jsonb_build_object('eventId',(v_context->>'eventId')::uuid,'reordered',true); perform reservations_private.audit(v_context,'event_periods.reordered','event',(v_context->>'eventId')::uuid,v_operation_id,null,v_result); return reservations_private.complete_operation(v_operation_id,v_context,p_operation,p_args,v_result);
 end if;
 raise exception 'RESERVATIONS_SCOPED_OPERATION_NOT_IMPLEMENTED' using errcode='0A000';
end $function$
;
