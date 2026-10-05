begin;

-- P6C1 final reconciliation: Platform permissions are the only Conference
-- authorization authority. Remove every remaining Conference membership
-- consumer before the final membership-plane demolition.

drop trigger if exists conferences_add_owner_membership on public.conferences;
drop function if exists public.add_conference_owner_membership();

drop trigger if exists conference_locks_require_manager on public.conference_locks;
drop function if exists public.enforce_conference_lock_manager();

drop trigger if exists conferences_prevent_invalid_organization_change
  on public.conferences;
drop function if exists public.prevent_invalid_conference_organization_change();

-- Retain User Management as Platform account/Organization/device
-- administration, with no Conference membership scope or result contract.
create or replace function public.get_user_management_actor_capabilities(
  p_actor_device_id uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  actor_id uuid;
  system_owner boolean;
  organization_administrator boolean;
begin
  actor_id:=public.require_current_approved_device(p_actor_device_id);
  system_owner:=public.is_system_owner(actor_id);
  organization_administrator:=exists(
    select 1 from public.organization_members members
    where members.user_id=actor_id
      and members.role in ('organization_owner','organization_admin')
  );
  return pg_catalog.jsonb_build_object(
    'status','success',
    'canOpenUserManagement',system_owner or organization_administrator,
    'canViewAccount',system_owner,
    'canManageAccount',system_owner,
    'canViewOrganization',organization_administrator,
    'canManageOrganizationMembers',organization_administrator,
    'canManageOrganizationRoles',exists(
      select 1 from public.organization_members members
      where members.user_id=actor_id and members.role='organization_owner'),
    'canViewDevices',organization_administrator,
    'canManageDevices',organization_administrator
  );
end $$;

create or replace function public.search_user_management_users(
  p_actor_device_id uuid,p_query text default null,
  p_account_status text default null,p_limit integer default 50
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  actor_id uuid;
  system_owner boolean;
  normalized_query text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_query,'')));
  effective_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
  actor_id:=public.require_current_approved_device(p_actor_device_id);
  system_owner:=public.is_system_owner(actor_id);
  if p_account_status is not null
     and p_account_status not in ('pending','approved','blocked') then
    raise exception 'INVALID_ACCOUNT_STATUS' using errcode='22023';
  end if;
  return pg_catalog.jsonb_build_object(
    'status','success',
    'capabilities',public.get_user_management_actor_capabilities(p_actor_device_id)-'status',
    'users',coalesce((
      with scoped_users as (
        select users.id,users.email from auth.users users where system_owner
        union
        select users.id,users.email
        from public.organization_members actor_members
        join public.organization_members target_members
          on target_members.organization_id=actor_members.organization_id
        join auth.users users on users.id=target_members.user_id
        where actor_members.user_id=actor_id
          and actor_members.role in ('organization_owner','organization_admin')
      ), filtered as (
        select users.id,users.email from scoped_users users
        join public.system_user_access access on access.user_id=users.id
        left join public.profiles profiles on profiles.id=users.id
        where (p_account_status is null or access.account_status=p_account_status)
          and (normalized_query=''
            or pg_catalog.lower(coalesce(profiles.display_name,''))
              like '%'||normalized_query||'%'
            or pg_catalog.lower(coalesce(users.email,''))
              like '%'||normalized_query||'%')
        order by coalesce(profiles.display_name,users.email),users.id
        limit effective_limit
      )
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'userId',users.id,'displayName',profiles.display_name,
        'email',users.email,'accountStatus',access.account_status,
        'deviceCount',platform_private.canonical_device_count(users.id)
      ) order by coalesce(profiles.display_name,users.email),users.id)
      from filtered users
      join public.system_user_access access on access.user_id=users.id
      left join public.profiles profiles on profiles.id=users.id
    ),'[]'::jsonb)
  );
end $$;

