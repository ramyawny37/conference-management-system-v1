-- Move active User Management reads to Platform canonical account/role storage.

create or replace function public.get_user_management_actor_capabilities(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid;
begin
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'USER_MANAGEMENT_SCOPE_DENIED' using errcode='42501'; end if;
 return pg_catalog.jsonb_build_object('status','success','canOpenUserManagement',true,'canViewAccount',true,'canManageAccount',true,'canViewDevices',true,'canManageDevices',false);
end $$;

create or replace function public.search_user_management_users(p_actor_device_id uuid,p_query text default null,p_account_status text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid; normalized_query text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_query,''))); effective_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'USER_MANAGEMENT_SCOPE_DENIED' using errcode='42501'; end if;
 if p_account_status is not null and p_account_status not in('pending','approved','blocked') then raise exception 'INVALID_ACCOUNT_STATUS' using errcode='22023'; end if;
 return pg_catalog.jsonb_build_object('status','success','capabilities',public.get_user_management_actor_capabilities(p_actor_device_id)-'status','users',coalesce((
  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('userId',u.id,'displayName',p.display_name,'email',u.email,'accountStatus',p.account_status,'deviceCount',platform_private.canonical_device_count(u.id)) order by coalesce(p.display_name,u.email),u.id)
  from auth.users u join platform.profiles p on p.user_id=u.id
  where (p_account_status is null or p.account_status=p_account_status)
    and (normalized_query='' or pg_catalog.lower(coalesce(p.display_name,'')) like '%'||normalized_query||'%' or pg_catalog.lower(coalesce(u.email,'')) like '%'||normalized_query||'%')
  order by coalesce(p.display_name,u.email),u.id limit effective_limit
 ),'[]'::jsonb));
end $$;

create or replace function public.get_user_management_overview(p_actor_device_id uuid,p_target_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid; target_user auth.users%rowtype; target_profile platform.profiles%rowtype;
begin
 if p_target_user_id is null then raise exception 'TARGET_USER_REQUIRED' using errcode='22023'; end if;
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'USER_MANAGEMENT_SCOPE_DENIED' using errcode='42501'; end if;
 select * into target_user from auth.users where id=p_target_user_id;
 if not found then raise exception 'TARGET_USER_NOT_FOUND' using errcode='P0002'; end if;
 select * into target_profile from platform.profiles where user_id=p_target_user_id;
 if not found then raise exception 'PROFILE_NOT_FOUND' using errcode='P0002'; end if;
 return pg_catalog.jsonb_build_object('status','success','user',pg_catalog.jsonb_build_object('userId',target_user.id,'displayName',target_profile.display_name,'email',target_user.email),'account',pg_catalog.jsonb_build_object('accountStatus',target_profile.account_status),'capabilities',public.get_user_management_actor_capabilities(p_actor_device_id)-'status');
end $$;

create or replace function public.get_user_management_account(p_actor_device_id uuid,p_target_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid; target_profile platform.profiles%rowtype;
begin
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'SYSTEM_OWNER_REQUIRED' using errcode='42501'; end if;
 select * into target_profile from platform.profiles where user_id=p_target_user_id;
 if not found then raise exception 'PROFILE_NOT_FOUND' using errcode='P0002'; end if;
 return pg_catalog.jsonb_build_object('status','success','account',pg_catalog.jsonb_build_object(
   'accountStatus',target_profile.account_status,
   'systemRoles',coalesce((select pg_catalog.jsonb_agg(r.code order by r.code) from platform.user_roles a join platform.roles r on r.id=a.role_id where a.user_id=p_target_user_id and a.revoked_at is null and (a.expires_at is null or a.expires_at>pg_catalog.now()) and r.domain='platform' and a.scope_type='platform' and a.scope_id is null),'[]'::jsonb),
   'capabilities',pg_catalog.jsonb_build_object('canApprove',target_profile.account_status='pending','canBlock',target_profile.account_status='approved' and not public.is_system_owner(p_target_user_id),'canUnblock',target_profile.account_status='blocked')
 ));
end $$;
