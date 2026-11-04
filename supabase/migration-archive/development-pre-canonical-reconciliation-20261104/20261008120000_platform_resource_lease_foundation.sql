begin;

create table if not exists platform.resource_leases (
  module_id text not null,
  resource_type text not null,
  resource_id text not null,
  scope text not null default 'edit',
  holder_user_id uuid not null references auth.users(id) on delete cascade,
  holder_device_id uuid not null references platform.devices(id) on delete cascade,
  lease_token uuid not null,
  acquired_at timestamptz not null default clock_timestamp(),
  renewed_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  primary key (module_id,resource_type,resource_id,scope),
  unique (lease_token),
  constraint platform_resource_leases_module_check check (module_id ~ '^[a-z][a-z0-9_-]{0,63}$'),
  constraint platform_resource_leases_type_check check (resource_type ~ '^[a-z][a-z0-9_-]{0,63}$'),
  constraint platform_resource_leases_scope_check check (scope ~ '^[a-z][a-z0-9_-]{0,63}$'),
  constraint platform_resource_leases_resource_check check (length(resource_id) between 1 and 256)
);

alter table platform.resource_leases enable row level security;
revoke all on table platform.resource_leases from public,anon,authenticated;

create or replace function platform_private.resource_lease_permission_key(p_module_id text,p_resource_type text,p_scope text)
returns text language plpgsql immutable set search_path='' as $$
begin
  if p_scope <> 'edit' then raise exception 'PLATFORM_RESOURCE_LEASE_SCOPE_UNSUPPORTED' using errcode='22023'; end if;
  if p_module_id='conference' and p_resource_type='accommodation_room' then return 'conference.accommodation.manage'; end if;
  raise exception 'PLATFORM_RESOURCE_LEASE_RESOURCE_UNMAPPED: %.%',p_module_id,p_resource_type using errcode='42501';
end $$;

create or replace function platform_private.require_resource_lease_writer(
 p_actor_device_id uuid,p_module_id text,p_resource_type text,p_resource_id text,p_scope text
) returns uuid language plpgsql security definer set search_path='' as $$
declare authority jsonb; actor_id uuid; permission_key text;
begin
 if p_actor_device_id is null or p_resource_id is null or btrim(p_resource_id)='' then
   raise exception 'PLATFORM_RESOURCE_LEASE_ARGUMENT_INVALID' using errcode='22023';
 end if;
 permission_key:=platform_private.resource_lease_permission_key(p_module_id,p_resource_type,p_scope);
 authority:=public.require_effective_module_permission(
   p_actor_device_id,p_module_id,permission_key,p_resource_type,p_resource_id
 );
 actor_id:=nullif(authority->>'actorUserId','')::uuid;
 if actor_id is null then raise exception 'PLATFORM_RESOURCE_LEASE_AUTHORITY_INVALID' using errcode='42501'; end if;
 return actor_id;
end $$;

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
 if current.holder_user_id=actor_id and current.holder_device_id=p_actor_device_id then
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
 if current.holder_user_id<>actor_id or current.holder_device_id<>p_actor_device_id or current.lease_token<>p_lease_token then
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
 if current.holder_user_id<>actor_id or current.holder_device_id<>p_actor_device_id or current.lease_token<>p_lease_token then
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
 owned:=current.holder_user_id=actor_id and current.holder_device_id=p_actor_device_id;
 return jsonb_strip_nulls(jsonb_build_object('status','locked','locked',true,'owned',owned,'leaseToken',case when owned then current.lease_token else null end,'expiresAt',current.expires_at,'serverNow',now_at));
end $$;

revoke all on function platform_private.resource_lease_permission_key(text,text,text) from public,anon,authenticated;
revoke all on function platform_private.require_resource_lease_writer(uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function platform_private.acquire_resource_lease(uuid,text,text,text,text,uuid,integer) from public,anon,authenticated;
revoke all on function platform_private.renew_resource_lease(uuid,text,text,text,text,uuid,integer) from public,anon,authenticated;
revoke all on function platform_private.release_resource_lease(uuid,text,text,text,text,uuid) from public,anon,authenticated;
revoke all on function platform_private.get_resource_lease(uuid,text,text,text,text) from public,anon,authenticated;

do $$
declare d text; marker text:=E'  end if;\n  return platform.execute_conference_device_operation_phase1c_core(\n    p_user_id,p_session_id,p_token_hash,p_operation,p_args\n  );'; replacement text:=E'  elsif p_operation in (''acquire_resource_lease'',''renew_resource_lease'') then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_resource_type'',''p_resource_id'',''p_scope'',''p_lease_token'',''p_ttl_seconds'']);\n    if p_operation=''acquire_resource_lease'' then\n      return platform_private.acquire_resource_lease(p_actor_device_id,''conference'',p_args->>''p_resource_type'',p_args->>''p_resource_id'',p_args->>''p_scope'',(p_args->>''p_lease_token'')::uuid,(p_args->>''p_ttl_seconds'')::integer);\n    end if;\n    return platform_private.renew_resource_lease(p_actor_device_id,''conference'',p_args->>''p_resource_type'',p_args->>''p_resource_id'',p_args->>''p_scope'',(p_args->>''p_lease_token'')::uuid,(p_args->>''p_ttl_seconds'')::integer);\n  elsif p_operation=''release_resource_lease'' then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_resource_type'',''p_resource_id'',''p_scope'',''p_lease_token'']);\n    return platform_private.release_resource_lease(p_actor_device_id,''conference'',p_args->>''p_resource_type'',p_args->>''p_resource_id'',p_args->>''p_scope'',(p_args->>''p_lease_token'')::uuid);\n  elsif p_operation=''get_resource_lease'' then\n    perform platform_private.require_exact_jsonb_keys(p_args,array[''p_resource_type'',''p_resource_id'',''p_scope'']);\n    return platform_private.get_resource_lease(p_actor_device_id,''conference'',p_args->>''p_resource_type'',p_args->>''p_resource_id'',p_args->>''p_scope'');\n  end if;\n  return platform.execute_conference_device_operation_phase1c_core(\n    p_user_id,p_session_id,p_token_hash,p_operation,p_args\n  );';
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='platform_private' and p.proname='route_canonical_conference_operation';
 if d is null or position(marker in d)=0 then raise exception 'PLATFORM_RESOURCE_LEASE_DISPATCH_PREDECESSOR_MISMATCH' using errcode='55000'; end if;
 execute replace(d,marker,replacement);
end $$;

commit;