create or replace function public.get_user_management_overview(
  p_actor_device_id uuid,p_target_user_id uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  actor_id uuid;
  system_owner boolean;
  target_user auth.users%rowtype;
  target_profile public.profiles%rowtype;
  target_access public.system_user_access%rowtype;
  target_in_scope boolean;
  device_organization_id uuid;
begin
  if p_target_user_id is null then
    raise exception 'TARGET_USER_REQUIRED' using errcode='22023';
  end if;
  actor_id:=public.require_current_approved_device(p_actor_device_id);
  system_owner:=public.is_system_owner(actor_id);
  target_in_scope:=system_owner or exists(
    select 1
    from public.organization_members actor_members
    join public.organization_members target_members
      on target_members.organization_id=actor_members.organization_id
    where actor_members.user_id=actor_id
      and target_members.user_id=p_target_user_id
      and actor_members.role in ('organization_owner','organization_admin')
  );
  if not target_in_scope then
    raise exception 'USER_MANAGEMENT_SCOPE_DENIED' using errcode='42501';
  end if;
  select * into target_user from auth.users users where users.id=p_target_user_id;
  if not found then raise exception 'TARGET_USER_NOT_FOUND' using errcode='P0002'; end if;
  select * into target_profile from public.profiles where id=p_target_user_id;
  select * into target_access
  from public.system_user_access where user_id=p_target_user_id;
  if not found then raise exception 'SYSTEM_ACCESS_NOT_FOUND' using errcode='P0002'; end if;
  select actor_members.organization_id into device_organization_id
  from public.organization_members actor_members
  join public.organization_members target_members
    on target_members.organization_id=actor_members.organization_id
   and target_members.user_id=p_target_user_id
  where actor_members.user_id=actor_id
    and actor_members.role in ('organization_owner','organization_admin')
    and (actor_members.role='organization_owner' or target_members.role='member')
  order by actor_members.created_at,actor_members.organization_id limit 1;
  return pg_catalog.jsonb_build_object(
    'status','success',
    'user',pg_catalog.jsonb_build_object(
      'userId',target_user.id,'displayName',target_profile.display_name,
      'email',target_user.email),
    'account',case when system_owner then pg_catalog.jsonb_build_object(
      'accountStatus',target_access.account_status,
      'canCreateConferences',target_access.can_create_conferences,
      'systemRoles',coalesce((select pg_catalog.jsonb_agg(roles.role order by roles.role)
        from public.system_user_roles roles
        where roles.user_id=p_target_user_id),'[]'::jsonb)) else null end,
    'organizations',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'organizationId',organizations.id,'organizationName',organizations.display_name,
      'isMember',target_members.user_id is not null,'role',target_members.role,
      'capabilities',pg_catalog.jsonb_build_object(
        'canAdd',target_members.user_id is null and target_access.account_status='approved',
        'canChangeRole',target_members.user_id is not null
          and actor_members.role='organization_owner' and p_target_user_id<>actor_id,
        'canRemove',target_members.user_id is not null and p_target_user_id<>actor_id
          and (actor_members.role='organization_owner' or target_members.role='member'))
      ) order by organizations.display_name,organizations.id)
      from public.organization_members actor_members
      join public.organizations organizations
        on organizations.id=actor_members.organization_id
      left join public.organization_members target_members
        on target_members.organization_id=organizations.id
       and target_members.user_id=p_target_user_id
      where actor_members.user_id=actor_id
        and actor_members.role in ('organization_owner','organization_admin')),'[]'::jsonb),
    'deviceOrganizationId',device_organization_id,
    'capabilities',pg_catalog.jsonb_build_object(
      'canViewAccount',system_owner,'canManageAccount',system_owner,
      'canViewOrganization',exists(select 1 from public.organization_members members
        where members.user_id=actor_id
          and members.role in ('organization_owner','organization_admin')),
      'canManageOrganizationMembers',exists(select 1 from public.organization_members members
        where members.user_id=actor_id
          and members.role in ('organization_owner','organization_admin')),
      'canManageOrganizationRoles',exists(select 1 from public.organization_members members
        where members.user_id=actor_id and members.role='organization_owner'),
      'canViewDevices',device_organization_id is not null,
      'canManageDevices',device_organization_id is not null)
  );
end $$;

revoke all on function public.get_user_management_actor_capabilities(uuid)
  from public,anon;
revoke all on function public.search_user_management_users(uuid,text,text,integer)
  from public,anon;
revoke all on function public.get_user_management_overview(uuid,uuid)
  from public,anon;
grant execute on function public.get_user_management_actor_capabilities(uuid)
  to authenticated;
