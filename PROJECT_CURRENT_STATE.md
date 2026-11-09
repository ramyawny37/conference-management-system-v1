# Project Current State — Conference Management System

Last verified handoff: 2026-11-09 (Africa/Cairo)
Repository: `ramyawny37/conference-management-system-v1`

## Source control and delivery
- Development work only on `develop`; never modify `main` or Production.
- Last validated application-code SHA: `1b91e21729fd600b65833e05be31a6480220b368`.
- Commits after that SHA in the current handoff sequence are documentation-only; no application source was changed after the validated code SHA.
- `main` remains identical to production baseline `0751b53d622a35a980f50ccb5b8c9ed9ce8afcbf`.
- Development Preview uses the existing isolated GitHub Pages repository: `ramyawny37/conference-management-system-development-preview`.
- Vercel is retired and is not part of the application, hosting, Preview, or release path. Do not add Vercel/Gateway dependencies or require Vercel authorization.
- Supabase Development project: `gppwltrifgfxrkzvvxoe`. Never touch Production.

## Latest application changes
- `ee0b207c881cae5bee61e20dda198aa0dad0a8ee`: service-worker revision for shared Reservations/accommodation financial-cache assets.
- `ea72d0553b7f6e4410649ea7e2c83920b211f055`: dashboard uses payment-enriched booking rows for collected totals.
- `1b91e21729fd600b65833e05be31a6480220b368`: regression test for dashboard payment source.
- User manually confirmed the dashboard correction.

## CI and Preview evidence
- GitHub Actions run `42615328898` (run 752), SHA `ea72d0553b7f6e4410649ea7e2c83920b211f055`: **SUCCESS**.
- GitHub Actions run `42615343730` (run 753), SHA `1b91e21729fd600b65833e05be31a6480220b368`: **SUCCESS**. Every job step passed, including apology/refund regressions, platform regressions, identity replay, and local Development Preview validation.
- Local Development Preview validation passed 85 platform test files.
- Repeated failures immediately before these successes shared one cause: a literal escaped newline in `tests/reservations-detail-payment-cache-invalidation.test.js` caused `SyntaxError: Invalid or unexpected token`. Commit `cde054126a4363771ed86b2d59a0b3535034decb` corrected the test formatting; subsequent validation runs passed.
- GitHub Pages deployment run `42615914678`: **SUCCESS**. Its build log explicitly approved and checked out Platform SHA `1b91e21729fd600b65833e05be31a6480220b368`, passed 85-file validation and artifact guards, and deployed successfully.
- Preview URL: https://ramyawny37.github.io/conference-management-system-development-preview/
- Live browser acceptance of the remaining refund/rebooking UI is **UNVERIFIED**; deployment success is not a substitute for manual workflow acceptance.

## Supabase Development read-only audit
- No SQL writes, migrations, or data mutations were performed during this audit.
- Required canonical objects exist: bookings, payments, cancellation settlements, refund disbursements, event-scoped credit tables, operational booking view, and scoped writers.
- Aggregate Development state observed: 12 active bookings, 2 apologized, 1 deleted; 3 settlement rows, 1 refund disbursement, and 1 settlement with pending refund.
- Integrity checks: **0** settlement allocation mismatches; **0** refund-ledger vs settlement refunded-amount mismatches; no settlement over-refunded.
- Event-scope audit observed 1 conference-scoped event and 4 standalone events; each had its own scope partition in the inspected Development data.
- RLS is enabled on audited financial tables; no direct SELECT/INSERT grants to anon, authenticated, or service_role were present.
- Canonical payment record/void lock the booking row; cancellation locks booking and active payment rows; refund payout locks booking and settlement rows.
- Refund writer supports dated partial/multiple payouts, caps each payout at remaining pending plus retained non-refundable amount, records payment method/reference/reason/executor, and uses operation idempotency/audit. Reporting reads actual refunds from the disbursement ledger and scopes by event.

## Explicit blocker — credit lifecycle
- The current apology UI offers only “لا يُرد حاليًا” and “مع استرداد”; it does not offer credit.
- `cancel_booking_scoped` rejects positive `credit_amount` with `RESERVATIONS_EVENT_CREDIT_ISOLATION_REQUIRED`.
- `redeem_person_credit_scoped` is fail-closed with `RESERVATIONS_CREDIT_DESTINATION_REQUIRED`; there is no atomic destination-booking payment path.
- Event-scoped credit account/entry tables are empty. No credit balance has been issued or redeemed.
- Do not remove these guards or enable a credit UI until one complete event-scoped path exists for source settlement allocation, destination booking payment, cash-vs-credit reporting, idempotency, audit, and regression tests.

## Next actions
1. Implement the agreed event-scoped credit lifecycle as one atomic source-settlement-to-destination-booking payment path, with correct cash/credit reporting.
2. Complete live UI acceptance for pending refund, later partial/full disbursement, deletion financial history, and same-event rebooking without manual refresh.
3. Keep using the existing GitHub Pages Development Preview workflow. No new hosting provider or parallel path.
4. Record exact run IDs, Preview source SHA, test evidence, and blockers in this file and `WORK_LOG.md`.

## Product and architecture rules
- Arabic, non-React SPA; one canonical implementation only.
- Each event is fully standalone in people, bookings, accounts, payments, refunds/credits, accommodation, transport, dashboards, and reports.
- Apology preserves history and allows same-event rebooking; deletion removes event operations but preserves central person identity and financial history.
- Apologized participants remain visible as “معتذر”, are excluded from active counts and completion, and open read-only details.
- No legacy/parallel path, demo data for acceptance, Production changes, or manual-refresh dependency.
- Completion requires root-cause fix, Development database verification, frontend state update, regression tests, successful Actions for exact application SHA, matching GitHub Pages Preview, and live operational acceptance.
