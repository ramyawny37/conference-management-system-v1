begin;
create or replace function public.search_module_permission_candidates(p_actor_device_id uuid,p_module_key text,p_query text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid;v_query text:=lower(btrim(coalesce(p_query,'')));v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
 v_actor:=public.require_current_approved_device(p_actor_device_id);
 if p_module_key not in('conference','warehouse','reservations') then raise exception 'ACTIVE_MODULE_REQUIRED' using errcode='42501'; end if;
 if not platform_private.is_canonical_platform_owner(v_actor) then
  perform public.require_effective_module_permission(p_actor_device_id,p_module_key,p_module_key||'.module.manage',null,null);
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('userId',x.user_id,'displayName',x.display_name,'email',x.email,'accountStatus',x.account_status) order by coalesce(x.display_name,x.email),x.user_id)
 from (select p.user_id,p.display_name,u.email,p.account_status from platform.profiles p join auth.users u on u.id=p.user_id
 where p.account_status='approved' and (v_query='' or lower(coalesce(p.display_name,'')) like '%'||v_query||'%' or lower(coalesce(u.email,'')) like '%'||v_query||'%')
 order by coalesce(p.display_name,u.email),p.user_id limit v_limit) x),'[]'::jsonb);
end $$;

create or replace function public.list_module_permission_resources_for_administration(p_actor_device_id uuid,p_module_key text,p_resource_type text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid;
begin
 v_actor:=public.require_current_approved_device(p_actor_device_id);
 if not exists(select 1 from platform.permissions p where p.domain=p_module_key and p.status='active' and p.allowed_resource_type=p_resource_type and p.allowed_scope_mode in('resource','both')) then raise exception 'MODULE_PERMISSION_RESOURCE_TYPE_NOT_ALLOWED' using errcode='42501'; end if;
 if not platform_private.is_canonical_platform_owner(v_actor) then perform public.require_effective_module_permission(p_actor_device_id,p_module_key,p_module_key||'.module.manage',null,null); end if;
 if p_module_key='warehouse' and p_resource_type='store' then
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId',s.id,'resourceType','store','code',s.code,'name',s.name,'displayName',s.name,'status',s.status) order by s.code,s.id) from warehouse.stores s where s.status='active'),'[]'::jsonb);
 elsif p_module_key='reservations' and p_resource_type='event' then
  return coalesce((select jsonb_agg(jsonb_build_object('resourceId',e.id,'resourceType','event','code',null,'name',e.name,'displayName',e.name,'status',e.status) order by e.start_date desc,e.name,e.id) from reservations.events e where reservations_private.has_event_permission(v_actor,'reservations.event.manage',e.id)),'[]'::jsonb);
 end if;
 raise exception 'MODULE_PERMISSION_RESOURCE_DISCOVERY_UNSUPPORTED' using errcode='42501';
end $$;
commit;