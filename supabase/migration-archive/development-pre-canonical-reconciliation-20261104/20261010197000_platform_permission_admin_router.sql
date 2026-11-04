begin;
create or replace function platform_private.route_permission_administration(p_user_id uuid,p_operation text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d uuid;
begin
 d:=platform_private.phase1c_context_device_id();
 if d is null or platform_private.validated_phase1c_device_authorization(p_user_id,d) is null then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501'; end if;
 case p_operation
 when 'list_module_permission_grants' then return public.list_module_permission_grants(d,p_args->>'p_module_key',(p_args->>'p_target_user_id')::uuid);
 when 'search_module_permission_candidates' then return public.search_module_permission_candidates(d,p_args->>'p_module_key',p_args->>'p_query',coalesce((p_args->>'p_limit')::integer,50));
 when 'list_module_permission_catalog_for_administration' then return public.list_module_permission_catalog_for_administration(d,p_args->>'p_module_key');
 when 'list_module_permission_resources_for_administration' then return public.list_module_permission_resources_for_administration(d,p_args->>'p_module_key',p_args->>'p_resource_type');
 when 'manage_catalog_module_grant' then return public.manage_catalog_module_grant(d,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',(p_args->>'p_target_user_id')::uuid,p_args->>'p_module_key',p_args->>'p_permission_key',p_args->>'p_resource_type',p_args->>'p_resource_id',(p_args->>'p_grant_id')::uuid,p_args->>'p_revocation_reason');
 else raise exception 'PLATFORM_OPERATION_NOT_ALLOWED' using errcode='42501';
 end case;
end $$;
commit;