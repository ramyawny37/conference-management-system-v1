begin;
create or replace function public.public_registration_gateway(p_operation text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_operation='event' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','publicId']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  return reservations.public_registration_read((p_args->>'publicId')::uuid,decode(replace(p_args->>'fingerprintDigest','\\x',''),'hex'));
 elsif p_operation='status_family' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','publicId','trackingSecretDigest']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';end if;
  return reservations.public_registration_status_family((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest','\\x',''),'hex'),decode(replace(p_args->>'fingerprintDigest','\\x',''),'hex'));
 elsif p_operation='submit_family' then
  if p_args is null or jsonb_typeof(p_args)<>'object' or (select array_agg(k order by k) from jsonb_object_keys(p_args) k)<>array['fingerprintDigest','members','publicId','submitOperationId','trackingSecretDigest']::text[] then raise exception 'PUBLIC_REGISTRATION_ARGUMENT_INVALID' using errcode='22023';end if;
  return reservations.public_registration_submit_family((p_args->>'publicId')::uuid,(p_args->>'submitOperationId')::uuid,decode(replace(p_args->>'trackingSecretDigest','\\x',''),'hex'),decode(replace(p_args->>'fingerprintDigest','\\x',''),'hex'),p_args->'members');
 end if;
 raise exception 'PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED' using errcode='22023';
end $$;
revoke all on function public.public_registration_gateway(text,jsonb) from public,anon,authenticated;
grant execute on function public.public_registration_gateway(text,jsonb) to service_role;
drop function reservations.public_registration_submit(uuid,uuid,bytea,bytea,uuid,text,text,text,date,text,text,text,text,text,text);
commit;
