CREATE OR REPLACE FUNCTION public.public_registration_gateway(p_operation text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if p_operation='event' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','publicId']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  return reservations.public_registration_read((p_args->>'publicId')::uuid,decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='status_family' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','publicId','trackingSecretDigest']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';end if;
  return reservations.public_registration_status_family((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='submit_family' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','members','publicId','submitOperationId','trackingSecretDigest']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';end if;
  return reservations.public_registration_submit_family((p_args->>'publicId')::uuid,(p_args->>'submitOperationId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'),p_args->'members');
 end if;
 raise exception 'PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED' using errcode='22023';
end $function$
;
