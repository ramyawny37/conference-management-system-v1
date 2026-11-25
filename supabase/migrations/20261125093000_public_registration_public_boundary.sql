begin;

-- PR2 narrow public read/submit/status boundary. Tables remain inaccessible.
alter table reservations.public_registration_requests
  add column submit_intent_digest bytea not null check(octet_length(submit_intent_digest)=32);

create table reservations.public_registration_rate_limits(
  channel_id uuid not null references reservations.public_registration_channels(id) on delete cascade,
  fingerprint_digest bytea not null check(octet_length(fingerprint_digest)=32),
  bucket_start timestamptz not null,
  request_count integer not null check(request_count>0),
  primary key(channel_id,fingerprint_digest,bucket_start)
);
alter table reservations.public_registration_rate_limits enable row level security;
alter table reservations.public_registration_rate_limits force row level security;
revoke all on reservations.public_registration_rate_limits from public,anon,authenticated,service_role;

create function reservations_private.public_registration_rate_limit(
  p_channel_id uuid,p_fingerprint_digest bytea,p_limit integer
) returns void language plpgsql volatile security definer set search_path='' as $$
declare v_bucket timestamptz:=date_trunc('minute',statement_timestamp()); v_count integer;
begin
 if p_fingerprint_digest is null or octet_length(p_fingerprint_digest)<>32 or p_limit<1 or p_limit>120 then
   raise exception 'PUBLIC_REGISTRATION_RATE_LIMIT_ARGUMENT_INVALID' using errcode='22023';
 end if;
 insert into reservations.public_registration_rate_limits(channel_id,fingerprint_digest,bucket_start,request_count)
 values(p_channel_id,p_fingerprint_digest,v_bucket,1)
 on conflict(channel_id,fingerprint_digest,bucket_start)
 do update set request_count=reservations.public_registration_rate_limits.request_count+1
 returning request_count into v_count;
 if v_count>p_limit then raise exception 'PUBLIC_REGISTRATION_RATE_LIMITED' using errcode='P0001'; end if;
 delete from reservations.public_registration_rate_limits
 where bucket_start<v_bucket-interval '10 minutes';
end $$;

