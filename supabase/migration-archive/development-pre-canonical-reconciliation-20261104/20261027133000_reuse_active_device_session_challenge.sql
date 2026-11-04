-- Development: reuse only the authenticated user's existing unconsumed challenge for the same approved binding.
-- Lock the binding to serialize concurrent begin requests; signature verification remains mandatory.
create or replace function platform.begin_device_session_challenge(p_binding_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,platform,platform_private as $$
declare
  v_user uuid:=auth.uid();
  v_binding platform.device_key_bindings%rowtype;
  v_id uuid:=extensions.gen_random_uuid();
  v_nonce text;
  v_issued timestamptz:=statement_timestamp();
  v_expires timestamptz:=v_issued+interval '2 minutes';
  v_payload text;
  v_open platform_private.device_session_challenges%rowtype;
begin
  if v_user is null or p_binding_id is null then
    raise exception 'DEVICE_SESSION_AUTH_REQUIRED' using errcode='42501';
  end if;

  select binding.* into v_binding
  from platform.device_key_bindings binding
  join platform.user_device_authorizations device_authorization
    on device_authorization.id=binding.device_authorization_id
    and device_authorization.user_id=binding.user_id and device_authorization.device_id=binding.device_id
  join platform.devices device on device.id=binding.device_id
  join platform.profiles profile on profile.user_id=binding.user_id
  where binding.id=p_binding_id and binding.user_id=v_user
    and binding.lifecycle_status='active' and binding.revoked_at is null and binding.retired_at is null
    and binding.algorithm='ECDSA_P256_SHA256'
    and device_authorization.status='approved' and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null and device.compromised_at is null
    and profile.account_status='approved'
  for update of binding;
  if not found then raise exception 'DEVICE_SESSION_BINDING_INVALID' using errcode='42501'; end if;

  update platform_private.device_session_challenges challenge
  set failed_at=v_issued,failure_code='EXPIRED_REPLACED'
  where challenge.user_id=v_user and challenge.binding_id=p_binding_id
    and challenge.consumed_at is null and challenge.failed_at is null and challenge.expires_at<=v_issued;

  select challenge.* into v_open
  from platform_private.device_session_challenges challenge
  where challenge.user_id=v_user and challenge.binding_id=p_binding_id
    and challenge.consumed_at is null and challenge.failed_at is null
    and challenge.expires_at>v_issued
  order by challenge.issued_at desc limit 1;
  if found then
    return jsonb_build_object('challengeId',v_open.id,'userId',v_user,'deviceId',v_binding.device_id,
      'authorizationId',v_binding.device_authorization_id,'bindingId',v_binding.id,
      'publicKeyThumbprint',v_binding.public_key_thumbprint,'purpose',v_open.purpose,
      'origin',v_open.origin,'nonce',v_open.nonce,'issuedAt',v_open.issued_at,
      'expiresAt',v_open.expires_at,'signingPayload',v_open.signing_payload);
  end if;

  v_nonce:=translate(encode(extensions.gen_random_bytes(32),'base64'),E'+/\n','-_');
  v_payload:='PLATFORM_DEVICE_SESSION_ESTABLISH'||chr(10)||'v1'||chr(10)||v_id||chr(10)||v_user||chr(10)||
    v_binding.device_id||chr(10)||v_binding.device_authorization_id||chr(10)||v_binding.id||chr(10)||
    v_binding.public_key_thumbprint||chr(10)||v_nonce||chr(10)||
    to_char(v_issued at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')||chr(10)||
    to_char(v_expires at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')||chr(10)||
    'https://ramyawny37.github.io';

  insert into platform_private.device_session_challenges(id,user_id,device_id,device_authorization_id,binding_id,
    public_key_thumbprint,purpose,origin,nonce,signing_payload,signing_payload_hash,issued_at,expires_at)
  values(v_id,v_user,v_binding.device_id,v_binding.device_authorization_id,v_binding.id,v_binding.public_key_thumbprint,
    'PLATFORM_DEVICE_SESSION_ESTABLISH','https://ramyawny37.github.io',v_nonce,v_payload,
    extensions.digest(v_payload,'sha256'),v_issued,v_expires);

  return jsonb_build_object('challengeId',v_id,'userId',v_user,'deviceId',v_binding.device_id,
    'authorizationId',v_binding.device_authorization_id,'bindingId',v_binding.id,
    'publicKeyThumbprint',v_binding.public_key_thumbprint,'purpose','PLATFORM_DEVICE_SESSION_ESTABLISH',
    'origin','https://ramyawny37.github.io','nonce',v_nonce,'issuedAt',v_issued,'expiresAt',v_expires,
    'signingPayload',v_payload);
end;
$$;

