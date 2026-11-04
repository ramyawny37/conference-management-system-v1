-- Browser startup account/role read from Platform canonical authority only.
create or replace function public.get_my_platform_system_access()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_user_id uuid:=auth.uid(); v_profile platform.profiles%rowtype;
begin
 if v_user_id is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select * into v_profile from platform.profiles where user_id=v_user_id;
 if not found then raise exception 'PLATFORM_PROFILE_NOT_FOUND' using errcode='P0002'; end if;
 return pg_catalog.jsonb_build_object(
  'userId',v_user_id,'accountStatus',v_profile.account_status,
  'systemRoles',coalesce((select pg_catalog.jsonb_agg(case r.code when 'platform_owner' then 'system_owner' when 'platform_admin' then 'system_admin' else r.code end order by r.code)
   from platform.user_roles a join platform.roles r on r.id=a.role_id
   where a.user_id=v_user_id and a.revoked_at is null and (a.expires_at is null or a.expires_at>pg_catalog.now())
    and r.domain='platform' and a.scope_type='platform' and a.scope_id is null),'[]'::jsonb),
  'checkedAt',pg_catalog.clock_timestamp());
end $$;
revoke all on function public.get_my_platform_system_access() from public,anon;
grant execute on function public.get_my_platform_system_access() to authenticated,service_role;
