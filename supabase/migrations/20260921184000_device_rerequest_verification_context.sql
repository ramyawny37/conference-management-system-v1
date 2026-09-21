create or replace function platform.get_device_key_rerequest_verification_context(p_user_id uuid, p_device_id uuid, p_binding_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'platform'
as $function$
declare
  v_result jsonb;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'DEVICE_REREQUEST_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_user_id is null or p_device_id is null or p_binding_id is null then
    raise exception 'DEVICE_REREQUEST_ARGUMENT_INVALID' using errcode='22023';
  end if;

  select jsonb_build_object(
    'bindingId', binding.id,
    'deviceId', binding.device_id,
    'authorizationId', binding.device_authorization_id,
    'publicKeyJwk', binding.public_key_jwk,
    'publicKeyThumbprint', binding.public_key_thumbprint,
    'algorithm', binding.algorithm,
    'bindingLifecycle', binding.lifecycle_status,
    'bindingRevoked', binding.revoked_at is not null,
    'bindingRetired', binding.retired_at is not null,
    'authorizationStatus', uda.status,
    'deviceLifecycle', device.lifecycle_status,
    'deviceRetired', device.retired_at is not null,
    'deviceCompromised', device.compromised_at is not null
  ) into v_result
  from platform.device_key_bindings binding
  join platform.user_device_authorizations uda on uda.id=binding.device_authorization_id
  join platform.devices device on device.id=binding.device_id
  where binding.id=p_binding_id
    and binding.user_id=p_user_id
    and binding.device_id=p_device_id
    and uda.user_id=p_user_id
    and uda.device_id=p_device_id;

  return coalesce(v_result,jsonb_build_object('status','missing'));
end;
$function$;

revoke all on function platform.get_device_key_rerequest_verification_context(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function platform.get_device_key_rerequest_verification_context(uuid,uuid,uuid) to service_role;
