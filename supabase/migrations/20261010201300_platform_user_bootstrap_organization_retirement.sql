begin;

-- User administration is platform/system-owner scoped after Organization retirement.
create or replace function public.get_user_management_actor_capabilities(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid;
begin
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'USER_MANAGEMENT_SCOPE_DENIED' using errcode='42501'; end if;
 return pg_catalog.jsonb_build_object('status','success','canOpenUserManagement',true,'canViewAccount',true,'canManageAccount',true,'canViewDevices',true,'canManageDevices',false);
end $$;

create or replace function public.search_user_management_users(p_actor_device_id uuid,p_query text default null,p_account_status text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid; normalized_query text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_query,''))); effective_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'USER_MANAGEMENT_SCOPE_DENIED' using errcode='42501'; end if;
 if p_account_status is not null and p_account_status not in('pending','approved','blocked') then raise exception 'INVALID_ACCOUNT_STATUS' using errcode='22023'; end if;
 return pg_catalog.jsonb_build_object('status','success','capabilities',public.get_user_management_actor_capabilities(p_actor_device_id)-'status','users',coalesce((
  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('userId',u.id,'displayName',p.display_name,'email',u.email,'accountStatus',a.account_status,'deviceCount',platform_private.canonical_device_count(u.id)) order by coalesce(p.display_name,u.email),u.id)
  from (select au.id,au.email from auth.users au join public.system_user_access sa on sa.user_id=au.id left join public.profiles pr on pr.id=au.id
        where (p_account_status is null or sa.account_status=p_account_status) and (normalized_query='' or pg_catalog.lower(coalesce(pr.display_name,'')) like '%'||normalized_query||'%' or pg_catalog.lower(coalesce(au.email,'')) like '%'||normalized_query||'%')
        order by coalesce(pr.display_name,au.email),au.id limit effective_limit) u
  join public.system_user_access a on a.user_id=u.id left join public.profiles p on p.id=u.id
 ),'[]'::jsonb));
end $$;

