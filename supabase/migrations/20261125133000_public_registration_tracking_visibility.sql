begin;
alter table reservations.public_registration_channels
 add column show_payment_status boolean not null default false,
 add column show_accommodation boolean not null default false;

create or replace function reservations_private.get_public_registration_settings(p_device_id uuid,p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c reservations.public_registration_channels%rowtype; v_context jsonb;
begin
 if p_event_id is null then raise exception 'PUBLIC_REGISTRATION_SETTINGS_ARGUMENT_INVALID' using errcode='22023'; end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create');
 select * into c from reservations.public_registration_channels where event_id=p_event_id;
 if not found then return jsonb_build_object('eventId',p_event_id,'configured',false,'enabled',false,'registrationMode','approval_required','fullPolicy','reject','opensAt',null,'closesAt',null,'showPaymentStatus',false,'showAccommodation',false,'revision',0); end if;
 return jsonb_build_object('eventId',c.event_id,'configured',true,'publicId',c.public_id,'enabled',c.enabled,'registrationMode',c.registration_mode,'fullPolicy',c.full_policy,'opensAt',c.opens_at,'closesAt',c.closes_at,'showPaymentStatus',c.show_payment_status,'showAccommodation',c.show_accommodation,'revision',c.revision);
end $$;

drop function reservations_private.update_public_registration_settings(uuid,uuid,uuid,bigint,boolean,text,text,timestamptz,timestamptz);
create function reservations_private.update_public_registration_settings(
 p_device_id uuid,p_operation_id uuid,p_event_id uuid,p_expected_revision bigint,p_enabled boolean,p_registration_mode text,p_full_policy text,
 p_opens_at timestamptz,p_closes_at timestamptz,p_show_payment_status boolean,p_show_accommodation boolean
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c reservations.public_registration_channels%rowtype; replay reservations.public_registration_channels%rowtype; v_context jsonb; v_actor uuid; v_intent bytea; v_result jsonb;
begin
 if p_device_id is null or p_operation_id is null or p_event_id is null or p_expected_revision is null or p_expected_revision<0 or p_enabled is null
 or p_registration_mode not in('approval_required','auto_approve') or p_full_policy not in('reject','waitlist') or p_show_payment_status is null or p_show_accommodation is null
 or (p_opens_at is not null and p_closes_at is not null and p_closes_at<=p_opens_at) then raise exception 'PUBLIC_REGISTRATION_SETTINGS_ARGUMENT_INVALID' using errcode='22023'; end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create'); v_actor:=(v_context->>'actorUserId')::uuid;
 v_intent:=extensions.digest(convert_to(jsonb_build_object('eventId',p_event_id,'expectedRevision',p_expected_revision,'enabled',p_enabled,'registrationMode',p_registration_mode,'fullPolicy',p_full_policy,'opensAt',p_opens_at,'closesAt',p_closes_at,'showPaymentStatus',p_show_payment_status,'showAccommodation',p_show_accommodation)::text,'UTF8'),'sha256');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-settings:'||p_operation_id::text,0));
 select * into replay from reservations.public_registration_channels where settings_operation_id=p_operation_id;
 if found then if replay.event_id<>p_event_id or replay.settings_intent_digest<>v_intent then raise exception 'PUBLIC_REGISTRATION_SETTINGS_IDEMPOTENCY_CONFLICT' using errcode='40001'; end if; return replay.settings_result; end if;
 select * into c from reservations.public_registration_channels where event_id=p_event_id for update;
 if not found then
  if p_expected_revision<>0 then raise exception 'PUBLIC_REGISTRATION_SETTINGS_REVISION_CONFLICT' using errcode='40001'; end if;
  insert into reservations.public_registration_channels(event_id,enabled,registration_mode,full_policy,opens_at,closes_at,show_payment_status,show_accommodation,created_by,updated_by,settings_operation_id,settings_intent_digest)
  values(p_event_id,p_enabled,p_registration_mode,p_full_policy,p_opens_at,p_closes_at,p_show_payment_status,p_show_accommodation,v_actor,v_actor,p_operation_id,v_intent) returning * into c;
 else
  if c.revision<>p_expected_revision then raise exception 'PUBLIC_REGISTRATION_SETTINGS_REVISION_CONFLICT' using errcode='40001'; end if;
  update reservations.public_registration_channels set enabled=p_enabled,registration_mode=p_registration_mode,full_policy=p_full_policy,opens_at=p_opens_at,closes_at=p_closes_at,
   show_payment_status=p_show_payment_status,show_accommodation=p_show_accommodation,revision=revision+1,updated_at=statement_timestamp(),updated_by=v_actor,settings_operation_id=p_operation_id,settings_intent_digest=v_intent
  where id=c.id returning * into c;
 end if;
 v_result:=jsonb_build_object('eventId',c.event_id,'configured',true,'publicId',c.public_id,'enabled',c.enabled,'registrationMode',c.registration_mode,'fullPolicy',c.full_policy,'opensAt',c.opens_at,'closesAt',c.closes_at,'showPaymentStatus',c.show_payment_status,'showAccommodation',c.show_accommodation,'revision',c.revision);
 update reservations.public_registration_channels set settings_result=v_result where id=c.id;
 perform reservations_private.audit(v_context,'public_registration.settings_updated','public_registration_channel',c.id,p_operation_id,null,v_result); return v_result;
end $$;
revoke all on function reservations_private.update_public_registration_settings(uuid,uuid,uuid,bigint,boolean,text,text,timestamptz,timestamptz,boolean,boolean) from public,anon,authenticated,service_role;

create or replace function reservations.public_registration_status(p_public_id uuid,p_tracking_secret_digest bytea,p_fingerprint_digest bytea)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_channel reservations.public_registration_channels%rowtype; v_request reservations.public_registration_requests%rowtype; v_booking reservations.bookings_operational%rowtype;
 v_paid numeric:=0; v_price numeric:=0; v_accommodation jsonb;
begin
 select c.* into v_channel from reservations.public_registration_channels c where c.public_id=p_public_id;
 if not found then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002'; end if;
 perform reservations_private.public_registration_rate_limit(v_channel.id,p_fingerprint_digest,60);
 if p_tracking_secret_digest is null or octet_length(p_tracking_secret_digest)<>32 then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002'; end if;
 select r.* into v_request from reservations.public_registration_requests r where r.channel_id=v_channel.id and r.tracking_secret_digest=p_tracking_secret_digest;
 if not found then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002'; end if;
 if v_request.booking_id is not null then
  select b.* into v_booking from reservations.bookings_operational b where b.id=v_request.booking_id and b.event_id=v_request.event_id;
  if v_channel.show_payment_status then
   select bt.price into v_price from reservations.booking_types bt where bt.id=v_booking.booking_type_id and bt.event_id=v_booking.event_id;
   select coalesce(sum(p.amount),0) into v_paid from reservations.payments p where p.booking_id=v_booking.id and p.status='active';
  end if;
  if v_channel.show_accommodation then
   select jsonb_strip_nulls(jsonb_build_object('assigned',o.id is not null,'roomNumber',room.room_number,'house',house.name,'floor',floor.name))
   into v_accommodation
   from reservations.events e join reservations.participants participant on participant.id=v_booking.participant_id and participant.scope_partition_id=v_booking.scope_partition_id
   left join public.conference_participations cp on cp.conference_id=e.conference_id and cp.person_id=participant.person_id
   left join lateral(select x.id,x.room_id from public.conference_accommodation_occupancies x where x.conference_id=e.conference_id and x.participation_id=cp.id order by x.arrival_day desc,x.id limit 1)o on true
   left join public.conference_accommodation_rooms room on room.id=o.room_id left join public.conference_accommodation_floors floor on floor.id=room.floor_id left join public.conference_accommodation_houses house on house.id=floor.house_id
   where e.id=v_booking.event_id;
   v_accommodation:=coalesce(v_accommodation,jsonb_build_object('assigned',false));
  end if;
 end if;
 return jsonb_strip_nulls(jsonb_build_object('reference',v_request.request_reference,'state',v_request.state,'revision',v_request.revision,'submittedAt',v_request.submitted_at,'updatedAt',v_request.updated_at,'decisionReason',v_request.decision_reason,
  'bookingNumber',case when v_request.booking_id is not null then v_booking.booking_number end,
  'financial',case when v_request.booking_id is not null and v_channel.show_payment_status then jsonb_build_object('price',v_price,'paid',v_paid,'remaining',greatest(v_price-v_paid,0)) end,
  'accommodation',case when v_request.booking_id is not null and v_channel.show_accommodation then v_accommodation end));
end $$;

do $patch$ declare v_oid oid:='platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure; d text; old text; new text;
begin select pg_get_functiondef(v_oid) into d;
 old:='return reservations_private.update_public_registration_settings(v_session.device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_event_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,(p_args->>''p_enabled'')::boolean,p_args->>''p_registration_mode'',p_args->>''p_full_policy'',nullif(p_args->>''p_opens_at'','''')::timestamptz,nullif(p_args->>''p_closes_at'','''')::timestamptz);';
 new:='return reservations_private.update_public_registration_settings(v_session.device_id,(p_args->>''p_operation_id'')::uuid,(p_args->>''p_event_id'')::uuid,(p_args->>''p_expected_revision'')::bigint,(p_args->>''p_enabled'')::boolean,p_args->>''p_registration_mode'',p_args->>''p_full_policy'',nullif(p_args->>''p_opens_at'','''')::timestamptz,nullif(p_args->>''p_closes_at'','''')::timestamptz,(p_args->>''p_show_payment_status'')::boolean,(p_args->>''p_show_accommodation'')::boolean);';
 if position(old in d)=0 then raise exception 'PUBLIC_REGISTRATION_VISIBILITY_DISPATCH_PRECONDITION_FAILED'; end if;
 d:=replace(d,'array[''p_operation_id'',''p_event_id'',''p_expected_revision'',''p_enabled'',''p_registration_mode'',''p_full_policy''],array[''p_opens_at'',''p_closes_at'']','array[''p_operation_id'',''p_event_id'',''p_expected_revision'',''p_enabled'',''p_registration_mode'',''p_full_policy'',''p_show_payment_status'',''p_show_accommodation''],array[''p_opens_at'',''p_closes_at'']');
 d:=replace(d,old,new); execute d;
end $patch$;
commit;
