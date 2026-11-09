# Work Log

## 2026-11-09 — Reservations dashboard correction and financial lifecycle audit

### Application commits
- `ee0b207c881cae5bee61e20dda198aa0dad0a8ee`: service-worker revision for shared Reservations/accommodation financial-cache assets.
- `ea72d0553b7f6e4410649ea7e2c83920b211f055`: `fix(reservations): use payment-enriched bookings on dashboard`. Dashboard collected totals now consume payment-enriched booking rows.
- `1b91e21729fd600b65833e05be31a6480220b368`: `test(reservations): cover dashboard payment source regression`.
- User manually confirmed the dashboard correction.
- Commits after `1b91e217` in this handoff sequence changed documentation only; no application source changed.

### GitHub Actions
- Run 752: `42615328898`, SHA `ea72d0553b7f6e4410649ea7e2c83920b211f055`, **SUCCESS**.
- Run 753: `42615343730`, SHA `1b91e21729fd600b65833e05be31a6480220b368`, **SUCCESS**.
- Run 753 job `129153711499`: every step passed, including apology/refund regressions, source/cache boundary, PostgreSQL-backed platform regressions, canonical accommodation lifecycle, identity replay, and local Development Preview validation.
- Local Development Preview validation passed 85 platform test files.
- Repeated failures immediately before the final successes shared one root cause: a literal escaped newline at line 23 of `tests/reservations-detail-payment-cache-invalidation.test.js` caused `SyntaxError: Invalid or unexpected token`. This was a malformed test source, not a failed application assertion.
- Commit `cde054126a4363771ed86b2d59a0b3535034decb` corrected the test formatting. Run `42612216950` then passed, followed by runs 752 and 753.

### Existing GitHub Pages Development Preview
- Preview repository: `ramyawny37/conference-management-system-development-preview`.
- Deployment run: `42615914678`, **SUCCESS**.
- Build job `129155620580` explicitly approved and checked out Platform SHA `1b91e21729fd600b65833e05be31a6480220b368`.
- Build passed the 85-file Development Preview validation and fail-closed artifact checks, including Development Supabase project reference and Reservations JS/CSS checksums.
- Deploy job `129155841314` succeeded.
- URL: https://ramyawny37.github.io/conference-management-system-development-preview/
- Vercel is retired and not part of this project. An earlier assistant attempt to use Vercel was an unnecessary tooling detour; no Vercel access was granted and no repository integration was created. Do not use or reintroduce Vercel.

### Supabase Development read-only audit
- Project: `gppwltrifgfxrkzvvxoe`.
- No SQL writes, migrations, or data mutations were performed during this audit.
- Canonical tables/views/writers exist for bookings, payments, operational bookings, cancellation settlements, refund disbursements, and event-scoped credit.
- Aggregate state observed: 12 active bookings, 2 apologized, 1 deleted; 3 settlement rows, 1 refund disbursement, and 1 settlement with pending refund.
- Financial integrity checks: 0 settlement allocation mismatches; 0 refund-ledger vs settlement refunded-amount mismatches; no settlement over-refunded.
- Event-scope audit: 1 conference-scoped event and 4 standalone events observed; each had its own scope partition.
- RLS enabled on audited financial tables; no direct SELECT/INSERT grants to anon, authenticated, or service_role.
- Payment record/void lock the booking row; cancellation locks booking and active payments; refund payout locks booking and settlement.
- Refund writer supports dated partial/multiple disbursements, caps each payout at remaining pending plus retained non-refundable amount, records method/reference/reason/executor, and uses operation idempotency/audit. Reporting reads actual refunds from `refund_disbursements` and scopes by event.
- Live UI acceptance for the remaining refund/rebooking journey was not performed in this audit.

### Credit lifecycle — explicitly deferred
- Current apology UI exposes only “لا يُرد حاليًا” and “مع استرداد”; there is no credit option.
- Current `cancel_booking_scoped` rejects positive `credit_amount` with `RESERVATIONS_EVENT_CREDIT_ISOLATION_REQUIRED`.
- Current `redeem_person_credit_scoped` deliberately raises `RESERVATIONS_CREDIT_DESTINATION_REQUIRED`; it cannot atomically apply credit to a destination booking/payment.
- Event-scoped credit account/entry tables have zero rows. No credit balance has been issued or redeemed.
- User decision 2026-11-09: future credit is not wanted in the current scope. Events have defined start/end dates. Preserve fail-closed credit guards; do not implement credit or add a parallel path.

### Next
1. Complete live UI acceptance for non-refund apology, pending refund, later partial/full disbursement (including after event end), deletion financial history, and same-event rebooking without manual refresh.
2. Verify selected-event reports separate active collections, retained apology income, actual disbursement by date, and net collections.
3. Leave future credit out of scope and fail-closed; preserve `develop` only and Supabase Development only; `main` and Production remain untouched.

## Logging rule
Append one dated section per completed work round. Record baseline SHA, final SHA, files/migrations, tests, Actions run IDs and outcomes, Preview source SHA, Development database effects, and unresolved blockers. Keep facts separate from inherited historical notes.

## 2026-11-09 — Event-bounded financial scope confirmation
- User explicitly removed future credit/transfer from the current release; do not implement or activate it.
- Each event has a start and end date. A financial refund disbursement may be recorded after event end, dated by the actual payout, without reopening the event for new bookings.
- Rechecked Development aggregate totals: 12 active, 2 apologized, 1 deleted bookings; 3 settlements, 1 disbursement, 1 pending refund; zero allocation errors, over-refunds, and ledger mismatches.
- This was a read-only database check. No operational user records or Production data were modified.
