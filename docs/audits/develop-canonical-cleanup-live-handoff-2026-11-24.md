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
