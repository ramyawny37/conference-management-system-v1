begin;
alter table reservations.public_registration_channels
  add column invite_image_path text null,
  add constraint public_registration_channels_invite_image_path_check
    check (invite_image_path is null or invite_image_path ~ '^[0-9a-f-]{36}/invite\.(jpg|jpeg|png|webp)$');

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('public-registration-invites','public-registration-invites',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

create or replace function reservations_private.get_public_registration_settings(p_device_id uuid,p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c reservations.public_registration_channels%rowtype; v_context jsonb;
begin
 if p_event_id is null then raise exception 'PUBLIC_REGISTRATION_SETTINGS_ARGUMENT_INVALID' using errcode='22023'; end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create');
 select * into c from reservations.public_registration_channels where event_id=p_event_id;
 if not found then return jsonb_build_object('eventId',p_event_id,'configured',false,'enabled',false,'registrationMode','approval_required','fullPolicy','reject','opensAt',null,'closesAt',null,'showPaymentStatus',false,'showAccommodation',false,'inviteImagePath',null,'revision',0); end if;
 return jsonb_build_object('eventId',c.event_id,'configured',true,'publicId',c.public_id,'enabled',c.enabled,'registrationMode',c.registration_mode,'fullPolicy',c.full_policy,'opensAt',c.opens_at,'closesAt',c.closes_at,'showPaymentStatus',c.show_payment_status,'showAccommodation',c.show_accommodation,'inviteImagePath',c.invite_image_path,'revision',c.revision);
end $$;

drop function reservations_private.update_public_registration_settings(uuid,uuid,uuid,bigint,boolean,text,text,timestamptz,timestamptz,boolean,boolean);
create function reservations_private.update_public_registration_settings(
 p_device_id uuid,p_operation_id uuid,p_event_id uuid,p_expected_revision bigint,p_enabled boolean,p_registration_mode text,p_full_policy text,
 p_opens_at timestamptz,p_closes_at timestamptz,p_show_payment_status boolean,p_show_accommodation boolean,p_invite_image_path text
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c reservations.public_registration_channels%rowtype; replay reservations.public_registration_channels%rowtype; v_context jsonb; v_actor uuid; v_intent bytea; v_result jsonb;
begin
 if p_device_id is null or p_operation_id is null or p_event_id is null or p_expected_revision is null or p_expected_revision<0 or p_enabled is null
 or p_registration_mode not in('approval_required','auto_approve') or p_full_policy not in('reject','waitlist') or p_show_payment_status is null or p_show_accommodation is null
 or (p_invite_image_path is not null and p_invite_image_path !~ '^[0-9a-f-]{36}/invite\.(jpg|jpeg|png|webp)$')
 or (p_opens_at is not null and p_closes_at is not null and p_closes_at<=p_opens_at) then raise exception 'PUBLIC_REGISTRATION_SETTINGS_ARGUMENT_INVALID' using errcode='22023'; end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create'); v_actor:=(v_context->>'actorUserId')::uuid;
 v_intent:=extensions.digest(convert_to(jsonb_build_object('eventId',p_event_id,'expectedRevision',p_expected_revision,'enabled',p_enabled,'registrationMode',p_registration_mode,'fullPolicy',p_full_policy,'opensAt',p_opens_at,'closesAt',p_closes_at,'showPaymentStatus',p_show_payment_status,'showAccommodation',p_show_accommodation,'inviteImagePath',p_invite_image_path)::text,'UTF8'),'sha256');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-settings:'||p_operation_id::text,0));
 select * into replay from reservations.public_registration_channels where settings_operation_id=p_operation_id;
 if found then if replay.event_id<>p_event_id or replay.settings_intent_digest<>v_intent then raise exception 'PUBLIC_REGISTRATION_SETTINGS_IDEMPOTENCY_CONFLICT' using errcode='40001'; end if; return replay.settings_result; end if;
 select * into c from reservations.public_registration_channels where event_id=p_event_id for update;
 if not found then
  if p_expected_revision<>0 then raise exception 'PUBLIC_REGISTRATION_SETTINGS_REVISION_CONFLICT' using errcode='40001'; end if;
  insert into reservations.public_registration_channels(event_id,enabled,registration_mode,full_policy,opens_at,closes_at,show_payment_status,show_accommodation,invite_image_path,created_by,updated_by,settings_operation_id,settings_intent_digest)
  values(p_event_id,p_enabled,p_registration_mode,p_full_policy,p_opens_at,p_closes_at,p_show_payment_status,p_show_accommodation,p_invite_image_path,v_actor,v_actor,p_operation_id,v_intent) returning * into c;
 else
  if c.revision<>p_expected_revision then raise exception 'PUBLIC_REGISTRATION_SETTINGS_REVISION_CONFLICT' using errcode='40001'; end if;
  update reservations.public_registration_channels set enabled=p_enabled,registration_mode=p_registration_mode,full_policy=p_full_policy,opens_at=p_opens_at,closes_at=p_closes_at,
   show_payment_status=p_show_payment_status,show_accommodation=p_show_accommodation,invite_image_path=p_invite_image_path,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor,settings_operation_id=p_operation_id,settings_intent_digest=v_intent
  where id=c.id returning * into c;
 end if;
 v_result:=jsonb_build_object('eventId',c.event_id,'configured',true,'publicId',c.public_id,'enabled',c.enabled,'registrationMode',c.registration_mode,'fullPolicy',c.full_policy,'opensAt',c.opens_at,'closesAt',c.closes_at,'showPaymentStatus',c.show_payment_status,'showAccommodation',c.show_accommodation,'inviteImagePath',c.invite_image_path,'revision',c.revision);
 update reservations.public_registration_channels set settings_result=v_result where id=c.id;
 perform reservations_private.audit(v_context,'public_registration.settings_updated','public_registration_channel',c.id,p_operation_id,null,v_result); return v_result;
end $$;
revoke all on function reservations_private.update_public_registration_settings(uuid,uuid,uuid,bigint,boolean,text,text,timestamptz,timestamptz,boolean,boolean,text) from public,anon,authenticated,service_role;

do $patch$ declare v_oid oid:='platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure; d text; old text; new text;
begin select pg_get_functiondef(v_oid) into d;
 old:='return reservations_private.update_public_registration_settings(v_session.device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_event_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,(p_args->>''p_enabled'')::boolean,p_args->>''p_registration_mode'',p_args->>''p_full_policy'',nullif(p_args->>''p_opens_at'','''')::timestamptz,nullif(p_args->>''p_closes_at'','''')::timestamptz,(p_args->>''p_show_payment_status'')::boolean,(p_args->>''p_show_accommodation'')::boolean);';
 new:='return reservations_private.update_public_registration_settings(v_session.device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_event_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,(p_args->>''p_enabled'')::boolean,p_args->>''p_registration_mode'',p_args->>''p_full_policy'',nullif(p_args->>''p_opens_at'','''')::timestamptz,nullif(p_args->>''p_closes_at'','''')::timestamptz,(p_args->>''p_show_payment_status'')::boolean,(p_args->>''p_show_accommodation'')::boolean,nullif(p_args->>''p_invite_image_path'',''''));';
 if position(old in d)=0 then raise exception 'PUBLIC_REGISTRATION_INVITE_DISPATCH_PRECONDITION_FAILED'; end if;
 d:=replace(d,'array[''p_operation_id'',''p_event_id'',''p_expected_revision'',''p_enabled'',''p_registration_mode'',''p_full_policy'',''p_show_payment_status'',''p_show_accommodation''],array[''p_opens_at'',''p_closes_at'']','array[''p_operation_id'',''p_event_id'',''p_expected_revision'',''p_enabled'',''p_registration_mode'',''p_full_policy'',''p_show_payment_status'',''p_show_accommodation''],array[''p_opens_at'',''p_closes_at'',''p_invite_image_path'']');
 d:=replace(d,old,new); execute d;
end $patch$;
commit;