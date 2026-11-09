# Architecture and Business Policies

These are binding product and engineering constraints for the Conference Management System.

## Delivery and environments
- Work only on Git branch `develop`.
- Use Supabase Development project `gppwltrifgfxrkzvvxoe` only.
- Never modify `main`, Production, or production data.
- No auto-merge, no force push, and no claiming deployment/acceptance without direct evidence.
- Use the existing Arabic SPA architecture (vanilla JavaScript/CSS/HTML); do not introduce React.
- One canonical path per capability. No parallel/legacy implementation, fallback path, temporary workaround, or accumulating duplicate code.
- Fix root causes, preserve existing supported behavior, test the complete connected lifecycle, then retire obsolete code.

## Event isolation
- Every event is fully standalone.
- People/participations, reservations, operational pricing, payments, refunds, credits, accommodation, transport, dashboards, and reports are scoped to their event.
- No cross-event totals, person identity leakage, payment allocation, refund/credit redemption, or operational state.

## Reservations and people
- Central person records are managed through the central people bank.
- During reservation entry, selecting an existing person loads all available identity fields (name, phone, church, gender, date of birth, age derived from DOB, and other supported fields).
- Editing an existing person's details must explicitly choose between updating the central person record and saving reservation-only data; never silently update central identity.
- Manual identity resolution is explicit and auditable. Never auto-merge people.
- Prevent duplicate active registration of the same person in the same event. A person who apologized may register again in that same event; the new booking must preserve the prior apology history without treating it as an active duplicate.
- Booking type selection starts empty and requires an explicit choice. Persist the selected type and its event-scoped price/period semantics.
- Dynamic attendance periods and event-defined booking types remain supported.

## Cancellation, apology, refund, and credit — one lifecycle
- Apology is not equivalent to deletion.
- An apologized booking remains visible in the event's reservations/participants list with status `معتذر`, but is excluded from active attendance and operational completion counts.
- An apologized person must open read-only details, not the edit form.
- Apology removes the person's active operational participation where required, but does not delete the central person record.
- A deleted booking is removed from the event's dependent operational modules according to the deletion contract; central person identity remains.
- Rebooking after apology is allowed in the same event and must not overwrite historical booking/settlement records.
- The financial decision may be no-refund at apology time, with a later refund after or during the event. The single settlement lifecycle must support later execution without a second/parallel workflow.
- Non-refunded amounts remain recognized as apology-related retained revenue.
- Refunds record actual disbursed amount, date, payment method, reference, reason, and executor. Partial/multiple disbursements must remain possible.
- Credit is an event-scoped/person-linked future entitlement allocated through supported payment methods and traceable to its source. Never cross-link events.
- Reports distinguish active bookings, apologized bookings, collected amounts, retained non-refunded apology revenue, actual refunds/disbursements, and available credit. Do not count an apology as an active participant.
- Show booking value, paid amount, and remaining balance for all relevant booking states.

## Accommodation and guardian/child linkage
- Child remains fully linked to guardian for participation and accommodation lifecycle even with an independent bed or a different room.
- Independent bed/room does not mean independent guardian relationship.
- If child and guardian share the same room, moving guardian moves the shared child according to the established shared-stay behavior.
- If child has a separate room, moving guardian alone does not move that child; child can be moved separately.
- Deleting/removing guardian participation removes linked child participation/accommodation from dependent event operations under the agreed deletion policy.
- Shared child stay must match guardian room/period; independent child stay may use a different room but must satisfy guardian-stay coverage.
- Automatic extra beds and their counts must update immediately without requiring a page refresh.

## UI, state, and reporting
- Mutations must update all dependent lists, counters, reports, and dashboards without manual refresh.
- A participant row should open the intended details consistently; preview panels must be closable and must not auto-open on initial page load.
- Apologized participants are read-only.
- Preserve the established Arabic RTL interface and existing visual reference behavior.
- No synthetic/demo data for acceptance; use controlled Development test records and clearly identify them.
- Financial reporting must use authoritative payment-enriched/operational data, not stale booking snapshots or unrelated raw collections.

## Definition of done
A task is complete only when all relevant layers are verified:
1. Root cause and canonical data/API contract.
2. Database constraints/RPC/permissions when applicable, in Development only.
3. Frontend behavior and immediate state refresh.
4. Focused regression tests plus relevant suite.
5. GitHub Actions successful for exact final SHA.
6. Development Preview built from exact final SHA.
7. Visual and operational acceptance on the real flow.
8. No regression to adjacent modules or event isolation.
9. Exact evidence recorded in `PROJECT_CURRENT_STATE.md` and `WORK_LOG.md`.

Use explicit statuses: PASS / FAIL / BLOCKED / UNVERIFIED. Never turn missing evidence into PASS.