create or replace function public.get_user_management_overview(p_actor_device_id uuid,p_target_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid; target_user auth.users%rowtype; target_profile public.profiles%rowtype; target_access public.system_user_access%rowtype;
begin
 if p_target_user_id is null then raise exception 'TARGET_USER_REQUIRED' using errcode='22023'; end if;
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'USER_MANAGEMENT_SCOPE_DENIED' using errcode='42501'; end if;
 select * into target_user from auth.users where id=p_target_user_id; if not found then raise exception 'TARGET_USER_NOT_FOUND' using errcode='P0002'; end if;
 select * into target_profile from public.profiles where id=p_target_user_id;
 select * into target_access from public.system_user_access where user_id=p_target_user_id; if not found then raise exception 'SYSTEM_ACCESS_NOT_FOUND' using errcode='P0002'; end if;
 return pg_catalog.jsonb_build_object('status','success','user',pg_catalog.jsonb_build_object('userId',target_user.id,'displayName',target_profile.display_name,'email',target_user.email),'account',pg_catalog.jsonb_build_object('accountStatus',target_access.account_status),'capabilities',public.get_user_management_actor_capabilities(p_actor_device_id)-'status');
end $$;

create or replace function public.get_user_management_devices(p_actor_device_id uuid,p_target_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid;
begin
 if p_target_user_id is null then raise exception 'TARGET_USER_REQUIRED' using errcode='22023'; end if;
 actor_id:=public.require_current_approved_device(p_actor_device_id);
 if not public.is_system_owner(actor_id) then raise exception 'DEVICE_READ_SCOPE_DENIED' using errcode='42501'; end if;
 return pg_catalog.jsonb_build_object('status','success','devices',coalesce((
  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('deviceId',da.device_id,'deviceName',d.display_name,'platform',d.platform,'lastSeenAt',d.last_seen_at,'authorizationStatus',da.status,'requestedAt',da.requested_at,'approvedAt',da.approved_at,'revokedAt',da.revoked_at,'lastRegisteredAt',da.last_authorized_seen_at,'capabilities',pg_catalog.jsonb_build_object('canApprove',false,'canReject',false,'canRevoke',false)) order by da.created_at,da.device_id)
  from platform.user_device_authorizations da join platform.devices d on d.id=da.device_id where da.user_id=p_target_user_id
 ),'[]'::jsonb));
end $$;

alter table public.system_bootstrap_state drop constraint if exists system_bootstrap_state_check;
alter table public.system_bootstrap_state drop constraint if exists system_bootstrap_state_organization_id_fkey;
alter table public.system_bootstrap_state drop column if exists organization_id;
alter table public.system_bootstrap_state add constraint system_bootstrap_state_check check(
 ((completed_at is null) and (completed_by is null) and (device_id is null) and (operation_id is null) and (intent_hash is null) and (stored_result is null))
 or ((completed_at is not null) and (completed_by is not null) and (device_id is not null) and (operation_id is not null) and (intent_hash is not null) and (stored_result is not null))
);

drop function if exists public.complete_first_system_bootstrap(text,text,text,uuid,text,text,uuid);
create function public.complete_first_system_bootstrap(p_setup_token text,p_device_id uuid,p_device_name text,p_device_platform text,p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','extensions' as $$
declare actor_id uuid:=auth.uid(); state_row public.system_bootstrap_state%rowtype; secret_row public.system_bootstrap_secret%rowtype; intent text; result jsonb;
begin
 if actor_id is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if p_operation_id is null or p_device_id is null then raise exception 'INVALID_BOOTSTRAP_REQUEST' using errcode='22023'; end if;
 intent:=encode(extensions.digest(actor_id::text||'|'||p_device_id::text,'sha256'),'hex');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('first-system-bootstrap',0));
 select * into state_row from public.system_bootstrap_state where singleton_id=1 for update;
 if state_row.completed_at is not null then
  if state_row.completed_by=actor_id and state_row.operation_id=p_operation_id and state_row.intent_hash=intent then return state_row.stored_result; end if;
  raise exception 'BOOTSTRAP_ALREADY_COMPLETED' using errcode='42501';
 end if;
 if exists(select 1 from public.system_user_roles where role='system_owner') then raise exception 'SYSTEM_OWNER_ALREADY_EXISTS' using errcode='42501'; end if;
 select * into secret_row from public.system_bootstrap_secret where singleton_id=1 for update;
 if not found or secret_row.intended_user_id<>actor_id then raise exception 'BOOTSTRAP_IDENTITY_INVALID' using errcode='42501'; end if;
 if extensions.crypt(coalesce(p_setup_token,''),secret_row.secret_hash)<>secret_row.secret_hash then raise exception 'BOOTSTRAP_CREDENTIAL_INVALID' using errcode='42501'; end if;
 if not exists(select 1 from public.system_user_access where user_id=actor_id and account_status='pending') then raise exception 'PENDING_ACCOUNT_REQUIRED' using errcode='42501'; end if;
 update public.system_user_access set account_status='approved',approved_by=actor_id,approved_at=now(),blocked_by=null,blocked_at=null where user_id=actor_id;
 insert into public.system_user_roles(user_id,role,granted_by) values(actor_id,'system_owner',actor_id);
 insert into public.devices(id,user_id,device_name,platform,last_seen_at) values(p_device_id,actor_id,nullif(btrim(coalesce(p_device_name,'')),''),nullif(btrim(coalesce(p_device_platform,'')),''),now());
 insert into public.user_device_authorizations(user_id,device_id,authorization_status,approved_at,approved_by,last_registered_at) values(actor_id,p_device_id,'approved',now(),actor_id,now());
 insert into public.system_access_audit_log(actor_user_id,target_user_id,action,new_values) values(actor_id,actor_id,'first_system_owner_bootstrapped',jsonb_build_object('deviceId',p_device_id));
 insert into public.device_authorization_audit_log(actor_user_id,target_user_id,device_id,action,operation_id,new_values) values(actor_id,actor_id,p_device_id,'device_authorization_bootstrapped',p_operation_id,jsonb_build_object('source','first_system_bootstrap'));
 result:=jsonb_build_object('status','completed','deviceId',p_device_id,'operationId',p_operation_id);
 update public.system_bootstrap_state set completed_at=now(),completed_by=actor_id,device_id=p_device_id,operation_id=p_operation_id,intent_hash=intent,stored_result=result where singleton_id=1;
 delete from public.system_bootstrap_secret where singleton_id=1;
 return result;
end $$;
revoke all on function public.complete_first_system_bootstrap(text,uuid,text,text,uuid) from public,anon;
grant execute on function public.complete_first_system_bootstrap(text,uuid,text,text,uuid) to authenticated;

commit;
