# Work Log

## 2026-11-09 — Reservations dashboard payment source and handoff continuity

### Verified functional commits
- `ee0b207c881cae5bee61e20dda198aa0dad0a8ee`
  - `chore(platform): reinstall development worker for shared financial cache refresh`
  - Changed `service-worker.js` to reinstall the Development worker for accommodation and shared Reservations financial-cache assets.
  - This was the previously identified Preview target before the dashboard correction.
- `ea72d0553b7f6e4410649ea7e2c83920b211f055`
  - `fix(reservations): use payment-enriched bookings on dashboard`
  - Changed `modules/reservations/reservations-module.js` so dashboard collected totals consume payment-enriched booking rows.
- `1b91e21729fd600b65833e05be31a6480220b368`
  - `test(reservations): cover dashboard payment source regression`
  - Added `tests/reservations-dashboard-payment-source.test.js`.
  - The test asserts dashboard mapper uses payment-enriched rows and maps `total_paid`.

### Handoff documentation commits
- `83a26c69997db6309deae9a6c331c9638d3a9845`: added `PROJECT_CURRENT_STATE.md`.
- `007d052c5660322da2fde5d4aa757ba19613530e`: added `ARCHITECTURE_AND_POLICIES.md`.
- `2512f10aba70c0608231c84b0f79b4b91f9d9d11`: added `WORK_LOG.md`.
- Verified `develop` head before the Vercel-reference correction: `9c935f8a46fe020bd9672731fb654738bd2185f9`.

### Acceptance and deployment
- User manually confirmed the dashboard correction.
- User's requested next financial QA includes verifying the same payment across dashboard, booking record, participant statement, and financial report without refresh; then apology/refund and deletion/rebooking lifecycle.
- User also clarified they were viewing a 100-operation concurrent/parallel posting test, not asking to create 100 additional bookings.
- GitHub commit-status endpoint returned no entries; Actions for the current exact SHA remain **UNVERIFIED**.
- Assistant incorrectly attempted to use Vercel to inspect Preview, despite it not being part of the project's active architecture. The generated one-time consent URL is an external tooling request only; it did not alter the repository or grant access. Do not approve or reuse it.
- Repository evidence: `tests/platform-unified-warehouse.test.js` explicitly asserts zero Gateway/Vercel dependency and absence of `vercel.json` and retired gateway artifacts. `npm run check:development-preview` runs `tools/validation/check-development-preview.cjs`, a local Node syntax/runtime/test validation script, not a Vercel deployment.
- User clarified Vercel has been retired for a long time. No Vercel integration should be reintroduced or treated as a deployment prerequisite.
- Actual GitHub-based Development Preview deployment/source SHA and live browser acceptance remain **UNVERIFIED**.
- No database migration or Development database mutation was made by these code/documentation commits.
- `main` was checked against baseline `0751b53d622a35a980f50ccb5b8c9ed9ce8afcbf` and was identical; no write to `main`.

### Next work
1. Inspect Actions for exact current `develop` SHA and first failing job/step if any.
2. Identify and verify the existing GitHub-based Development Preview path; do not use Vercel.
3. Complete financial lifecycle and concurrency acceptance on Development, with event isolation.
4. Record exact evidence before moving to the next module.

## Logging rule
Append one dated section per completed work round. Record baseline SHA, final SHA, files/migrations, tests, Actions run IDs and outcomes, Preview source SHA, Development database effects, and unresolved blockers. Keep facts separate from inherited historical notes.
