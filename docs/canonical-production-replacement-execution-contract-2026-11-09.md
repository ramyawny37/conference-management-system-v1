# Canonical Production Replacement — Execution Contract

Status: PREPARATION ONLY — no Production mutation authorized by this document.
Source: develop, pinned SHA 088d8a18332711a18c604691c503d3a9de171269 (refresh and revalidate before execution).
Target repository: ramyawny37/conference-management-system-v1, main.
Target Supabase: mpezfbvcdfxpgflehuot. Development: gppwltrifgfxrkzvvxoe.
Owner: a newly created Production Auth user; no legacy owner identity, devices, or data need be retained.
Data decision (2026-11-09): NO application records are to be migrated from either Development or old Production. Both are schema/reference sources only; Development must NOT be cleared or reset. Production is initialized with empty business data, with only required system catalogs and new owner/device records created through approved bootstrap.

## Decision
Replace the legacy Production application and application database with the canonical Development architecture. Do not merge legacy business logic, copy Development test records, or deploy the new frontend over the old database. Keep Development and Production isolated. No React or parallel runtime.

## Read-only inventory verified 2026-11-09
- Both Supabase projects report ACTIVE_HEALTHY / PostgreSQL 17.
- Development migration history: 295 rows; Production: 116 rows.
- Application functions across platform, reservations, platform_private, reservations_private: Development 161; Production 113.
- Development has platform 13, platform_private 11, public 46, reservations 15, reservations_private 1 ordinary tables; Production has platform 9, platform_private 7, public 53, reservations 12 and no reservations_private ordinary table.
- Development has newer deployed Edge Functions; Production functions must be independently redeployed and verified.
- Active migrations begin at 20260826110330 and presuppose an established pre-6.17 schema. The canonical historical lineage lives in supabase/migrations/DEVELOPMENT_PLATFORM_FOUNDATION_LINEAGE.json; old source artifacts in supabase/migration-archive/development-pre-canonical-reconciliation-20261104.
- tools/production-release/controlled-production-manifest.json is an old incremental/historical promotion contract (release SHA 9e35e7a5...) and must not be treated as an approved full replacement package.
- tools/issue-development-initial-platform-bootstrap.cjs is hard-coded to Development project, user, device, and origin. It MUST NOT be run for Production.

## Additional read-only security observation (2026-11-09)
Development application inventory: platform 13/13 RLS, platform_private 11/11 RLS, public 46/46 RLS, reservations 15/15 RLS, reservations_private 0/1 RLS. The reservations_private table is private and requires a grant/exposure review; do not assume an issue solely from RLS status. Security advisor reports 97 informational RLS-without-policy findings; this may be intentional deny-by-default for RPC-only tables, so audit actual grants, execution paths, and exposure before changing any policies. No permissions were changed.

## Gate A: build a reproducible canonical baseline (BLOCKED)
1. Inventory schemas, tables, constraints, indexes, triggers, policies, grants, extensions, views, functions, sequences, and data-dependent configuration in Development.
2. Distinguish application-owned objects from Supabase-managed auth/storage/realtime infrastructure. Never drop Supabase-managed schemas wholesale.
3. Construct an ordered, deterministic clean-bootstrap package from the authoritative established baseline plus applicable canonical migrations, without replaying superseded or Development-only recovery scripts.
4. Run it against an isolated disposable local Postgres/Supabase instance; a third hosted Supabase project is NOT required.
5. Compare the resulting schema with Development using structural inventories and security checks. Test idempotency and representative module operations. Do not fake migration-history rows.
Acceptance: clean bootstrap PASS, no missing dependencies, security and permissions PASS. Otherwise BLOCKED.

## Gate B: first owner and device (BLOCKED)
1. Create a new Production Auth user via supported administrative Auth flow after baseline is ready. No password is requested in chat or committed to Git.
2. Use a project-scoped, one-time, expiring owner-bootstrap authorization with verified Auth user and device binding; never reuse Development user/device IDs or token.
3. Prove first login, first device approval, logout/login, second-device approval and revoke, owner access and denied unauthorized access.
4. Never disable device authorization as a shortcut; verify WebAuthn/session and Edge Function environment contracts.
Acceptance: end-to-end owner and device lifecycle PASS.

## Gate C: production release packaging (BLOCKED)
1. Audit the 10 main-only commits for any necessary deployment/security behavior, without merging old business logic.
2. Build a NEW full-replacement manifest pinned to an exact approved develop SHA, schema digest, Edge Function versions, frontend assets and deployment config.
3. Review js/supabase/public-config.js, service-worker.js, version.js and GitHub Pages base path for strict environment isolation and cache invalidation.
4. Run canonical syntax, dependency, unit/integration, release preflight and actual preview/browser acceptance. Update old incremental-only promotion checks instead of bypassing them.
5. Publish main only after Gates A/B pass and explicit go-live approval.
Acceptance: code/DB/Edge SHA alignment, owner access, no Development requests from Production, rollback artifact available.

## Gate D: replacement of existing Production (NOT AUTHORIZED YET)
1. Take and verify a restorable snapshot/export of the existing Production database, auth metadata as supported, Edge Functions, settings and main SHA. Even though old data is unwanted, backup enables rollback.
2. Capture a maintenance window and freeze writes. Obtain explicit final confirmation for irreversible reset/replacement.
3. Remove/replace only application-owned objects and legacy Auth users through supported, audited procedures. Avoid blanket DROP of managed schemas.
4. Apply the validated clean bootstrap, deploy five canonical Edge Functions, configure Auth URL/redirect, secrets, API exposure and JWT verification.
5. Bootstrap new owner; validate first device BEFORE opening to real users.
6. Promote approved source to main via controlled branch replacement; publish GitHub Pages; verify service worker and public config.
7. Smoke test new event, identity/booking, payment, apology/refund, accommodation/transport, finance/report isolation and permissions. No synthetic financial transactions in real operations unless safely removed and audited.
8. Keep verified rollback snapshots until acceptance and agreed retention period. The snapshots are for disaster recovery only, NOT data migration. The user's explicit no-data requirement does not waive safe rollback of destructive infrastructure changes.

## Explicit non-goals
- Do not redesign all screens before first live operation; fix launch-blocking UI defects only.
- Do not introduce a second reservations writer, legacy fallback, or parallel platform.
- Do not implement future-credit functionality.
- Do not copy Development sample data or historical Production user accounts.
- Do not reset, delete, or mutate Production without final approval.

## Reporting
For each gate record PASS / FAIL / BLOCKED, exact source SHA, schema digest, test commands/results, and artifacts. A code commit alone does not prove runtime acceptance.
