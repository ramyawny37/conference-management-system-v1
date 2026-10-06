begin;
create or replace function platform.execute_device_operation_pre_reservations_authorization_reconci(
 p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_module text,p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer set search_path='pg_catalog','public','platform','platform_private' as $$
declare s platform_private.device_sessions%rowtype;
begin
 if p_module not in('conference','warehouse','reservations') or p_operation<>'check_module_access' then
  return platform.execute_device_operation_pre_module_entry_access_gate(p_user_id,p_session_id,p_token_hash,p_module,p_operation,p_args);
 end if;
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501'; end if;
 perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
 select x.* into s from platform_private.device_sessions x
 join platform.device_key_bindings b on b.id=x.binding_id
 join platform.user_device_authorizations a on a.id=x.device_authorization_id
 join platform.devices d on d.id=x.device_id join platform.profiles p on p.user_id=x.user_id
 where x.id=p_session_id and x.user_id=p_user_id and x.token_hash=p_token_hash and x.purpose='PLATFORM_DEVICE_SESSION'
 and x.revoked_at is null and x.expires_at>statement_timestamp() and b.lifecycle_status='active' and b.revoked_at is null and b.retired_at is null
 and a.status='approved' and a.revoked_at is null and d.lifecycle_status='active' and d.retired_at is null and d.compromised_at is null and p.account_status='approved';
 if not found then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user_id,'role','service_role')::text,true);
 perform public.require_effective_module_permission(s.device_id,p_module,p_module||'.module.access',null,null);
 return jsonb_build_object('status','allowed','moduleKey',p_module);
end $$;
commit;