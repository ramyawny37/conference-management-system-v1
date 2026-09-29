begin;
create schema auth;
create schema extensions;
create schema platform;
create schema platform_private;
select pg_advisory_xact_lock(8675309);
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create function auth.jwt() returns jsonb language sql stable as $$ select '{"role":"service_role"}'::jsonb $$;
create table platform.profiles(user_id uuid primary key);
create table platform.devices(id uuid primary key,lifecycle_status text not null,retired_at timestamptz,compromised_at timestamptz);
create table platform.user_device_authorizations(
  id uuid primary key,user_id uuid not null references platform.profiles(user_id),device_id uuid not null references platform.devices(id),
  status text not null,requested_at timestamptz not null,approved_by uuid,approved_at timestamptz,blocked_by uuid,blocked_at timestamptz,
  revoked_by uuid,revoked_at timestamptz,status_reason text,updated_at timestamptz default now(),unique(user_id,device_id)
);
create table platform.device_key_bindings(
  id uuid primary key,user_id uuid not null references platform.profiles(user_id),device_id uuid not null references platform.devices(id),
  device_authorization_id uuid not null references platform.user_device_authorizations(id),public_key_jwk jsonb not null,
  public_key_thumbprint text not null,algorithm text not null,lifecycle_status text not null,revoked_at timestamptz,retired_at timestamptz
);
create table platform.audit_events(
  id bigserial primary key,actor_user_id uuid,subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,
  scope_type text,old_values jsonb,new_values jsonb,metadata jsonb,source text
);
\ir ../../supabase/migrations/20260921172640_revoked_device_native_key_rerequest.sql

create function pg_temp.reset_fixture(p_status text default 'revoked',p_binding_status text default 'active') returns void language plpgsql as $$
begin
  truncate platform.revoked_device_authorization_rerequest_operations,platform.audit_events,platform.device_key_bindings,platform.user_device_authorizations,platform.devices,platform.profiles restart identity cascade;
  insert into platform.profiles(user_id) values('10000000-0000-0000-0000-000000000001');
  insert into platform.devices(id,lifecycle_status) values('20000000-0000-0000-0000-000000000001','active');
  insert into platform.user_device_authorizations(id,user_id,device_id,status,requested_at,revoked_at,status_reason) values('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',p_status,now(),case when p_status='revoked' then now() end,'fixture');
  insert into platform.device_key_bindings(id,user_id,device_id,device_authorization_id,public_key_jwk,public_key_thumbprint,algorithm,lifecycle_status) values('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','{"kty":"EC"}'::jsonb,'thumb','ES256',p_binding_status);
end $$;

select pg_temp.reset_fixture();
select public.rerequest_revoked_device_authorization('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001')::text;
select public.rerequest_revoked_device_authorization('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001')::text;
do $$ begin
  if (select status from platform.user_device_authorizations where id='30000000-0000-0000-0000-000000000001')<>'pending' then raise exception 'status mismatch'; end if;
  if (select count(*) from platform.user_device_authorizations)<>1 then raise exception 'authorization identity changed'; end if;
  if (select count(*) from platform.devices)<>1 then raise exception 'device identity changed'; end if;
  if (select count(*) from platform.device_key_bindings)<>1 then raise exception 'binding identity changed'; end if;
  if (select count(*) from platform.revoked_device_authorization_rerequest_operations)<>1 then raise exception 'operation replay mismatch'; end if;
  if (select count(*) from platform.audit_events where action='revoked_device_authorization_rerequested')<>1 then raise exception 'audit mismatch'; end if;
end $$;
rollback;
