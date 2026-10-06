begin;
create or replace function public.manage_foundation_module_grant(p_actor_device_id uuid,p_operation_id uuid,p_action text,p_target_user_id uuid,p_module_key text,p_permission_key text,p_grant_id uuid default null,p_revocation_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$ begin raise exception 'PLATFORM_OPERATION_NOT_ALLOWED' using errcode='42501'; end $$;
create or replace function public.recover_revoke_final_module_manager(p_actor_device_id uuid,p_operation_id uuid,p_module_key text,p_target_user_id uuid,p_target_grant_id uuid,p_recovery_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$ begin raise exception 'PLATFORM_OPERATION_NOT_ALLOWED' using errcode='42501'; end $$;
commit;