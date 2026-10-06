begin;
create or replace function platform_private.create_permission_grant(
 p_actor uuid,p_actor_device_id uuid,p_target uuid,p_module text,p_permission text,
 p_resource_type text default null,p_resource_id text default null,p_operation_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_permission_id uuid;v_id uuid;
begin
 if p_actor is null or p_target is null or p_module not in('conference','warehouse','reservations')
 or p_permission is null or ((p_resource_type is null)<>(p_resource_id is null)) then
  raise exception 'INVALID_PERMISSION_GRANT' using errcode='22023'; end if;
 if not exists(select 1 from platform.profiles where user_id=p_target and account_status='approved') then
  raise exception 'TARGET_ACCOUNT_APPROVED_REQUIRED' using errcode='42501'; end if;
 select id into v_permission_id from platform.permissions
 where domain=p_module and code=p_permission and status='active'
 and ((p_resource_type is null and allowed_scope_mode in('module','both'))
   or (p_resource_type is not null and allowed_scope_mode in('resource','both') and allowed_resource_type=p_resource_type));
 if v_permission_id is null then raise exception 'ACTIVE_PERMISSION_SCOPE_REQUIRED' using errcode='42501'; end if;
 select id into v_id from platform.permission_grants
 where user_id=p_target and permission_id=v_permission_id and revoked_at is null
 and ((p_resource_type is null and scope_type='module')
  or (p_resource_type is not null and scope_type='resource' and resource_type=p_resource_type and resource_id=p_resource_id));
 if v_id is null then
  insert into platform.permission_grants(user_id,permission_id,scope_type,resource_type,resource_id,granted_by,metadata)
  values(p_target,v_permission_id,case when p_resource_type is null then 'module' else 'resource' end,
   p_resource_type,p_resource_id,p_actor,
   jsonb_build_object('actorDeviceId',p_actor_device_id,'operationId',p_operation_id))
  returning id into v_id;
 end if;
 return v_id;
end $$;
revoke all on function platform_private.create_permission_grant(uuid,uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function platform_private.create_permission_grant(uuid,uuid,uuid,text,text,text,text,uuid) to service_role;
commit;