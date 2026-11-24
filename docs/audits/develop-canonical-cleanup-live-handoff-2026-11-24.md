# Conference Management — develop canonical cleanup live handoff (2026-11-24)

## Scope and non-negotiable rules
- Repository: `ramyawny37/conference-management-system-v1`.
- Edit `develop` and Supabase Development only. Never modify `main` or Production during this work.
- Vanilla JavaScript SPA, not React; Development Preview, not Vercel.
- One canonical route for Conference, Reservations and Warehouse. Remove legacy only after dependency tracing and replacement tests.
- Every conference must remain independent. Preserve guardian-child accommodation behavior, identity resolution, apologies/refunds, approved-device authorization, and financial reporting.
- Require source checks, CI, and live approved-device UI acceptance. CI alone is not live acceptance.

## Completed commits and verified CI
| Commit | Change | Evidence |
| --- | --- | --- |
| `12cf79610264979e4f584579f84fd7cfeb14657f` | Removed unused legacy local house modal HTML and `openHouseModal`, `closeHouseModal`, `saveHouse`, `deleteHouse` handlers. | GitHub Actions `45348311849` SUCCESS; `45348311695` SUCCESS. |
| `9dc1e8b8709691327ade82c3845c5e1d3882d95f` | Added regression test that forbids reintroduction of the local house modal/handlers while retaining canonical house directory operations. | GitHub Actions `45349020961` SUCCESS. |

## Current confirmed architecture
- `renderAccommodation()` renders `renderCanonicalAccommodation(canonicalAccommodationState())` for linked conferences. No canonical link shows a cloud-context error.
- `openRoomEditor()` and `saveRoomData()` are legacy-local handlers protected by `requireLocalOnlyAccommodationMutation()`; linked conferences cannot use their local writer.
- `roomModal` and `closeRM()` are SHARED by the canonical room editor; do not delete them as legacy.
- `editRoomData` and draft helpers remain widely referenced (guest picker, room moves, rendering). Do not remove a single function without complete reachability proof.
- `reconcileAccommodationRoomKeyHolders()` is invoked by `state.js` persistence and guarded by a test; preserve until proven replaceable.
- Existing `tests/canonical-accommodation-legacy-ui-parity.test.js` has assertions for the legacy room editor. Replace them with canonical-only behavior checks before retiring the legacy code.

## Pending gates (NOT PASS)
1. Full cross-file reachability map of local room editor/draft helpers and shared UI handlers.
2. Atomic removal of proven-unreachable legacy room code, plus updated regression tests, on `develop` only.
3. CI PASS for each cleanup commit; record commit SHA and run ID.
4. Approved-device live Development Preview acceptance: houses, rooms, refresh, permissions, guardian-child, Reservations, Warehouse, cross-module isolation. Not yet verified.
5. Final CSS/markup dead-code cleanup and modern compact UI visual acceptance.

## Audit findings requiring caution
- Supabase Development canonical tables and device-operation router are active. `platform.execute_conference_device_operation_phase1c_core` is a live fallback; do not delete it.
- Four public conference section-lock RPCs were statically traced through approved-device authorization. Negative-path live session tests remain pending.
- RLS advisor informational findings alone do not justify automatic policies or index changes.

## Execution protocol
After each commit append: UTC date, changed paths, why safe, exact SHA, test commands, GitHub Actions run ID/result, and outstanding FAIL/UNVERIFIED. Never label a read-only review as implementation. Do not delete existing evidence when updating this file.

## 2026-11-24 follow-up
- `2c174a52fc0b579e01a6019b552dc5e73ff8cd7c`: added this persistent in-repository handoff. No runtime code changes.
- `8d4c708011cbe4d9a7da6ca67ed1c5752358bdc5`: added source-boundary regression asserting canonical accommodation rendering cannot call the local room editor/writer, and that the local writer retains its guard. **CI not yet confirmed at the time of this entry**.
- The legacy room editor and shared modal have **not** been deleted. Visual/device-session acceptance remains **UNVERIFIED**.

