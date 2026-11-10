-- Disposable-only fixture for the hosted Supabase foundation that is outside
-- the application replacement boundary.  This is not an application schema
-- bootstrap and must never be executed against a hosted project.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
    RAISE EXCEPTION 'DISPOSABLE_FOUNDATION_POSTGRES_ROLE_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN CREATE ROLE supabase_admin NOLOGIN; END IF;
END
$roles$;

ALTER SCHEMA "public" OWNER TO "postgres";
GRANT USAGE, CREATE ON SCHEMA "public" TO "postgres";
DO $database_grant$
BEGIN
  EXECUTE format('GRANT CREATE ON DATABASE %I TO postgres',current_database());
END
$database_grant$;

CREATE SCHEMA IF NOT EXISTS "extensions";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "supabase_vault";
CREATE SCHEMA IF NOT EXISTS "auth";
CREATE TABLE IF NOT EXISTS "auth"."users" (
  "id" uuid PRIMARY KEY,
  "email" text,
  "raw_user_meta_data" jsonb,
  "created_at" timestamptz DEFAULT now()
);
CREATE OR REPLACE FUNCTION "auth"."uid"() RETURNS uuid
LANGUAGE sql STABLE SET search_path = ''
AS $auth$ SELECT NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid $auth$;
CREATE OR REPLACE FUNCTION "auth"."role"() RETURNS text
LANGUAGE sql STABLE SET search_path = ''
AS $auth$ SELECT NULLIF(pg_catalog.current_setting('request.jwt.claim.role', true), '') $auth$;
CREATE OR REPLACE FUNCTION "auth"."jwt"() RETURNS jsonb
LANGUAGE sql STABLE SET search_path = ''
AS $auth$ SELECT COALESCE(NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $auth$;

-- Hosted Supabase owns these defaults.  The application executor must verify
-- them but must never replay or mutate them.
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres", "anon", "authenticated", "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres", "anon", "authenticated", "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres", "anon", "authenticated", "service_role";
