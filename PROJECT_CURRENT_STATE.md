# Project Current State — Conference Management System

Last verified handoff: 2026-11-09 (Africa/Cairo)
Repository: `ramyawny37/conference-management-system-v1`

## Source control
- Active development branch: `develop` only.
- Verified branch head at handoff: `1b91e21729fd600b65833e05be31a6480220b368`.
- Its parent fix commit: `ea72d0553b7f6e4410649ea7e2c83920b211f055`.
- The compare API confirmed `develop` is exactly one commit ahead of `ea72d055`, and that commit is the dashboard payment-source regression test.
- Production branch `main` must not be changed. Last recorded production SHA in project handoff context: `0751b53d622a35a980f50ccb5b8c9ed9ce8afcbf`. Re-verify before any release-related statement.
- No merge to main, no auto-merge, no force push.

## Latest code change
- `ea72d055`: `fix(reservations): use payment-enriched bookings on dashboard`.
  - Changed `modules/reservations/reservations-module.js`.
  - Dashboard booking rows now use the payment-enriched rows for collected totals rather than the raw booking collection.
- `1b91e217`: added `tests/reservations-dashboard-payment-source.test.js` to guard the regression.
- The regression test commit is the current verified `develop` head.

## Verification state — do not overstate
- GitHub commit metadata confirms both commits exist on the history leading to `develop`.
- The connector's combined commit-status endpoint returned no status entries for these commits; this is NOT proof of a successful Actions run.
- The workflow-runs lookup available during handoff only returns PR-triggered runs and returned none for `ea72d055`; therefore Actions result is currently **UNVERIFIED**.
- Latest Preview deployment SHA and live runtime acceptance are **UNVERIFIED**.
- The latest dashboard change is frontend mapping/test work; no new Supabase migration was part of these two commits.
- Do not claim CI, Preview, or operational acceptance PASS until independently checked.

## Immediate next actions
1. Inspect GitHub Actions runs for current `develop` head `1b91e21729fd600b65833e05be31a6480220b368`, including all jobs and logs for failures.
2. If Actions failed, identify the first causal failure, fix the root cause on `develop`, add/update a focused regression test, then rerun.
3. Verify the Development Preview is built from the exact final `develop` SHA and test the dashboard collected amount against payment-enriched booking data.
4. Confirm no refresh is needed for dashboard updates after relevant mutations.
5. Update this file and `WORK_LOG.md` with exact SHAs, run IDs, results, Preview SHA, and remaining blockers.

## Environment boundary
- Supabase Development project: `gppwltrifgfxrkzvvxoe`.
- All database inspection/migrations/testing must target Development only.
- Never touch Production or `main`.
- The last prior handoff reported the unified cancellation/refund/credit financial contract applied on Development; re-check actual schema/state before relying on it.

## Product scope
This is the Arabic, non-React Conference Management System SPA. Keep one canonical implementation and remove obsolete paths only after verifying full feature parity. Each event is standalone: people, bookings, accounts, payments, refunds/credits, and reports must not leak across events.
