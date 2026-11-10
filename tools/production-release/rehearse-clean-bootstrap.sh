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
if grep -Eq '^-- Data for Name:' "$dump" || grep -Eiq '^COPY[[:space:]].*[[:space:]]FROM[[:space:]]+stdin;[[:space:]]*
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