create function reservations.public_registration_read(
  p_public_id uuid,p_fingerprint_digest bytea
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_channel reservations.public_registration_channels%rowtype; v_event reservations.events%rowtype;
begin
 select c.* into v_channel from reservations.public_registration_channels c where c.public_id=p_public_id;
 if not found or not v_channel.enabled then raise exception 'PUBLIC_REGISTRATION_UNAVAILABLE' using errcode='P0002'; end if;
 perform reservations_private.public_registration_rate_limit(v_channel.id,p_fingerprint_digest,60);
 if (v_channel.opens_at is not null and statement_timestamp()<v_channel.opens_at)
    or (v_channel.closes_at is not null and statement_timestamp()>=v_channel.closes_at) then
   raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001';
 end if;
 select e.* into v_event from reservations.events e where e.id=v_channel.event_id;
 if not found or v_event.status<>'open' then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001'; end if;
 return jsonb_build_object(
   'publicId',v_channel.public_id,'event',jsonb_build_object(
     'name',v_event.name,'startDate',v_event.start_date,'endDate',v_event.end_date,'location',v_event.location
   ),
   'bookingTypes',(select coalesce(jsonb_agg(jsonb_build_object(
     'id',bt.id,'name',bt.name,'price',bt.price,'eligibleAttendanceSegments',bt.eligible_attendance_segments
   ) order by bt.display_order,bt.id),'[]'::jsonb) from reservations.booking_types bt where bt.event_id=v_event.id and bt.active),
   'registrationMode',v_channel.registration_mode,'opensAt',v_channel.opens_at,'closesAt',v_channel.closes_at
 );
end $$;

create function reservations.public_registration_submit(
  p_public_id uuid,p_submit_operation_id uuid,p_tracking_secret_digest bytea,p_fingerprint_digest bytea,
  p_booking_type_id uuid,p_full_name text,p_phone text,p_gender text,p_date_of_birth date,
  p_church text,p_governorate text,p_city_or_village text,p_service_sector text,p_service_sector_other text,p_notes text
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
 v_channel reservations.public_registration_channels%rowtype; v_event reservations.events%rowtype;
 v_existing reservations.public_registration_requests%rowtype; v_request_id uuid:=extensions.gen_random_uuid();
 v_intent bytea; v_reference text;
begin
 if p_submit_operation_id is null or p_tracking_secret_digest is null or octet_length(p_tracking_secret_digest)<>32 then
   raise exception 'PUBLIC_REGISTRATION_SUBMISSION_INVALID' using errcode='22023'; end if;
 select c.* into v_channel from reservations.public_registration_channels c where c.public_id=p_public_id for key share;
 if not found or not v_channel.enabled then raise exception 'PUBLIC_REGISTRATION_UNAVAILABLE' using errcode='P0002'; end if;
 perform reservations_private.public_registration_rate_limit(v_channel.id,p_fingerprint_digest,8);
 if v_channel.registration_mode<>'approval_required'
    or (v_channel.opens_at is not null and statement_timestamp()<v_channel.opens_at)
    or (v_channel.closes_at is not null and statement_timestamp()>=v_channel.closes_at) then
   raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001'; end if;
 select e.* into v_event from reservations.events e where e.id=v_channel.event_id for key share;
 if not found or v_event.status<>'open' then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001'; end if;
 if not exists(select 1 from reservations.booking_types bt where bt.id=p_booking_type_id and bt.event_id=v_event.id and bt.active) then
   raise exception 'PUBLIC_REGISTRATION_BOOKING_TYPE_UNAVAILABLE' using errcode='22023'; end if;

 v_intent:=extensions.digest(convert_to(jsonb_build_object(
   'bookingTypeId',p_booking_type_id,'fullName',btrim(coalesce(p_full_name,'')),'phone',btrim(coalesce(p_phone,'')),
   'gender',p_gender,'dateOfBirth',p_date_of_birth,'church',coalesce(p_church,''),'governorate',coalesce(p_governorate,''),
   'cityOrVillage',coalesce(p_city_or_village,''),'serviceSector',coalesce(p_service_sector,''),
   'serviceSectorOther',p_service_sector_other,'notes',p_notes
 )::text,'UTF8'),'sha256');

 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-submit:'||v_channel.id::text||':'||p_submit_operation_id::text,0));
 select r.* into v_existing from reservations.public_registration_requests r
 where r.channel_id=v_channel.id and r.submit_operation_id=p_submit_operation_id;
 if found then
   if v_existing.submit_intent_digest<>v_intent or v_existing.tracking_secret_digest<>p_tracking_secret_digest then
     raise exception 'PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT' using errcode='40001'; end if;
   return jsonb_build_object('reference',v_existing.request_reference,'state',v_existing.state,'submittedAt',v_existing.submitted_at);
 end if;

 v_reference:='PR-'||upper(substr(replace(v_request_id::text,'-',''),1,12));
 insert into reservations.public_registration_requests(
   id,channel_id,event_id,submit_operation_id,submit_intent_digest,request_reference,tracking_secret_digest,booking_type_id,
   submitted_full_name,submitted_phone,submitted_gender,submitted_date_of_birth,submitted_church,submitted_governorate,
   submitted_city_or_village,submitted_service_sector,submitted_service_sector_other,submitted_notes
 ) values(
   v_request_id,v_channel.id,v_event.id,p_submit_operation_id,v_intent,v_reference,p_tracking_secret_digest,p_booking_type_id,
   btrim(p_full_name),btrim(p_phone),p_gender,p_date_of_birth,coalesce(p_church,''),coalesce(p_governorate,''),
   coalesce(p_city_or_village,''),coalesce(p_service_sector,''),p_service_sector_other,p_notes
 );
 return jsonb_build_object('reference',v_reference,'state','submitted','submittedAt',statement_timestamp());
end $$;

create function reservations.public_registration_status(
  p_public_id uuid,p_tracking_secret_digest bytea,p_fingerprint_digest bytea
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_channel reservations.public_registration_channels%rowtype; v_request reservations.public_registration_requests%rowtype; v_booking_number text;
begin
 select c.* into v_channel from reservations.public_registration_channels c where c.public_id=p_public_id;
 if not found then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002'; end if;
 perform reservations_private.public_registration_rate_limit(v_channel.id,p_fingerprint_digest,60);
 if p_tracking_secret_digest is null or octet_length(p_tracking_secret_digest)<>32 then
   raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002'; end if;
 select r.* into v_request from reservations.public_registration_requests r
 where r.channel_id=v_channel.id and r.tracking_secret_digest=p_tracking_secret_digest;
 if not found then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002'; end if;
 if v_request.booking_id is not null then
   select b.booking_number into v_booking_number from reservations.bookings b where b.id=v_request.booking_id;
 end if;
 return jsonb_strip_nulls(jsonb_build_object(
   'reference',v_request.request_reference,'state',v_request.state,'revision',v_request.revision,
   'submittedAt',v_request.submitted_at,'updatedAt',v_request.updated_at,'decisionReason',v_request.decision_reason,
   'bookingNumber',v_booking_number
 ));
end $$;

revoke all on function reservations_private.public_registration_rate_limit(uuid,bytea,integer) from public,anon,authenticated,service_role;
revoke all on function reservations.public_registration_read(uuid,bytea) from public,anon,authenticated;
revoke all on function reservations.public_registration_submit(uuid,uuid,bytea,bytea,uuid,text,text,text,date,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function reservations.public_registration_status(uuid,bytea,bytea) from public,anon,authenticated;
grant execute on function reservations.public_registration_read(uuid,bytea) to service_role;
grant execute on function reservations.public_registration_submit(uuid,uuid,bytea,bytea,uuid,text,text,text,date,text,text,text,text,text,text) to service_role;
grant execute on function reservations.public_registration_status(uuid,bytea,bytea) to service_role;

commit;
