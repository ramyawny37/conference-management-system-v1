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
# The application artifact retains application ACLs but must exclude the
# Supabase-owned public namespace and supabase_admin default ACL replay.
if ! grep -Eiq '^[[:space:]]*GRANT[[:space:]]' "$dump" ||
   ! grep -Eiq '^[[:space:]]*ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES[[:space:]]' "$dump"; then
  fail "Schema-only dump lacks GRANT or ALTER DEFAULT PRIVILEGES replay; reviewed ACL restoration is required"
fi
if grep -Eiq '^[[:space:]]*CREATE[[:space:]]+SCHEMA[[:space:]]+"?public"?[[:space:]]*;' "$dump"; then
  fail "Application bootstrap must preserve the Supabase-managed public namespace"
fi
if grep -Eiq 'ALTER[[:space:]]+DEFAULT[[:space:]]+PRIVILEGES[[:space:]]+FOR[[:space:]]+ROLE[[:space:]]+"?supabase_admin"?' "$dump"; then
  fail "Application bootstrap must not replay Supabase-managed default privileges"
fi
[[ "${RELEASE_APPLICATION_ROLE:-postgres}" == "postgres" ]] || fail "Application executor role must be postgres"
echo "Rehearsing schema in disposable local database (no hosted connections)"
# The managed foundation is established separately by the fixture administrator.
psql -X -v ON_ERROR_STOP=1 -1 -f tests/fixtures/supabase-managed-foundation.sql >/dev/null
# Model an already-running application, including replaceable platform state and
# unexpected business rows. The reviewed ALL_APPLICATION_DATA contract must
# remove all of it atomically; none of these rows may reach the canonical seed.
psql -X -v ON_ERROR_STOP=1 -1 >/dev/null <<'SQL'
SET ROLE postgres;
CREATE SCHEMA platform;
CREATE TABLE platform.audit_events (id bigint PRIMARY KEY, payload jsonb NOT NULL);
CREATE TABLE platform.roles (id bigint PRIMARY KEY, code text NOT NULL);
CREATE TABLE platform.permissions (id bigint PRIMARY KEY, code text NOT NULL);
CREATE TABLE platform.role_permissions (role_id bigint NOT NULL, permission_id bigint NOT NULL);
INSERT INTO platform.audit_events VALUES (1,'{"legacy":true}');
INSERT INTO platform.roles VALUES (1,'legacy-role');
INSERT INTO platform.permissions VALUES (1,'legacy.permission');
INSERT INTO platform.role_permissions VALUES (1,1);
CREATE TABLE public.legacy_conference_operational_data (id bigint PRIMARY KEY);
INSERT INTO public.legacy_conference_operational_data VALUES (1);
CREATE SCHEMA reservations;
CREATE TABLE reservations.legacy_bookings (id bigint PRIMARY KEY);
INSERT INTO reservations.legacy_bookings VALUES (1);
RESET ROLE;
SQL
cutover="$(mktemp /tmp/canonical-application-cutover-XXXXXX.sql)"
trap 'rm -f "$cutover"' EXIT
{
  echo 'BEGIN;'
  if [[ "${PGUSER}" != "postgres" ]]; then echo 'SET LOCAL ROLE "postgres";'; fi
  cat tools/production-release/prepare-canonical-application-replacement.sql
  cat "$dump"
  echo 'SET LOCAL client_min_messages = notice;'
  cat tools/production-release/canonical-system-catalog-seed.sql
  cat tools/production-release/assert-canonical-full-foundation.sql
  cat tools/production-release/assert-canonical-structural-parity.sql
  cat tools/production-release/assert-first-owner-device-security.sql
  cat tools/production-release/assert-canonical-access-parity.sql
  cat tools/production-release/assert-canonical-ambient-grants.sql
  cat tools/production-release/assert-canonical-default-grants.sql
  echo 'COMMIT;'
} > "$cutover"
psql -X -v ON_ERROR_STOP=1 -f "$cutover"
echo "PASS: disposable structural rehearsal (owner/device and Edge Functions remain separate gates)"
