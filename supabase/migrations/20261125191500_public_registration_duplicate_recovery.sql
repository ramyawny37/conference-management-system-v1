-- Canonical public-registration duplicate guard and secure recovery.
-- Reuses platform_private.person_phone_key; no parallel phone normalizer.

do $migration$
declare v_def text;
begin
 select pg_get_functiondef(p.oid) into v_def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='reservations' and p.proname='public_registration_submit_family'
 and pg_get_function_identity_arguments(p.oid)='p_public_id uuid, p_submit_operation_id uuid, p_tracking_secret_digest bytea, p_fingerprint_digest bytea, p_members jsonb';

 if v_def is null then raise exception 'PUBLIC_REGISTRATION_SUBMIT_FAMILY_NOT_FOUND'; end if;
 if position('PUBLIC_REGISTRATION_ALREADY_EXISTS' in v_def)>0 then return; end if;

 v_def:=replace(v_def,
 $$ v_intent:=extensions.digest(convert_to(p_members::text,'UTF8'),'sha256');$$,
 $$ if nullif(btrim(v_primary->>'phone'),'') is null then raise exception 'PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED' using errcode='22023';end if;
 v_intent:=extensions.digest(convert_to(p_members::text,'UTF8'),'sha256');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'public-registration-identity:'||v_event.id::text||':'||
   platform_private.person_phone_key(v_primary->>'phone')||':'||(v_primary->>'dateOfBirth'),0));
 if exists(
   select 1 from reservations.public_registration_requests r
   left join reservations.bookings b on b.id=r.booking_id
   where r.event_id=v_event.id
     and platform_private.person_phone_key(r.submitted_phone)=platform_private.person_phone_key(v_primary->>'phone')
     and r.submitted_date_of_birth=(v_primary->>'dateOfBirth')::date
     and (
       r.state in('submitted','under_review')
       or (r.state='approved' and b.lifecycle_status='active')
     )
 ) then raise exception 'PUBLIC_REGISTRATION_ALREADY_EXISTS' using errcode='23505';end if;
 v_intent:=extensions.digest(convert_to(p_members::text,'UTF8'),'sha256');$$);

 if v_def not like '%PUBLIC_REGISTRATION_ALREADY_EXISTS%' then raise exception 'PUBLIC_REGISTRATION_DUPLICATE_GUARD_PATCH_FAILED'; end if;
 execute v_def;
end $migration$;

create or replace function reservations.public_registration_recover_family(
 p_public_id uuid,p_request_reference text,p_phone text,p_date_of_birth date,
 p_new_tracking_secret_digest bytea,p_fingerprint_digest bytea
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare v_channel reservations.public_registration_channels%rowtype;
 v_request reservations.public_registration_requests%rowtype;
begin
 if nullif(btrim(p_request_reference),'') is null or nullif(btrim(p_phone),'') is null
    or p_date_of_birth is null or p_new_tracking_secret_digest is null
    or octet_length(p_new_tracking_secret_digest)<>32 then
   raise exception 'PUBLIC_REGISTRATION_RECOVERY_INVALID' using errcode='22023';
 end if;
 select * into v_channel from reservations.public_registration_channels
 where public_id=p_public_id and enabled for key share;
 if not found then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002';end if;
 perform reservations_private.public_registration_rate_limit(v_channel.id,p_fingerprint_digest,8);
 select * into v_request from reservations.public_registration_requests
 where channel_id=v_channel.id
   and upper(request_reference)=upper(btrim(p_request_reference))
   and platform_private.person_phone_key(submitted_phone)=platform_private.person_phone_key(p_phone)
   and submitted_date_of_birth=p_date_of_birth
 for update;
 if not found then raise exception 'PUBLIC_REGISTRATION_RECOVERY_NOT_FOUND' using errcode='P0002';end if;
 update reservations.public_registration_requests
 set tracking_secret_digest=p_new_tracking_secret_digest,updated_at=statement_timestamp()
 where id=v_request.id;
 return jsonb_build_object('reference',v_request.request_reference,'state',v_request.state,'eventId',v_request.event_id);
end $function$;

revoke all on function reservations.public_registration_recover_family(uuid,text,text,date,bytea,bytea) from public,anon,authenticated;
grant execute on function reservations.public_registration_recover_family(uuid,text,text,date,bytea,bytea) to service_role;

create or replace function public.public_registration_gateway(p_operation text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
 if p_operation='event' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','publicId']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  return reservations.public_registration_read((p_args->>'publicId')::uuid,decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='status_family' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','publicId','trackingSecretDigest']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';end if;
  return reservations.public_registration_status_family((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='recover_family' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['dateOfBirth','fingerprintDigest','newTrackingSecretDigest','phone','publicId','requestReference']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';end if;
  return reservations.public_registration_recover_family((p_args->>'publicId')::uuid,p_args->>'requestReference',p_args->>'phone',(p_args->>'dateOfBirth')::date,decode(replace(p_args->>'newTrackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='submit_family' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','members','publicId','submitOperationId','trackingSecretDigest']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';end if;
  return reservations.public_registration_submit_family((p_args->>'publicId')::uuid,(p_args->>'submitOperationId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'),p_args->'members');
 end if;
 raise exception 'PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED' using errcode='22023';
end $function$;

revoke all on function public.public_registration_gateway(text,jsonb) from public,anon,authenticated;
grant execute on function public.public_registration_gateway(text,jsonb) to service_role;