### Verified CI for canonical renderer boundary
- `8d4c708011cbe4d9a7da6ca67ed1c5752358bdc5` -> GitHub Actions `45350095936` **SUCCESS** (verified after completion).
- `2c174a52fc0b579e01a6019b552dc5e73ff8cd7c` -> GitHub Actions `45349899007` **SUCCESS**.
- Source reachability observation: `openRoomEditor` still appears in a local room action constructed outside the active `renderAccommodation()` entry point. It is **not** safe to remove without mapping all callers and tests. Canonical entry point still calls only `renderCanonicalAccommodation()`.
- Next execution: replace or retire remaining legacy room actions and draft helpers only as a coherent tested unit; live approved-device smoke and visual acceptance still **UNVERIFIED**.

## 2026-11-24 canonical room draft transaction closure

### Baseline and scope

- Baseline: `a00c7810ed8600bdb51b3917fe701dddc6012be2` (`develop`, equal to `origin/develop` before this change).
- Final SHA: pending commit at the time of this entry.
- Scope is limited to the canonical Conference room editor, family accommodation transaction, and directly related tests. No Production connection or operational person data was used.

### Proven root causes and changes

- Removal was staged by hiding the row only; the draft retained the occupied bed and counters came from the original projection. `stageCanonicalAccommodationRoomRemoval` now marks the stay, releases its bed as an editable slot, cascades the local draft projection for linked children, and recomputes guest/child counts from active draft stays.
- The frontend payload and `save_conference_family_accommodation_draft` previously executed assignments before removals. The frontend now emits `remove -> move -> replace -> assign`; migration `20261124085051_canonical_family_room_draft_transaction_order.sql` makes the database order authoritative and applies room structure after removals but before additions.
- Accommodation removal previously called transport cleanup. The new forward-only migration keeps transport assignments intact for `accommodation_removed`; participation apology/deletion retain their existing transport cleanup ownership.
- Hydration failure previously returned a truthy committed result, allowing the editor to close without confirmed state. It now fails confirmation, and the room save verifies removed/assigned/replaced occupancies in the hydrated canonical projection before the final success toast.
- Deleted dead code: `refreshCanonicalRoomEditorAfterRemoval`. Repository search found no callers before deletion; the staged family save is now the sole room-editor removal path.

### Modified runtime and test files

- `script.js`
- `supabase/migrations/20261124085051_canonical_family_room_draft_transaction_order.sql`
- `tests/canonical-accommodation-atomic-replacement.test.js`
- `tests/canonical-accommodation-frontend-cutover-p6d.test.js`
- `tests/canonical-accommodation-legacy-ui-parity.test.js`
- `tests/canonical-family-accommodation-integration.test.js`
- `tests/conference-operational-lifecycle-migrations-postgres.test.js`
- `docs/audits/develop-canonical-cleanup-live-handoff-2026-11-24.md`

### Verification status

| Check | Result | Evidence |
| --- | --- | --- |
| JavaScript syntax, duplicate-function, undefined/dependency scans | PASS | `node --check` plus source scans after every edit group. |
| Previously failing canonical room suites | PASS | 102/102. |
| Canonical hydration and room save suites | PASS | 36/36. |
| Accommodation regression suite | PASS | 220/220, including real PostgreSQL concurrency/transaction tests. |
| Family removal preserves participation, guardian links and transport | PASS | Isolated PostgreSQL migration test; 3 family stays removed, 3 participations and child links retained, 3 transport assignments retained. |
| Full repository `tests/*.test.js` | FAIL (pre-existing cross-module baseline) | 1755 PASS, 46 FAIL, 1 TODO. Failures include missing retired files and unrelated Conference/Reservations/Warehouse allowlist contracts. Two accommodation expectations exposed by this change were updated and pass in the isolated suite. |
| `npm run check` | FAIL (Production-promotion baseline) | 663 PASS, 5 FAIL in `platform-promotion-readiness.test.js`; resolving them requires Production/public-config/cache-version changes explicitly outside this task. |
| Browser visual and approved-device acceptance | BLOCKED | `AGENTS.md` explicitly prohibits browser/automated UI tests in this workspace. |
| Development database deployment | PENDING | Migration is committed only after local verification; no Production database was accessed. |
| GitHub Actions / Development Preview provenance | PENDING | Must be filled after push and verification of the final SHA. |

### Non-regression boundaries

- No React, Vercel, `main`, Production, or real Mina/operational records were touched.
- The independent Cards tab, print layout, PNG export, and WhatsApp paths were not modified; the accommodation suite's card/PNG dimension regression passed.
- New-person and child creation remain staged inside the family payload and therefore roll back atomically or disappear on Cancel without a database write.
