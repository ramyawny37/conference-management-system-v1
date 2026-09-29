begin;
create schema auth;
create schema extensions;
create schema platform;
create schema platform_private;
select pg_advisory_xact_lock(8675309);
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then
    begin create role anon; exception when duplicate_object or unique_violation then null; end;
  end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then
    begin create role authenticated; exception when duplicate_object or unique_violation then null; end;
  end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then
    begin create role service_role; exception when duplicate_object or unique_violation then null; end;
  end if;
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
