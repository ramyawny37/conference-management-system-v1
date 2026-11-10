#!/usr/bin/env bash
# Offline, disposable-target-only bootstrap rehearsal. Never targets hosted Supabase.
set -euo pipefail
fail() { echo "BLOCKED: $*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail "Usage: bash tools/production-release/rehearse-clean-bootstrap.sh /absolute/path/schema-only.sql"
[[ "$1" = /* && -f "$1" ]] || fail "Schema dump must be an existing absolute path"
[[ "${RELEASE_DISPOSABLE_REHEARSAL:-}" == "I_UNDERSTAND_DISPOSABLE_ONLY" ]] || fail "Explicit disposable rehearsal acknowledgement required"
[[ "${PGHOST:-}" == "localhost" || "${PGHOST:-}" == "127.0.0.1" ]] || fail "Only local PostgreSQL host is permitted"
[[ "${PGDATABASE:-}" == release_rehearsal_* ]] || fail "Database name must start with release_rehearsal_"
[[ "${PGPORT:-5432}" =~ ^[0-9]+$ ]] || fail "PGPORT must be numeric"
[[ "${PGPORT:-5432}" -ge 1 && "${PGPORT:-5432}" -le 65535 ]] || fail "PGPORT out of range"
[[ -z "${PGOPTIONS:-}" ]] || fail "PGOPTIONS override forbidden"
[[ -z "${PGCONNECT_TIMEOUT:-}" || "${PGCONNECT_TIMEOUT}" =~ ^[0-9]+$ ]] || fail "Invalid PGCONNECT_TIMEOUT"
[[ -z "${PGHOSTADDR:-}" ]] || fail "PGHOSTADDR override forbidden"
[[ -z "${PGSERVICE:-}" && -z "${PGSERVICEFILE:-}" ]] || fail "PostgreSQL service overrides forbidden"
[[ "${PGUSER:-}" != "" && "${PGPASSWORD:-}" != "" ]] || fail "Explicit disposable database credentials required"
[[ "${PGSSLMODE:-}" != "require" ]] || fail "Hosted TLS connections forbidden"
command -v psql >/dev/null || fail "psql unavailable"
dump="$1"
grep -q '^-- PostgreSQL database dump' "$dump" || fail "Unrecognized schema-only dump"
if grep -Fq -- '-- Data for Name:' "$dump" || grep -Eiq '^COPY[[:space:]].*FROM[[:space:]]+stdin;[[:space:]]*$' "$dump"; then fail "Dump contains table data"; fi
if grep -Eiq '^[[:space:]]*(CREATE|ALTER)[[:space:]]+(ROLE|USER|DATABASE|TABLESPACE)[[:space:]]' "$dump"; then fail "Dump contains privileged cluster DDL"; fi
# Exporter strips ACLs; without an approved grants replay the artifact
# cannot establish the secure canonical database, regardless of schema parity.
if ! grep -Eiq '^[[:space:]]*GRANT[[:space:]]' "$dump" ||
   ! grep -Eiq '^[[:space:]]*ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES[[:space:]]' "$dump"; then
  fail "Schema-only dump lacks GRANT or ALTER DEFAULT PRIVILEGES replay; reviewed ACL restoration is required"
fi
echo "Rehearsing schema in disposable local database (no hosted connections)"
# Minimal Supabase-managed foundation required by the application dump. These objects
# are intentionally outside the replacement boundary and already exist on hosted Supabase.
psql -X -v ON_ERROR_STOP=1 -1 <<'SQL' >/dev/null
CREATE SCHEMA IF NOT EXISTS "extensions";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";
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
SQL
# Rehearse the same zero-data replacement boundary intended for hosted release:
# only the five application schemas are cleared; PostgreSQL/Supabase-managed schemas are out of scope.
psql -X -v ON_ERROR_STOP=1 -1 <<'SQL' >/dev/null
DROP SCHEMA IF EXISTS "reservations_private" CASCADE;
DROP SCHEMA IF EXISTS "reservations" CASCADE;
DROP SCHEMA IF EXISTS "platform_private" CASCADE;
DROP SCHEMA IF EXISTS "platform" CASCADE;
DROP SCHEMA IF EXISTS "public" CASCADE;
SQL
psql -X -v ON_ERROR_STOP=1 -1 -f "$dump" >/dev/null
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/canonical-system-catalog-seed.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-full-foundation.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-structural-parity.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-first-owner-device-security.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-access-parity.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-ambient-grants.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-default-grants.sql
echo "PASS: disposable structural rehearsal (owner/device and Edge Functions remain separate gates)"
 "$dump"; then fail "Dump contains table data"; fi
if grep -Eiq '^[[:space:]]*(CREATE|ALTER)[[:space:]]+(ROLE|USER|DATABASE|TABLESPACE)[[:space:]]' "$dump"; then fail "Dump contains privileged cluster DDL"; fi
# Exporter strips ACLs; without an approved grants replay the artifact
# cannot establish the secure canonical database, regardless of schema parity.
if ! grep -Eiq '^[[:space:]]*GRANT[[:space:]]' "$dump" ||
   ! grep -Eiq '^[[:space:]]*ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES[[:space:]]' "$dump"; then
  fail "Schema-only dump lacks GRANT or ALTER DEFAULT PRIVILEGES replay; reviewed ACL restoration is required"
fi
echo "Rehearsing schema in disposable local database (no hosted connections)"
psql -X -v ON_ERROR_STOP=1 -1 -f "$dump" >/dev/null
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/canonical-system-catalog-seed.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-full-foundation.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-structural-parity.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-first-owner-device-security.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-access-parity.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-ambient-grants.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-default-grants.sql
echo "PASS: disposable structural rehearsal (owner/device and Edge Functions remain separate gates)"
