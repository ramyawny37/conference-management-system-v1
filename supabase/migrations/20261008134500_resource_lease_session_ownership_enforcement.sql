begin;
create or replace function platform_private.acquire_resource_lease(
 p_actor_device_id uuid,p_module_id text,p_resource_type text,p_resource_id text,p_scope text,p_lease_token uuid,p_ttl_seconds integer default 120
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid; ttl integer:=coalesce(p_ttl_seconds,120); now_at timestamptz:=clock_timestamp(); exp_at timestamptz; current platform.resource_leases%rowtype;
begin
 if p_lease_token is null or ttl<30 or ttl>300 then raise exception 'PLATFORM_RESOURCE_LEASE_ARGUMENT_INVALID' using errcode='22023'; end if;
 actor_id:=platform_private.require_resource_lease_writer(p_actor_device_id,p_module_id,p_resource_type,p_resource_id,p_scope);
 perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',p_module_id,p_resource_type,p_resource_id,p_scope),0));
 select * into current from platform.resource_leases where module_id=p_module_id and resource_type=p_resource_type and resource_id=p_resource_id and scope=p_scope for update;
 exp_at:=now_at+make_interval(secs=>ttl);
 if not found or current.expires_at<=now_at then
   insert into platform.resource_leases(module_id,resource_type,resource_id,scope,holder_user_id,holder_device_id,lease_token,acquired_at,renewed_at,expires_at)
   values(p_module_id,p_resource_type,p_resource_id,p_scope,actor_id,p_actor_device_id,p_lease_token,now_at,now_at,exp_at)
   on conflict(module_id,resource_type,resource_id,scope) do update set holder_user_id=excluded.holder_user_id,holder_device_id=excluded.holder_device_id,lease_token=excluded.lease_token,acquired_at=excluded.acquired_at,renewed_at=excluded.renewed_at,expires_at=excluded.expires_at;
   return jsonb_build_object('status','acquired','owned',true,'moduleId',p_module_id,'resourceType',p_resource_type,'resourceId',p_resource_id,'scope',p_scope,'leaseToken',p_lease_token,'expiresAt',exp_at,'serverNow',now_at);
 end if;
 if current.holder_user_id=actor_id and current.holder_device_id=p_actor_device_id and platform_private.resource_lease_session_owner(p_actor_device_id,current.holder_session_id) then
   return jsonb_build_object('status','already_owned','owned',true,'moduleId',p_module_id,'resourceType',p_resource_type,'resourceId',p_resource_id,'scope',p_scope,'leaseToken',current.lease_token,'expiresAt',current.expires_at,'serverNow',now_at);
 end if;
 return jsonb_build_object('status','locked','owned',false,'errorCode','RESOURCE_LEASE_HELD','moduleId',p_module_id,'resourceType',p_resource_type,'resourceId',p_resource_id,'scope',p_scope,'expiresAt',current.expires_at,'serverNow',now_at);
end $$;

create or replace function platform_private.renew_resource_lease(
 p_actor_device_id uuid,p_module_id text,p_resource_type text,p_resource_id text,p_scope text,p_lease_token uuid,p_ttl_seconds integer default 120
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid; ttl integer:=coalesce(p_ttl_seconds,120); now_at timestamptz:=clock_timestamp(); exp_at timestamptz; current platform.resource_leases%rowtype;
begin
 if p_lease_token is null or ttl<30 or ttl>300 then raise exception 'PLATFORM_RESOURCE_LEASE_ARGUMENT_INVALID' using errcode='22023'; end if;
 actor_id:=platform_private.require_resource_lease_writer(p_actor_device_id,p_module_id,p_resource_type,p_resource_id,p_scope);
 select * into current from platform.resource_leases where module_id=p_module_id and resource_type=p_resource_type and resource_id=p_resource_id and scope=p_scope for update;
 if not found or current.expires_at<=now_at then return jsonb_build_object('status','expired','owned',false,'errorCode','RESOURCE_LEASE_EXPIRED','serverNow',now_at); end if;
 if current.holder_user_id<>actor_id or current.holder_device_id<>p_actor_device_id or not platform_private.resource_lease_session_owner(p_actor_device_id,current.holder_session_id) or current.lease_token<>p_lease_token then
   return jsonb_build_object('status','not_owner','owned',false,'errorCode','RESOURCE_LEASE_NOT_OWNED','expiresAt',current.expires_at,'serverNow',now_at);
 end if;
 exp_at:=now_at+make_interval(secs=>ttl);
 update platform.resource_leases set renewed_at=now_at,expires_at=exp_at where module_id=p_module_id and resource_type=p_resource_type and resource_id=p_resource_id and scope=p_scope;
 return jsonb_build_object('status','renewed','owned',true,'leaseToken',p_lease_token,'expiresAt',exp_at,'serverNow',now_at);
end $$;

create or replace function platform_private.release_resource_lease(
 p_actor_device_id uuid,p_module_id text,p_resource_type text,p_resource_id text,p_scope text,p_lease_token uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid; current platform.resource_leases%rowtype; now_at timestamptz:=clock_timestamp();
begin
 actor_id:=platform_private.require_resource_lease_writer(p_actor_device_id,p_module_id,p_resource_type,p_resource_id,p_scope);
 select * into current from platform.resource_leases where module_id=p_module_id and resource_type=p_resource_type and resource_id=p_resource_id and scope=p_scope for update;
 if not found then return jsonb_build_object('status','not_found','owned',false,'serverNow',now_at); end if;
 if current.holder_user_id<>actor_id or current.holder_device_id<>p_actor_device_id or not platform_private.resource_lease_session_owner(p_actor_device_id,current.holder_session_id) or current.lease_token<>p_lease_token then
   return jsonb_build_object('status','not_owner','owned',false,'errorCode','RESOURCE_LEASE_NOT_OWNED','serverNow',now_at);
 end if;
 delete from platform.resource_leases where module_id=p_module_id and resource_type=p_resource_type and resource_id=p_resource_id and scope=p_scope;
 return jsonb_build_object('status','released','owned',false,'serverNow',now_at);
end $$;

create or replace function platform_private.get_resource_lease(
 p_actor_device_id uuid,p_module_id text,p_resource_type text,p_resource_id text,p_scope text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid; current platform.resource_leases%rowtype; now_at timestamptz:=clock_timestamp(); owned boolean;
begin
 actor_id:=platform_private.require_resource_lease_writer(p_actor_device_id,p_module_id,p_resource_type,p_resource_id,p_scope);
 select * into current from platform.resource_leases where module_id=p_module_id and resource_type=p_resource_type and resource_id=p_resource_id and scope=p_scope;
 if not found or current.expires_at<=now_at then return jsonb_build_object('status','available','locked',false,'owned',false,'serverNow',now_at); end if;
 owned:=current.holder_user_id=actor_id and current.holder_device_id=p_actor_device_id and platform_private.resource_lease_session_owner(p_actor_device_id,current.holder_session_id);
 return jsonb_strip_nulls(jsonb_build_object('status','locked','locked',true,'owned',owned,'leaseToken',case when owned then current.lease_token else null end,'expiresAt',current.expires_at,'serverNow',now_at));
end $$;


commit;