grant execute on function public.search_user_management_users(uuid,text,text,integer)
  to authenticated;
grant execute on function public.get_user_management_overview(uuid,uuid)
  to authenticated;

-- Replace the legacy dispatcher core with only surviving final operations.
create or replace function platform.execute_conference_device_operation_phase1c_core(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,platform,platform_private as $$
declare v_session platform_private.device_sessions%rowtype; v_result jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'CONFERENCE_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_user_id is null or p_session_id is null or octet_length(p_token_hash)<>32 then
    raise exception 'DEVICE_SESSION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  select session.* into v_session from platform_private.device_sessions session
  join platform.device_key_bindings binding on binding.id=session.binding_id
  join platform.user_device_authorizations device_authorization
    on device_authorization.id=session.device_authorization_id
  join platform.devices device on device.id=session.device_id
  join platform.profiles profile on profile.user_id=session.user_id
  where session.id=p_session_id and session.user_id=p_user_id
    and session.token_hash=p_token_hash
    and session.revoked_at is null and session.expires_at>statement_timestamp()
    and binding.user_id=session.user_id and binding.device_id=session.device_id
    and binding.device_authorization_id=session.device_authorization_id
    and binding.public_key_thumbprint=session.public_key_thumbprint
    and binding.lifecycle_status='active' and binding.revoked_at is null
    and binding.retired_at is null
    and device_authorization.user_id=session.user_id
    and device_authorization.device_id=session.device_id
    and device_authorization.status='approved'
    and device_authorization.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved';
  if not found then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501'; end if;
  if p_args ? 'p_actor_device_id'
     or (p_args ? 'p_device_id' and p_operation<>'approve_pending_device_authorization') then
    raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='22023';
  end if;
  perform set_config('platform.phase1c_context',jsonb_build_object(
    'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',v_session.id,
    'user_id',v_session.user_id,'device_id',v_session.device_id,
    'authorization_id',v_session.device_authorization_id,
    'binding_id',v_session.binding_id,'token_hash',encode(p_token_hash,'hex'))::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',p_user_id,'role','authenticated')::text,true);

  case p_operation
  when 'device_guarded_list_my_organizations' then
    perform platform_private.require_exact_jsonb_keys(p_args,'{}');
    select coalesce(jsonb_agg(to_jsonb(result)),'[]') into v_result
    from public.device_guarded_list_my_organizations(v_session.device_id) result;
  when 'device_guarded_get_my_organization_access' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id']);
    v_result:=public.device_guarded_get_my_organization_access(v_session.device_id,(p_args->>'p_organization_id')::uuid);
  when 'device_guarded_list_organization_members' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id']);
    select coalesce(jsonb_agg(to_jsonb(result)),'[]') into v_result
    from public.device_guarded_list_organization_members(v_session.device_id,(p_args->>'p_organization_id')::uuid) result;
  when 'device_guarded_lookup_organization_candidate_by_email' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_email']);
    v_result:=public.device_guarded_lookup_organization_candidate_by_email(v_session.device_id,(p_args->>'p_organization_id')::uuid,p_args->>'p_email');
  when 'device_guarded_add_organization_member','device_guarded_remove_organization_member' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_target_user_id','p_operation_id']);
    if p_operation='device_guarded_add_organization_member' then
      v_result:=public.device_guarded_add_organization_member(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_operation_id')::uuid);
    else
      v_result:=public.device_guarded_remove_organization_member(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_operation_id')::uuid);
    end if;
  when 'device_guarded_change_organization_role' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_target_user_id','p_target_role','p_operation_id']);
    v_result:=public.device_guarded_change_organization_role(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid,p_args->>'p_target_role',(p_args->>'p_operation_id')::uuid);
  when 'device_guarded_get_organization_membership_operation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_operation_id']);
    v_result:=public.device_guarded_get_organization_membership_operation(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_operation_id')::uuid);
  when 'manage_organization' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_action','p_organization_id'],array['p_name','p_description']);
    v_result:=public.manage_organization(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',(p_args->>'p_organization_id')::uuid,p_args->>'p_name',p_args->>'p_description');
  when 'get_organization_management_overview' then
    perform platform_private.require_exact_jsonb_keys(p_args,'{}');
    v_result:=public.get_organization_management_overview(v_session.device_id);
  when 'get_user_management_actor_capabilities' then
    perform platform_private.require_exact_jsonb_keys(p_args,'{}');
    v_result:=public.get_user_management_actor_capabilities(v_session.device_id);
  when 'search_user_management_users' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_query','p_account_status','p_limit']);
    v_result:=public.search_user_management_users(v_session.device_id,p_args->>'p_query',p_args->>'p_account_status',(p_args->>'p_limit')::integer);
  when 'get_user_management_overview' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
    v_result:=public.get_user_management_overview(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
  when 'get_user_management_devices' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
    v_result:=public.get_user_management_devices(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
  when 'get_user_management_account' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
    v_result:=public.get_user_management_account(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
  when 'device_guarded_manage_system_user' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id','p_operation_id','p_action'],array['p_requested_value']);
    v_result:=public.device_guarded_manage_system_user(v_session.device_id,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',case when p_args ? 'p_requested_value' then (p_args->>'p_requested_value')::boolean else null end);
  when 'list_member_device_authorizations' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_target_user_id']);
    v_result:=public.list_member_device_authorizations(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid);
  when 'approve_member_device','reject_member_pending_device','revoke_member_device' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_target_user_id','p_device_id','p_operation_id']);
    if p_operation='approve_member_device' then v_result:=public.approve_member_device(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_device_id')::uuid,(p_args->>'p_operation_id')::uuid);
    elsif p_operation='reject_member_pending_device' then v_result:=public.reject_member_pending_device(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_device_id')::uuid,(p_args->>'p_operation_id')::uuid);
    else v_result:=public.revoke_member_device(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_device_id')::uuid,(p_args->>'p_operation_id')::uuid); end if;
  when 'replace_member_active_device' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_target_user_id','p_active_device_id','p_replacement_device_id','p_operation_id']);
    v_result:=public.replace_member_active_device(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_active_device_id')::uuid,(p_args->>'p_replacement_device_id')::uuid,(p_args->>'p_operation_id')::uuid);
  when 'list_pending_device_authorizations' then
    perform platform_private.require_exact_jsonb_keys(p_args,'{}');
    v_result:=platform.list_pending_device_authorizations();
  when 'approve_pending_device_authorization' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_authorization_id','p_device_id','p_reason']);
    v_result:=platform.approve_pending_device_authorization((p_args->>'p_authorization_id')::uuid,(p_args->>'p_device_id')::uuid,p_args->>'p_reason');
  when 'list_organization_templates' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id']);
    v_result:=public.list_organization_templates(v_session.device_id,(p_args->>'p_organization_id')::uuid);
  when 'list_shared_organization_templates' then
    perform platform_private.require_exact_jsonb_keys(p_args,'{}');
    v_result:=public.list_shared_organization_templates(v_session.device_id);
  when 'apply_organization_template_operation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_organization_id','p_operation_id','p_template_type','p_template_id','p_action','p_base_revision','p_payload']);
    v_result:=public.apply_organization_template_operation(v_session.device_id,(p_args->>'p_organization_id')::uuid,(p_args->>'p_operation_id')::uuid,p_args->>'p_template_type',p_args->>'p_template_id',p_args->>'p_action',(p_args->>'p_base_revision')::bigint,p_args->'p_payload');
  when 'apply_library_template_content_operation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_template_type','p_template_id','p_action','p_base_revision','p_payload']);
    v_result:=public.apply_library_template_content_operation(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_template_type',p_args->>'p_template_id',p_args->>'p_action',(p_args->>'p_base_revision')::bigint,p_args->'p_payload');
  when 'apply_organization_template_access_operation' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_template_type','p_template_id','p_organization_id','p_action']);
    v_result:=public.apply_organization_template_access_operation(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_template_type',p_args->>'p_template_id',(p_args->>'p_organization_id')::uuid,p_args->>'p_action');
  when 'list_module_permission_grants' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key','p_target_user_id']);
    v_result:=public.list_module_permission_grants(v_session.device_id,p_args->>'p_module_key',(p_args->>'p_target_user_id')::uuid);
  when 'manage_foundation_module_grant' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_action','p_target_user_id','p_module_key','p_permission_key','p_grant_id','p_revocation_reason']);
    v_result:=public.manage_foundation_module_grant(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',(p_args->>'p_target_user_id')::uuid,p_args->>'p_module_key',p_args->>'p_permission_key',(p_args->>'p_grant_id')::uuid,p_args->>'p_revocation_reason');
  when 'recover_revoke_final_module_manager' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_module_key','p_target_user_id','p_target_grant_id','p_recovery_reason']);
    v_result:=public.recover_revoke_final_module_manager(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_module_key',(p_args->>'p_target_user_id')::uuid,(p_args->>'p_target_grant_id')::uuid,p_args->>'p_recovery_reason');
  when 'acquire_conference_lock','renew_conference_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_lock_token','p_ttl_seconds']);
    if p_operation='acquire_conference_lock' then v_result:=public.device_guarded_acquire_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer);
    else v_result:=public.device_guarded_renew_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer); end if;
  when 'release_conference_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_lock_token']);
    v_result:=public.device_guarded_release_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_lock_token')::uuid);
  when 'get_conference_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
    v_result:=public.device_guarded_get_conference_lock(v_session.device_id,(p_args->>'p_conference_id')::uuid);
  when 'acquire_conference_section_lock','renew_conference_section_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_section','p_lock_token','p_ttl_seconds']);
    if p_operation='acquire_conference_section_lock' then v_result:=public.acquire_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer);
    else v_result:=public.renew_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id,(p_args->>'p_lock_token')::uuid,(p_args->>'p_ttl_seconds')::integer); end if;
  when 'release_conference_section_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_section','p_lock_token']);
    v_result:=public.release_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id,(p_args->>'p_lock_token')::uuid);
  when 'get_conference_section_lock' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_section']);
    v_result:=public.get_conference_section_lock((p_args->>'p_conference_id')::uuid,p_args->>'p_section',v_session.device_id);
  else raise exception 'CONFERENCE_OPERATION_NOT_ALLOWED' using errcode='42501';
  end case;
  return v_result;
