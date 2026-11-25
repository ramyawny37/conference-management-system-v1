begin;

-- Canonical PostgREST gateway for the anonymous Edge Function.
-- reservations remains non-exposed; only service_role may execute this dispatcher.
create or replace function public.public_registration_gateway(
  p_operation text,
  p_args jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path=''
as $$
begin
  if p_operation='event' then
    if p_args is null or jsonb_typeof(p_args)<>'object'
       or (select array_agg(k order by k) from jsonb_object_keys(p_args) k) <> array['fingerprintDigest','publicId']::text[] then
      raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';
    end if;
    return reservations.public_registration_read(
      (p_args->>'publicId')::uuid,
      decode(replace(p_args->>'fingerprintDigest','\\x',''),'hex')
    );
  elsif p_operation='status' then
    if p_args is null or jsonb_typeof(p_args)<>'object'
       or (select array_agg(k order by k) from jsonb_object_keys(p_args) k) <> array['fingerprintDigest','publicId','trackingSecretDigest']::text[] then
      raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';
    end if;
    return reservations.public_registration_status(
      (p_args->>'publicId')::uuid,
      decode(replace(p_args->>'trackingSecretDigest','\\x',''),'hex'),
      decode(replace(p_args->>'fingerprintDigest','\\x',''),'hex')
    );
  elsif p_operation='submit' then
    if p_args is null or jsonb_typeof(p_args)<>'object'
       or (select array_agg(k order by k) from jsonb_object_keys(p_args) k) <>
          array['bookingTypeId','church','cityOrVillage','dateOfBirth','fingerprintDigest','fullName','gender','governorate','notes','phone','publicId','serviceSector','serviceSectorOther','submitOperationId','trackingSecretDigest']::text[] then
      raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';
    end if;
    return reservations.public_registration_submit(
      (p_args->>'publicId')::uuid,
      (p_args->>'submitOperationId')::uuid,
      decode(replace(p_args->>'trackingSecretDigest','\\x',''),'hex'),
      decode(replace(p_args->>'fingerprintDigest','\\x',''),'hex'),
      (p_args->>'bookingTypeId')::uuid,
      p_args->>'fullName',
      p_args->>'phone',
      p_args->>'gender',
      nullif(p_args->>'dateOfBirth','')::date,
      p_args->>'church',
      p_args->>'governorate',
      p_args->>'cityOrVillage',
      p_args->>'serviceSector',
      p_args->>'serviceSectorOther',
      p_args->>'notes'
    );
  end if;
  raise exception 'PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED' using errcode='22023';
end
$$;

revoke all on function public.public_registration_gateway(text,jsonb) from public,anon,authenticated;
grant execute on function public.public_registration_gateway(text,jsonb) to service_role;

commit;
