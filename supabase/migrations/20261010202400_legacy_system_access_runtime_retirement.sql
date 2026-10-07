-- Collapse legacy account mutation wrappers into the one device-guarded Platform path.
create or replace function public.device_guarded_manage_system_user(p_actor_device_id uuid,p_target_user_id uuid,p_operation_id uuid,p_action text,p_requested_value boolean default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor_id uuid; existing public.system_access_admin_operations%rowtype; result jsonb; target_status text;
begin
 if p_target_user_id is null or p_operation_id is null or p_action not in ('approve','block','unblock') or p_requested_value is not null then raise exception 'INVALID_SYSTEM_ACCESS_OPERATION' using errcode='22023'; end if;
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'SYSTEM_OWNER_REQUIRED' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('system-access-operation:'||p_operation_id::text,0));
 select * into existing from public.system_access_admin_operations where operation_id=p_operation_id;
 if found then
  if existing.actor_user_id=actor_id and existing.actor_device_id=p_actor_device_id and existing.target_user_id=p_target_user_id and existing.action=p_action and existing.requested_value is null then return existing.stored_result; end if;
  raise exception 'SYSTEM_ACCESS_OPERATION_MISMATCH' using errcode='22023';
 end if;
 target_status:=case p_action when 'block' then 'blocked' else 'approved' end;
 perform platform.set_account_status(p_target_user_id,target_status,'device_guarded_manage_system_user:'||p_action);
 result:=pg_catalog.jsonb_build_object('status',target_status,'userId',p_target_user_id);
 insert into public.system_access_admin_operations(operation_id,actor_user_id,actor_device_id,target_user_id,action,requested_value,result_status,stored_result)
 values(p_operation_id,actor_id,p_actor_device_id,p_target_user_id,p_action,null,target_status,result);
 return result;
end $$;
drop function if exists public.approve_system_user(uuid,boolean);
drop function if exists public.block_system_user(uuid);
drop function if exists public.unblock_system_user(uuid);
drop function if exists public.grant_system_role(uuid,text);
drop function if exists public.revoke_system_role(uuid,text);
drop function if exists public.get_my_device_authorization(uuid);
drop function if exists public.get_my_device_aware_system_access(uuid);
