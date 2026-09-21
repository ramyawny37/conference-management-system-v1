begin;

-- Correct the canonical member-device authorization function prospectively.
-- Multi-device approval is additive: an existing approved device must not force
-- replacement. All actor, target, binding, revoke, replace, idempotency, audit,
-- and ledger invariants remain unchanged from the canonical authority function.
create or replace function platform_private.apply_member_device_authorization(
  p_action text,p_actor_device_id uuid,p_organization_id uuid,p_target_user_id uuid,
  p_device_id uuid,p_replacement_device_id uuid,p_operation_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); target_role text;
  existing public.device_authorization_admin_operations%rowtype;
  target platform.user_device_authorizations%rowtype;
  replacement platform.user_device_authorizations%rowtype;
  result jsonb; result_status text; operation_name text;
begin
  if p_action not in ('approve','reject','revoke','replace') or p_device_id is null
    or p_operation_id is null or (p_action='replace')<>(p_replacement_device_id is not null)
    or (p_action='replace' and p_device_id=p_replacement_device_id) then
    raise exception 'DEVICE_ADMINISTRATION_ARGUMENT_REQUIRED' using errcode='22023';
  end if;
  target_role:=public.require_device_authorization_manager(
    p_actor_device_id,p_organization_id,p_target_user_id);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'organization-membership:'||p_organization_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'platform-device-authorization-user:'||p_target_user_id::text,0));
  target_role:=public.require_device_authorization_manager(
    p_actor_device_id,p_organization_id,p_target_user_id);
  operation_name:=case p_action when 'approve' then 'approve_member_device'
    when 'reject' then 'reject_member_pending_device' when 'revoke' then 'revoke_member_device'
    else 'replace_member_active_device' end;
  select * into existing from public.device_authorization_admin_operations operation
  where operation.operation_id=p_operation_id;
  if found then
    if existing.actor_user_id_snapshot=actor_id and existing.actor_device_id=p_actor_device_id
      and existing.organization_id=p_organization_id
      and existing.target_user_id_snapshot=p_target_user_id
      and existing.device_id=p_device_id
      and existing.replacement_device_id is not distinct from p_replacement_device_id
      and existing.action=operation_name then return existing.stored_result; end if;
    raise exception 'DEVICE_ADMINISTRATION_OPERATION_MISMATCH' using errcode='22023';
  end if;
  select device_authorization.* into target from platform.user_device_authorizations device_authorization
  join platform.devices device on device.id=device_authorization.device_id
  where device_authorization.user_id=p_target_user_id and device_authorization.device_id=p_device_id
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null for update of device_authorization;
  if not found then raise exception 'DEVICE_AUTHORIZATION_NOT_FOUND' using errcode='P0002'; end if;
  if p_action in ('approve','reject') and (target.status<>'pending' or target.revoked_at is not null) then
    raise exception 'PENDING_UNREVOKED_DEVICE_REQUIRED' using errcode='42501';
  end if;
  if p_action='revoke' and (target.status<>'approved' or target.revoked_at is not null) then
    raise exception 'APPROVED_UNREVOKED_DEVICE_REQUIRED' using errcode='42501';
  end if;
  if p_action='revoke' and (
      target_role='organization_owner' or actor_id=p_target_user_id
      or platform_private.is_canonical_platform_owner(p_target_user_id)
    ) and (select count(*) from platform.user_device_authorizations approved
      join platform.devices device on device.id=approved.device_id
      where approved.user_id=p_target_user_id and approved.status='approved'
        and approved.revoked_at is null and device.lifecycle_status='active'
        and device.retired_at is null and device.compromised_at is null)<=1 then
    raise exception 'DEVICE_REVOCATION_REPLACEMENT_REQUIRED' using errcode='42501';
  end if;
  if p_action='approve' and (
      not exists(select 1 from platform.profiles profile
        where profile.user_id=p_target_user_id and profile.account_status='approved')
      or not exists(select 1 from platform.device_key_bindings binding
        where binding.user_id=p_target_user_id and binding.device_id=p_device_id
          and binding.device_authorization_id=target.id
          and binding.lifecycle_status='active' and binding.revoked_at is null
          and binding.retired_at is null)
    ) then
    raise exception 'DEVICE_APPROVAL_PRECONDITION_INVALID' using errcode='42501';
  end if;
  if p_action='replace' then
    select device_authorization.* into replacement from platform.user_device_authorizations device_authorization
    join platform.devices device on device.id=device_authorization.device_id
    where device_authorization.user_id=p_target_user_id
      and device_authorization.device_id=p_replacement_device_id
      and device.lifecycle_status='active' and device.retired_at is null
      and device.compromised_at is null for update of device_authorization;
    if target.status<>'approved' or target.revoked_at is not null
      or replacement.status is distinct from 'pending' or replacement.revoked_at is not null
      or (select count(*) from platform.user_device_authorizations approved
        join platform.devices device on device.id=approved.device_id
        where approved.user_id=p_target_user_id and approved.status='approved'
          and approved.revoked_at is null and device.lifecycle_status='active')<>1 then
      raise exception 'DEVICE_REPLACEMENT_PRECONDITION_INVALID' using errcode='42501';
    end if;
  end if;
  if p_action in ('reject','revoke','replace') then
    update platform.user_device_authorizations set status='revoked',revoked_at=pg_catalog.now(),
      revoked_by=actor_id where id=target.id;
  else
    update platform.user_device_authorizations set status='approved',approved_at=pg_catalog.now(),
      approved_by=actor_id,revoked_at=null,revoked_by=null where id=target.id;
  end if;
  if p_action='replace' then
    update platform.user_device_authorizations set status='approved',approved_at=pg_catalog.now(),
      approved_by=actor_id,revoked_at=null,revoked_by=null where id=replacement.id;
  end if;
  result_status:=case when p_action in ('approve','replace') then 'approved' else 'revoked' end;
  result:=case when p_action='replace' then pg_catalog.jsonb_build_object('status','applied',
    'organizationId',p_organization_id,'targetUserId',p_target_user_id,
    'revokedDeviceId',p_device_id,'approvedDeviceId',p_replacement_device_id)
  else pg_catalog.jsonb_build_object('status','applied','authorizationStatus',result_status,
    'organizationId',p_organization_id,'targetUserId',p_target_user_id,'deviceId',p_device_id) end;
  insert into public.device_authorization_audit_log(actor_user_id,target_user_id,device_id,
    action,operation_id,old_values,new_values)
  values(actor_id,p_target_user_id,p_device_id,
    case p_action when 'approve' then 'device_authorization_approved'
      when 'reject' then 'device_authorization_rejected' else 'device_authorization_revoked' end,
    p_operation_id,pg_catalog.jsonb_build_object('authorizationStatus',target.status),
    pg_catalog.jsonb_build_object('authorizationStatus',case when p_action='approve' then 'approved' else 'revoked' end,
      'organizationId',p_organization_id,'replacementDeviceId',p_replacement_device_id));
  if p_action='replace' then
    insert into public.device_authorization_audit_log(actor_user_id,target_user_id,device_id,
      action,operation_id,old_values,new_values)
    values(actor_id,p_target_user_id,p_replacement_device_id,'device_authorization_approved',
      p_operation_id,pg_catalog.jsonb_build_object('authorizationStatus','pending'),
      pg_catalog.jsonb_build_object('authorizationStatus','approved','organizationId',p_organization_id,
        'replacedDeviceId',p_device_id));
  end if;
  insert into public.device_authorization_admin_operations(operation_id,organization_id,
    actor_user_id,actor_user_id_snapshot,actor_device_id,target_user_id,target_user_id_snapshot,
    device_id,replacement_device_id,action,outcome,stored_result)
  values(p_operation_id,p_organization_id,actor_id,actor_id,p_actor_device_id,p_target_user_id,
    p_target_user_id,p_device_id,p_replacement_device_id,operation_name,'applied',result);
  return result;
end; $$;

-- This helper is private; preserve the canonical non-runtime execution boundary.
revoke all on function platform_private.apply_member_device_authorization(
  text,uuid,uuid,uuid,uuid,uuid,uuid
) from public,anon,authenticated,service_role;

commit;
