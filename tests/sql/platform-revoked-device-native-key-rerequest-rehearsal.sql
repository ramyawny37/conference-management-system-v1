begin;
create schema auth;
create schema extensions;
create schema platform;
create schema platform_private;
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
  truncate platform_private.device_authorization_rerequest_nonces,platform.audit_events,platform.device_key_bindings,
    platform.user_device_authorizations,platform.devices,platform.profiles cascade;
  insert into platform.profiles values
    ('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002');
  insert into platform.devices values('20000000-0000-4000-8000-000000000001','active',null,null);
  insert into platform.user_device_authorizations values(
    '30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',p_status,now()-interval '1 day',null,null,null,null,
    case when p_status='revoked' then '10000000-0000-4000-8000-000000000002'::uuid end,
    case when p_status='revoked' then now()-interval '1 hour' end,'old reason',now()
  );
  insert into platform.device_key_bindings values(
    '40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',
    '{"kty":"EC","crv":"P-256","x":"x","y":"y"}','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'ECDSA_P256_SHA256',p_binding_status,case when p_binding_status='revoked' then now() end,null
  );
end $$;

select pg_temp.reset_fixture();
select platform.rerequest_revoked_device_key(
  '10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
);
do $$ begin
  if (select status from platform.user_device_authorizations)<>'pending' then raise exception 'STATUS_NOT_PENDING'; end if;
  if (select count(*) from platform.devices)<>1 then raise exception 'DEVICE_COUNT_CHANGED'; end if;
  if (select count(*) from platform.user_device_authorizations)<>1 then raise exception 'AUTHORIZATION_COUNT_CHANGED'; end if;
  if (select count(*) from platform.device_key_bindings)<>1 then raise exception 'BINDING_COUNT_CHANGED'; end if;
  if (select device_id from platform.user_device_authorizations)<>'20000000-0000-4000-8000-000000000001'::uuid then raise exception 'DEVICE_CHANGED'; end if;
  if (select id from platform.device_key_bindings)<>'40000000-0000-4000-8000-000000000001'::uuid then raise exception 'BINDING_CHANGED'; end if;
  if exists(select 1 from platform.user_device_authorizations where approved_by is not null or approved_at is not null or blocked_by is not null or blocked_at is not null or revoked_by is not null or revoked_at is not null or status_reason is not null) then raise exception 'TERMINAL_METADATA_RETAINED'; end if;
  if not exists(select 1 from platform.audit_events where action='device_authorization.native_key_rerequested' and old_values->>'status'='revoked' and new_values->>'status'='pending' and metadata->>'proof'='native_key_possession') then raise exception 'AUDIT_MISSING'; end if;
end $$;

select pg_temp.reset_fixture();
update platform.user_device_authorizations set status='pending',revoked_at=null;
do $$ begin perform platform.rerequest_revoked_device_key('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'); raise exception 'NON_REVOKED_ACCEPTED'; exception when insufficient_privilege then null; end $$;
select pg_temp.reset_fixture('revoked','revoked');
do $$ begin perform platform.rerequest_revoked_device_key('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'); raise exception 'INACTIVE_BINDING_ACCEPTED'; exception when insufficient_privilege then null; end $$;
select pg_temp.reset_fixture();
do $$ begin perform platform.rerequest_revoked_device_key('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'); raise exception 'WRONG_USER_ACCEPTED'; exception when insufficient_privilege then null; end $$;
select pg_temp.reset_fixture();
insert into platform.devices values('20000000-0000-4000-8000-000000000002','active',null,null);
do $$ begin perform platform.rerequest_revoked_device_key('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000001','FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'); raise exception 'WRONG_DEVICE_ACCEPTED'; exception when insufficient_privilege then null; end $$;
select pg_temp.reset_fixture();
insert into platform_private.device_authorization_rerequest_nonces values(
  'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',now()
);
do $$ begin perform platform.rerequest_revoked_device_key('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'); raise exception 'REPLAY_ACCEPTED'; exception when insufficient_privilege then null; end $$;

rollback;
