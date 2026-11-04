-- Same-device authorization rerequest after proof of the existing active native key.

create table platform_private.device_authorization_rerequest_nonces (
  nonce text primary key check (nonce ~ '^[A-Za-z0-9_-]{43}$'),
  user_id uuid not null references platform.profiles(user_id) on delete restrict,
  device_id uuid not null references platform.devices(id) on delete restrict,
  device_authorization_id uuid not null references platform.user_device_authorizations(id) on delete restrict,
  binding_id uuid not null references platform.device_key_bindings(id) on delete restrict,
  requested_at timestamptz not null default statement_timestamp()
);
alter table platform_private.device_authorization_rerequest_nonces enable row level security;
alter table platform_private.device_authorization_rerequest_nonces force row level security;
revoke all on platform_private.device_authorization_rerequest_nonces from public,anon,authenticated,service_role;

create or replace function platform.rerequest_revoked_device_key(
  p_user_id uuid,p_device_id uuid,p_binding_id uuid,p_nonce text
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,platform,platform_private as $$
declare
  v_authorization platform.user_device_authorizations%rowtype;
  v_binding platform.device_key_bindings%rowtype;
  v_device platform.devices%rowtype;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'DEVICE_REREQUEST_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_user_id is null or p_device_id is null or p_binding_id is null
    or p_nonce !~ '^[A-Za-z0-9_-]{43}$' then
    raise exception 'DEVICE_REREQUEST_ARGUMENT_INVALID' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('device-rerequest:'||p_user_id::text||':'||p_device_id::text,0));
  select device_authorization.* into v_authorization
  from platform.user_device_authorizations device_authorization
  where device_authorization.user_id=p_user_id and device_authorization.device_id=p_device_id
  for update;
  if not found or v_authorization.status<>'revoked' then
    raise exception 'DEVICE_REREQUEST_REVOKED_AUTHORIZATION_REQUIRED' using errcode='42501';
  end if;

  select binding.* into v_binding from platform.device_key_bindings binding
  where binding.id=p_binding_id for update;
  if not found or v_binding.user_id<>p_user_id or v_binding.device_id<>p_device_id
    or v_binding.device_authorization_id<>v_authorization.id
    or v_binding.lifecycle_status<>'active' or v_binding.revoked_at is not null
    or v_binding.retired_at is not null then
    raise exception 'DEVICE_REREQUEST_ACTIVE_BINDING_REQUIRED' using errcode='42501';
  end if;

  select device.* into v_device from platform.devices device where device.id=p_device_id for update;
  if not found or v_device.lifecycle_status<>'active' or v_device.retired_at is not null
    or v_device.compromised_at is not null then
    raise exception 'DEVICE_REREQUEST_ACTIVE_DEVICE_REQUIRED' using errcode='42501';
  end if;
  if exists(select 1 from platform_private.device_authorization_rerequest_nonces where nonce=p_nonce) then
    raise exception 'DEVICE_REREQUEST_REPLAY_DENIED' using errcode='42501';
  end if;

  insert into platform_private.device_authorization_rerequest_nonces(
    nonce,user_id,device_id,device_authorization_id,binding_id
  ) values(p_nonce,p_user_id,p_device_id,v_authorization.id,p_binding_id);
  update platform.user_device_authorizations set
    status='pending',requested_at=statement_timestamp(),approved_by=null,approved_at=null,
    blocked_by=null,blocked_at=null,revoked_by=null,revoked_at=null,status_reason=null
  where id=v_authorization.id;
  insert into platform.audit_events(
    actor_user_id,subject_user_id,domain,module,action,entity_type,entity_id,scope_type,
    old_values,new_values,metadata,source
  ) values(
    p_user_id,p_user_id,'platform','devices','device_authorization.native_key_rerequested',
    'user_device_authorization',v_authorization.id,'platform',jsonb_build_object('status','revoked'),
    jsonb_build_object('status','pending'),jsonb_build_object(
      'deviceId',p_device_id,'authorizationId',v_authorization.id,'bindingId',p_binding_id,
      'publicKeyThumbprint',v_binding.public_key_thumbprint,'transition','revoked_to_pending',
      'proof','native_key_possession'),'system'
  );
  return jsonb_build_object(
    'deviceId',p_device_id,'authorizationId',v_authorization.id,'bindingId',p_binding_id,
    'publicKeyThumbprint',v_binding.public_key_thumbprint,'status','pending'
  );
end; $$;

revoke all on function platform.rerequest_revoked_device_key(uuid,uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function platform.rerequest_revoked_device_key(uuid,uuid,uuid,text) to service_role;
