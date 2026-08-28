-- Phase 2AL disposable PostgreSQL 17 fixture. Never apply to a hosted database.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role app_catalog_owner nologin;

alter default privileges for role postgres in schema public
grant execute on functions to service_role;

alter default privileges for role postgres in schema public
grant select, insert, update, delete, truncate, references, trigger, maintain
on tables to service_role;

create schema auth;
create schema if not exists extensions;
create schema supabase_migrations;

create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create function auth.jwt() returns jsonb
language sql stable
as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;

do $$
declare
  installed_schema text;
begin
  select n.nspname
  into installed_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if installed_schema is not null and installed_schema <> 'extensions' then
    raise exception 'LAB_PGCRYPTO_SCHEMA_MISMATCH: expected extensions, found %', installed_schema;
  end if;
end
$$;

create extension if not exists pgcrypto
with schema extensions;

create publication supabase_realtime;

create table supabase_migrations.schema_migrations (
  version text primary key,
  statements text[],
  name text,
  created_by text,
  idempotency_key text unique,
  rollback text[]
);

comment on schema auth is 'PHASE 2AL TEST-ONLY minimal Supabase Auth contract';
comment on schema extensions is 'PHASE 2AL TEST-ONLY extension signature contract';
comment on schema supabase_migrations is 'PHASE 2AL TEST-ONLY migration-history laboratory';
