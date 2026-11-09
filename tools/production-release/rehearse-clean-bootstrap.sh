#!/usr/bin/env bash
# Offline, disposable-target-only bootstrap rehearsal. Never targets hosted Supabase.
set -euo pipefail
fail() { echo "BLOCKED: $*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail "Usage: bash tools/production-release/rehearse-clean-bootstrap.sh /absolute/path/schema-only.sql"
[[ "$1" = /* && -f "$1" ]] || fail "Schema dump must be an existing absolute path"
[[ "${RELEASE_DISPOSABLE_REHEARSAL:-}" == "I_UNDERSTAND_DISPOSABLE_ONLY" ]] || fail "Explicit disposable rehearsal acknowledgement required"
[[ "${PGHOST:-}" == "localhost" || "${PGHOST:-}" == "127.0.0.1" ]] || fail "Only local PostgreSQL host is permitted"
[[ "${PGDATABASE:-}" == release_rehearsal_* ]] || fail "Database name must start with release_rehearsal_"
[[ "${PGUSER:-}" != "" && "${PGPASSWORD:-}" != "" ]] || fail "Explicit disposable database credentials required"
[[ "${PGSSLMODE:-}" != "require" ]] || fail "Hosted TLS connections forbidden"
command -v psql >/dev/null || fail "psql unavailable"
dump="$1"
grep -q '^-- PostgreSQL database dump' "$dump" || fail "Unrecognized schema-only dump"
if grep -Eiq '^[[:space:]]*(COPY|INSERT|UPDATE|DELETE|TRUNCATE)[[:space:]]' "$dump"; then fail "Dump contains data manipulation"; fi
if grep -Eiq '^[[:space:]]*(CREATE|ALTER)[[:space:]]+(ROLE|USER|DATABASE|TABLESPACE)[[:space:]]' "$dump"; then fail "Dump contains privileged cluster DDL"; fi
echo "Rehearsing schema in disposable local database (no hosted connections)"
psql -X -v ON_ERROR_STOP=1 -1 -f "$dump" >/dev/null
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/canonical-system-catalog-seed.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-full-foundation.sql
psql -X -v ON_ERROR_STOP=1 -f tools/production-release/assert-canonical-structural-parity.sql
echo "PASS: disposable structural rehearsal (owner/device and Edge Functions remain separate gates)"
