begin;
create or replace function public.list_module_permission_catalog_for_administration(p_actor_device_id uuid,p_module_key text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid;
begin
 v_actor:=public.require_current_approved_device(p_actor_device_id);
 if p_module_key not in('conference','warehouse','reservations') then raise exception 'ACTIVE_MODULE_REQUIRED' using errcode='42501'; end if;
 if not platform_private.is_canonical_platform_owner(v_actor) then
  perform public.require_effective_module_permission(p_actor_device_id,p_module_key,p_module_key||'.module.manage',null,null);
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'permissionKey',p.code,'displayName',p.code,'description',p.description,
  'allowedScopeMode',p.allowed_scope_mode,'allowedResourceType',p.allowed_resource_type,
  'sensitiveMutation',p.sensitive_mutation,'catalogVersion',1) order by p.code)
  from platform.permissions p where p.domain=p_module_key and p.status='active'
  and p.code not in(p_module_key||'.module.access',p_module_key||'.module.manage')),'[]'::jsonb);
end $$;

create or replace function public.list_module_permission_grants(p_actor_device_id uuid,p_module_key text,p_target_user_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid;v_target uuid;
begin
 v_actor:=public.require_current_approved_device(p_actor_device_id);v_target:=coalesce(p_target_user_id,v_actor);
 if p_module_key not in('conference','warehouse','reservations') then raise exception 'ACTIVE_MODULE_REQUIRED' using errcode='42501'; end if;
 if v_target<>v_actor and not platform_private.is_canonical_platform_owner(v_actor) then
  perform public.require_effective_module_permission(p_actor_device_id,p_module_key,p_module_key||'.module.manage',null,null);
 end if;
 return jsonb_build_object('status','success','targetUserId',v_target,'moduleKey',p_module_key,'grants',
 coalesce((select jsonb_agg(jsonb_build_object(
  'grantId',g.id,'permissionKey',p.code,'resourceType',g.resource_type,'resourceId',g.resource_id,
  'grantedAt',g.granted_at,'revokedAt',g.revoked_at) order by g.granted_at,g.id)
 from platform.permission_grants g join platform.permissions p on p.id=g.permission_id
 where g.user_id=v_target and p.domain=p_module_key),'[]'::jsonb));
end $$;
commit;