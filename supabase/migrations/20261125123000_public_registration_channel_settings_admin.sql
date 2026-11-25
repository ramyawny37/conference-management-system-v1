begin;

alter table reservations.public_registration_channels
  add column settings_operation_id uuid,
  add column settings_intent_digest bytea check(settings_intent_digest is null or octet_length(settings_intent_digest)=32),
  add column settings_result jsonb;

create unique index public_registration_channels_settings_operation_uidx
  on reservations.public_registration_channels(settings_operation_id) where settings_operation_id is not null;

create function reservations_private.get_public_registration_settings(
  p_device_id uuid,p_event_id uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c reservations.public_registration_channels%rowtype; v_context jsonb;
begin
  if p_event_id is null then raise exception 'PUBLIC_REGISTRATION_SETTINGS_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create');
  select * into c from reservations.public_registration_channels where event_id=p_event_id;
  if not found then
    return jsonb_build_object('eventId',p_event_id,'configured',false,'enabled',false,'registrationMode','approval_required','fullPolicy','reject','opensAt',null,'closesAt',null,'revision',0);
  end if;
  return jsonb_build_object('eventId',c.event_id,'configured',true,'publicId',c.public_id,'enabled',c.enabled,
    'registrationMode',c.registration_mode,'fullPolicy',c.full_policy,'opensAt',c.opens_at,'closesAt',c.closes_at,'revision',c.revision);
end $$;

create function reservations_private.update_public_registration_settings(
  p_device_id uuid,p_operation_id uuid,p_event_id uuid,p_expected_revision bigint,
  p_enabled boolean,p_registration_mode text,p_full_policy text,p_opens_at timestamptz,p_closes_at timestamptz
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c reservations.public_registration_channels%rowtype; replay reservations.public_registration_channels%rowtype;
  v_context jsonb; v_actor uuid; v_intent bytea; v_result jsonb;
begin
  if p_device_id is null or p_operation_id is null or p_event_id is null or p_expected_revision is null or p_expected_revision<0
     or p_enabled is null or p_registration_mode not in('approval_required','auto_approve')
     or p_full_policy not in('reject','waitlist') or (p_opens_at is not null and p_closes_at is not null and p_closes_at<=p_opens_at)
  then raise exception 'PUBLIC_REGISTRATION_SETTINGS_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create');
  v_actor:=(v_context->>'actorUserId')::uuid;
  v_intent:=extensions.digest(convert_to(jsonb_build_object('eventId',p_event_id,'expectedRevision',p_expected_revision,
    'enabled',p_enabled,'registrationMode',p_registration_mode,'fullPolicy',p_full_policy,
    'opensAt',p_opens_at,'closesAt',p_closes_at)::text,'UTF8'),'sha256');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-settings:'||p_operation_id::text,0));
  select * into replay from reservations.public_registration_channels where settings_operation_id=p_operation_id;
  if found then
    if replay.event_id<>p_event_id or replay.settings_intent_digest<>v_intent then
      raise exception 'PUBLIC_REGISTRATION_SETTINGS_IDEMPOTENCY_CONFLICT' using errcode='40001'; end if;
    return replay.settings_result;
  end if;
  select * into c from reservations.public_registration_channels where event_id=p_event_id for update;
  if not found then
    if p_expected_revision<>0 then raise exception 'PUBLIC_REGISTRATION_SETTINGS_REVISION_CONFLICT' using errcode='40001'; end if;
    insert into reservations.public_registration_channels(event_id,enabled,registration_mode,full_policy,opens_at,closes_at,created_by,updated_by,
      settings_operation_id,settings_intent_digest)
    values(p_event_id,p_enabled,p_registration_mode,p_full_policy,p_opens_at,p_closes_at,v_actor,v_actor,p_operation_id,v_intent)
    returning * into c;
  else
    if c.revision<>p_expected_revision then raise exception 'PUBLIC_REGISTRATION_SETTINGS_REVISION_CONFLICT' using errcode='40001'; end if;
    update reservations.public_registration_channels set enabled=p_enabled,registration_mode=p_registration_mode,full_policy=p_full_policy,
      opens_at=p_opens_at,closes_at=p_closes_at,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor,
      settings_operation_id=p_operation_id,settings_intent_digest=v_intent
    where id=c.id returning * into c;
  end if;
  v_result:=jsonb_build_object('eventId',c.event_id,'configured',true,'publicId',c.public_id,'enabled',c.enabled,
    'registrationMode',c.registration_mode,'fullPolicy',c.full_policy,'opensAt',c.opens_at,'closesAt',c.closes_at,'revision',c.revision);
  update reservations.public_registration_channels set settings_result=v_result where id=c.id;
  perform reservations_private.audit(v_context,'public_registration.settings_updated','public_registration_channel',c.id,p_operation_id,null,v_result);
  return v_result;
end $$;

revoke all on function reservations_private.get_public_registration_settings(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function reservations_private.update_public_registration_settings(uuid,uuid,uuid,bigint,boolean,text,text,timestamptz,timestamptz) from public,anon,authenticated,service_role;

do $patch$
declare v_oid oid:='platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure;
 v_def text; v_new text; v_anchor text:=E'    case p_operation\n    when \'decide_public_registration_request\' then';
 v_insert text:=E'    case p_operation\n    when \'get_public_registration_settings\' then\n      perform platform_private.require_exact_jsonb_keys(p_args,array[\'p_event_id\']);\n      return reservations_private.get_public_registration_settings(v_session.device_id,(p_args->>\'p_event_id\')::uuid);\n    when \'update_public_registration_settings\' then\n      perform platform_private.require_exact_jsonb_keys(p_args,array[\'p_operation_id\',\'p_event_id\',\'p_expected_revision\',\'p_enabled\',\'p_registration_mode\',\'p_full_policy\'],array[\'p_opens_at\',\'p_closes_at\']);\n      return reservations_private.update_public_registration_settings(v_session.device_id,(p_args->>\'p_operation_id\')::uuid,(p_args->>\'p_event_id\')::uuid,(p_args->>\'p_expected_revision\')::bigint,(p_args->>\'p_enabled\')::boolean,p_args->>\'p_registration_mode\',p_args->>\'p_full_policy\',nullif(p_args->>\'p_opens_at\',\'\')::timestamptz,nullif(p_args->>\'p_closes_at\',\'\')::timestamptz);\n    when \'decide_public_registration_request\' then';
begin
 select pg_get_functiondef(v_oid) into v_def;
 if position('when ''get_public_registration_settings'' then' in v_def)>0 or position('when ''update_public_registration_settings'' then' in v_def)>0 then raise exception 'PUBLIC_REGISTRATION_SETTINGS_DISPATCH_ALREADY_PRESENT'; end if;
 if length(v_def)-length(replace(v_def,v_anchor,''))<>length(v_anchor) then raise exception 'PUBLIC_REGISTRATION_SETTINGS_DISPATCH_ANCHOR_MISMATCH'; end if;
 v_new:=replace(v_def,v_anchor,v_insert); execute v_new;
end $patch$;

commit;
