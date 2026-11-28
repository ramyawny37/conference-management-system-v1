begin;

create or replace function reservations.public_registration_get_push_subscription_state(
 p_public_id uuid,
 p_tracking_secret_digest bytea,
 p_endpoint text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
 v_request_id uuid;
 v_active boolean:=false;
begin
 if char_length(coalesce(p_endpoint,'')) not between 20 and 4096 then
  raise exception 'PUBLIC_REGISTRATION_PUSH_SUBSCRIPTION_INVALID' using errcode='22023';
 end if;
 select r.id into v_request_id
 from reservations.public_registration_requests r
 join reservations.public_registration_channels c on c.id=r.channel_id
 where c.public_id=p_public_id
   and r.tracking_secret_digest=p_tracking_secret_digest;
 if v_request_id is null then
  raise exception 'PUBLIC_REGISTRATION_TRACKING_INVALID' using errcode='42501';
 end if;
 select exists(
  select 1
  from platform.notification_applicant_push_subscriptions s
  where s.request_id=v_request_id
    and s.endpoint=p_endpoint
    and s.active
 ) into v_active;
 return jsonb_build_object('active',v_active);
end
$function$;

revoke all on function reservations.public_registration_get_push_subscription_state(uuid,bytea,text)
 from public,anon,authenticated,service_role;

create or replace function public.public_registration_gateway(p_operation text,p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
begin
 if p_operation='event' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','publicId']);
  return reservations.public_registration_read((p_args->>'publicId')::uuid,decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='status_family' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','publicId','trackingSecretDigest']);
  return reservations.public_registration_status_family((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='recover_family' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['dateOfBirth','fingerprintDigest','fullName','newTrackingSecretDigest','phone','publicId']);
  return reservations.public_registration_recover_family((p_args->>'publicId')::uuid,p_args->>'fullName',p_args->>'phone',(p_args->>'dateOfBirth')::date,decode(replace(p_args->>'newTrackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='submit_family' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','members','publicId','submitOperationId','trackingSecretDigest']);
  return reservations.public_registration_submit_family((p_args->>'publicId')::uuid,(p_args->>'submitOperationId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'),p_args->'members');
 elsif p_operation='add_family_member' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','member','operationId','publicId','trackingSecretDigest']);
  return reservations.public_registration_add_family_member((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'),(p_args->>'operationId')::uuid,p_args->'member');
 elsif p_operation='push_subscription_state' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['endpoint','publicId','trackingSecretDigest']);
  return reservations.public_registration_get_push_subscription_state((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),p_args->>'endpoint');
 elsif p_operation='upsert_push_subscription' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['auth','endpoint','p256dh','publicId','trackingSecretDigest','userAgent']);
  return reservations.public_registration_upsert_push_subscription((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),p_args->>'endpoint',p_args->>'p256dh',p_args->>'auth',p_args->>'userAgent');
 elsif p_operation='disable_push_subscription' then
  perform platform_private.require_exact_jsonb_keys(p_args,array['endpoint','publicId','trackingSecretDigest']);
  return reservations.public_registration_disable_push_subscription((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),p_args->>'endpoint');
 end if;
 raise exception 'PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED' using errcode='22023';
end
$function$;

revoke all on function public.public_registration_gateway(text,jsonb) from public,anon,authenticated;
grant execute on function public.public_registration_gateway(text,jsonb) to service_role;

commit;
