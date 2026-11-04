-- Protect manual Reservations person creation with an explicit, short-lived
-- identity decision. platform.people remains the only current-person store and
-- reservations_private.mutate_scoped remains the only booking writer.

create table reservations_private.manual_person_identity_challenges (
  token uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  device_id uuid not null,
  event_id uuid not null,
  input_profile jsonb not null,
  candidates jsonb not null check (jsonb_typeof(candidates)='array'),
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default statement_timestamp()+interval '10 minutes',
  unique(operation_id,device_id,event_id)
);

revoke all on reservations_private.manual_person_identity_challenges
  from public,anon,authenticated,service_role;

create or replace function platform_private.reservations_person_identity_candidates(
  p_full_name text,p_phone text,p_limit integer default 10
) returns jsonb
language sql stable security invoker set search_path=''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'personId',candidate.id,
    'fullName',candidate.full_name,
    'phone',candidate.phone,
    'gender',candidate.gender,
    'dateOfBirth',candidate.date_of_birth,
    'church',candidate.church,
    'governorate',candidate.governorate,
    'cityOrVillage',candidate.city_or_village,
    'serviceSector',candidate.service_sector,
    'serviceSectorOther',candidate.service_sector_other,
    'revision',candidate.revision,
    'matchedName',candidate.name_search=platform_private.person_name_key(p_full_name),
    'matchedPhone',nullif(platform_private.person_phone_key(p_phone),'') is not null
      and candidate.phone_search=platform_private.person_phone_key(p_phone)
  ) order by candidate.full_name,candidate.id),'[]'::jsonb)
  from (
    select person.*
    from platform.people person
    where (platform_private.person_name_key(p_full_name)<>''
           and person.name_search=platform_private.person_name_key(p_full_name))
       or (platform_private.person_phone_key(p_phone)<>''
           and person.phone_search=platform_private.person_phone_key(p_phone))
    order by person.full_name,person.id
    limit least(greatest(coalesce(p_limit,10),1),20)
  ) candidate
$function$;

revoke all on function platform_private.reservations_person_identity_candidates(text,text,integer)
  from public,anon,authenticated,service_role;

do $migration$
declare
  d text;
  old_text text;
  new_text text;
  create_keys_old text;
  create_keys_new text;
begin
  d:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);

  old_text:='v_count integer;';
  new_text:='v_count integer; v_identity_profile jsonb; v_identity_candidates jsonb; v_identity_challenge reservations_private.manual_person_identity_challenges%rowtype;';
  if (length(d)-length(replace(d,old_text,'')))/length(old_text)<>1 then
    raise exception 'RESERVATIONS_IDENTITY_DECLARATION_CONTRACT_DRIFT';
  end if;
  d:=replace(d,old_text,new_text);

  -- The current contract already treats canonical profile fields as optional.
  -- Add only the two challenge fields to the same create_booking validator.
  create_keys_old:='array[''p_person_id'',''p_person_update_revision'',''p_gender'',''p_date_of_birth'']';
  if position(create_keys_old in d)=0 then
    create_keys_old:='array[''p_person_id'',''p_person_update_revision'']';
  end if;
  if position(create_keys_old in d)=0 then
    create_keys_old:='array[''p_person_id'']';
  end if;
  if position(create_keys_old in d)=0 then
    raise exception 'RESERVATIONS_CREATE_BOOKING_OPTIONAL_KEYS_CONTRACT_DRIFT';
  end if;
  create_keys_new:=left(create_keys_old,length(create_keys_old)-1)
    ||',''p_identity_resolution_token'',''p_identity_resolution_decision'']';
  d:=replace(d,create_keys_old,create_keys_new);

  old_text:='v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; v_number:=reservations_private.allocate_booking_number';
  new_text:=$identity$
  -- Serialize identities sharing either normalized key. This closes the race
  -- between candidate discovery and canonical person creation across events.
  perform pg_advisory_xact_lock(hashtextextended('reservations-person-name:'||platform_private.person_name_key(p_args->>'p_full_name'),0));
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

  v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; v_number:=reservations_private.allocate_booking_number$identity$;
  if (length(d)-length(replace(d,old_text,'')))/length(old_text)<>1 then
    raise exception 'RESERVATIONS_IDENTITY_CREATE_ANCHOR_CONTRACT_DRIFT';
  end if;
  d:=replace(d,old_text,new_text);
  execute d;

  d:=pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
  create_keys_old:='array[''p_person_id'',''p_person_update_revision'',''p_gender'',''p_date_of_birth'']';
  if position(create_keys_old in d)=0 then create_keys_old:='array[''p_person_id'',''p_person_update_revision'']'; end if;
  if position(create_keys_old in d)=0 then create_keys_old:='array[''p_person_id'']'; end if;
  if position(create_keys_old in d)=0 then raise exception 'DEVICE_CREATE_BOOKING_OPTIONAL_KEYS_CONTRACT_DRIFT'; end if;
  create_keys_new:=left(create_keys_old,length(create_keys_old)-1)
    ||',''p_identity_resolution_token'',''p_identity_resolution_decision'']';
  execute replace(d,create_keys_old,create_keys_new);
end $migration$;

revoke all on function reservations_private.mutate_scoped(uuid,text,jsonb)
  from public,anon,authenticated;
revoke all on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  from public,anon,authenticated;
