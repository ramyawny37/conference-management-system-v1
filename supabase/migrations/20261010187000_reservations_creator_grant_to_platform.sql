begin;
create or replace function platform_private.grant_deterministic_resource_permission(
 p_authorization_context jsonb,p_operation_id uuid,p_created_resource_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid;v_device uuid;v_verified jsonb;v_grant_id uuid;
begin
 if p_authorization_context is null or p_operation_id is null or p_created_resource_id is null
 or p_authorization_context->>'moduleKey'<>'reservations'
 or p_authorization_context->>'permissionKey'<>'reservations.event.create'
 then raise exception 'DETERMINISTIC_RESOURCE_GRANT_RULE_INVALID' using errcode='42501'; end if;
 v_actor:=nullif(p_authorization_context->>'actorUserId','')::uuid;
 v_device:=nullif(p_authorization_context->>'actorDeviceId','')::uuid;
 v_verified:=public.require_effective_module_permission(v_device,'reservations','reservations.event.create',null,null);
 if (v_verified->>'actorUserId')::uuid<>v_actor then raise exception 'DETERMINISTIC_RESOURCE_GRANT_CONTEXT_INVALID' using errcode='42501'; end if;
 v_grant_id:=platform_private.create_permission_grant(
   v_actor,v_device,v_actor,'reservations','reservations.event.manage','event',
   p_created_resource_id::text,p_operation_id);
 return jsonb_build_object('status','granted','grantId',v_grant_id,'targetUserId',v_actor,
   'moduleKey','reservations','permissionKey','reservations.event.manage',
   'resourceType','event','resourceId',p_created_resource_id,
   'authoritySource','business_rule','rule','resource_creator_ownership');
end $$;
revoke all on function platform_private.grant_deterministic_resource_permission(jsonb,uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function platform_private.grant_deterministic_resource_permission(jsonb,uuid,uuid) to service_role;
commit;