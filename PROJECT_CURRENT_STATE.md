# Project Current State — Conference Management System

Last verified handoff: 2026-11-09 (Africa/Cairo)
Repository: `ramyawny37/conference-management-system-v1`

## Source control
- Active development branch: `develop` only.
- Current verified `develop` head before this audit log update: `d15e1cdc0fcfd18415cd16b520b4a95d6eb8014e`.
- Last validated application-code SHA: `1b91e21729fd600b65833e05be31a6480220b368`. Comparing it to current `develop` shows only the three handoff documentation files were added afterward; no application source changed.
- `develop` is five commits ahead of `ee0b207c881cae5bee61e20dda198aa0dad0a8ee`; compare confirms the additional changes are the dashboard fix, regression test, and three handoff documents.
- `main` remains identical to the recorded production baseline `0751b53d622a35a980f50ccb5b8c9ed9ce8afcbf`. No write was made to `main`.
- No merge to main, no auto-merge, no force push.

## Latest functional changes
- `ee0b207c881cae5bee61e20dda198aa0dad0a8ee`: `chore(platform): reinstall development worker for shared financial cache refresh`.
  - Changed `service-worker.js` comment to trigger a Development worker reinstall for canonical accommodation and shared Reservations financial-cache assets.
  - This was the previously identified Preview target before the dashboard payment-source fix.
- `ea72d0553b7f6e4410649ea7e2c83920b211f055`: `fix(reservations): use payment-enriched bookings on dashboard`.
  - Changed `modules/reservations/reservations-module.js`.
  - Dashboard booking rows use payment-enriched rows for collected totals rather than raw booking rows.
- `1b91e21729fd600b65833e05be31a6480220b368`: `test(reservations): cover dashboard payment source regression`.
  - Added `tests/reservations-dashboard-payment-source.test.js`.

## Handoff documentation
- `PROJECT_CURRENT_STATE.md`, `ARCHITECTURE_AND_POLICIES.md`, and `WORK_LOG.md` were added to `develop`.
- These are handoff records, not application runtime changes.

## Verification state — do not overstate
- GitHub confirms the above commits exist on the history leading to current `develop`.
- User confirmed the dashboard correction is now visible/working in their manual test.
- Automated Actions result for the current exact `develop` head is **UNVERIFIED**; the available commit-status endpoint returned no entries and the available workflow lookup was limited to PR-triggered runs.
- Vercel is not part of the active application/deployment architecture and must not be used as a project dependency or release gate.
- The active static runtime has an explicit regression test asserting no Gateway/Vercel dependency and absence of retired `vercel.json`/gateway artifacts. The package script `npm run check:development-preview` is a local Node validation script, not a Vercel deployment check.
- The Vercel authorization prompt in the prior conversation was an unnecessary external tooling detour; do not approve or rely on it. It did not create an application dependency or modify the repository's hosting configuration.
- The exact current Preview hosting/deployment evidence is **UNVERIFIED** and must be checked through the project's actual GitHub-based Development Preview workflow/repository, not Vercel.
- Browser acceptance beyond the user's dashboard confirmation remains **UNVERIFIED**.
- No Supabase migration or Development database mutation was performed as part of the documentation commits.

## Immediate next actions
1. Inspect GitHub Actions for the exact current `develop` SHA using the repository's normal GitHub workflow history; record actual run/job conclusions.
2. Complete the agreed event-scoped credit lifecycle only after defining its atomic destination-booking payment and cash-reporting semantics; preserve the existing fail-closed guards until the full writer/UI/report path is ready.
3. Complete live UI acceptance for pending refund, later partial/full disbursement, delete history, and same-event rebooking without refresh.
4. Continue to use the existing GitHub Pages Preview workflow; do not add Vercel or another hosting provider.
5. Update this file and `WORK_LOG.md` with exact run IDs, Preview source SHA, test evidence, and blockers.

## Environment boundary
- Supabase Development project: `gppwltrifgfxrkzvvxoe`.
- All database inspection/migrations/testing must target Development only.
- Never touch Production or `main`.
- The last prior handoff reported the unified cancellation/refund/credit financial contract applied on Development; re-check actual schema/state before relying on it.

## Product scope
Arabic, non-React Conference Management System SPA. Keep one canonical implementation. Each event is standalone: people, bookings, accounts, payments, refunds/credits, and reports must not leak across events.