end $$;

revoke all on function platform.execute_conference_device_operation_phase1c_core(
  uuid,uuid,bytea,text,jsonb
) from public,anon,authenticated,service_role;

-- Retire the obsolete creation, discovery, and adoption surfaces. No data is
-- migrated; old Conference membership and adoption data is irrelevant.
drop function if exists public.device_guarded_create_organization_conference_idempotent(uuid,uuid,uuid,uuid,text,jsonb);
drop function if exists public.create_organization_conference_idempotent(uuid,uuid,uuid,text,jsonb);
drop function if exists public.device_guarded_get_conference_creation_operation(uuid,uuid);
drop function if exists public.device_guarded_list_available_conferences(uuid);
drop function if exists public.device_guarded_list_eligible_legacy_conference_organizations(uuid,uuid);
drop function if exists public.device_guarded_assign_legacy_conference_organization(uuid,uuid,uuid,uuid);
drop table if exists public.legacy_conference_organization_assignments;

do $$
declare offender text;
begin
  select procedure.oid::regprocedure::text into offender
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid=procedure.pronamespace
  where namespace.nspname in ('public','platform','platform_private')
    and procedure.prokind='f'
    and procedure.proname not in ('is_conference_member','has_conference_role')
    and pg_get_functiondef(procedure.oid) ~* 'conference_members|is_conference_member|has_conference_role'
  order by procedure.oid::regprocedure::text limit 1;
  if offender is not null then
    raise exception 'FINAL_CONFERENCE_MEMBERSHIP_CONSUMER_REMAINS: %',offender
      using errcode='55000';
  end if;
  if exists(
    select 1 from pg_proc procedure
    join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname='public' and procedure.proname in (
      'add_conference_owner_membership','enforce_conference_lock_manager',
      'prevent_invalid_conference_organization_change',
      'device_guarded_create_organization_conference_idempotent',
      'create_organization_conference_idempotent',
      'device_guarded_get_conference_creation_operation',
      'device_guarded_list_available_conferences',
      'device_guarded_list_eligible_legacy_conference_organizations',
      'device_guarded_assign_legacy_conference_organization'
    )
  ) then
    raise exception 'RETIRED_CONFERENCE_SURFACE_REMAINS' using errcode='55000';
  end if;
end $$;

commit;
