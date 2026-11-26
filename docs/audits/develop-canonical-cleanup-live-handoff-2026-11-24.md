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
- Implementation SHA: `53fec6020806a17d191d2d22bdd0e778e6e80ed4`.
- Final evidence-only handoff SHA: the commit containing this updated report; runtime files are identical to the implementation SHA.
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
| Development migration delivery | PASS | Forward-only migration is committed on `develop`; no Production database was accessed. The deployment pipeline owns application to Supabase Development. |
| GitHub Actions | PASS | Conference `45360960934`; Reservations `45360960850`; both completed successfully at implementation SHA `53fec6020806a17d191d2d22bdd0e778e6e80ed4`. |
| Development Preview provenance | PASS | Preview run `45361523193` completed successfully. Deploy job `138332799972` logged `Deploying Platform develop SHA 53fec6020806a17d191d2d22bdd0e778e6e80ed4`. |

### Non-regression boundaries

- No React, Vercel, `main`, Production, or real Mina/operational records were touched.
- The independent Cards tab, print layout, PNG export, and WhatsApp paths were not modified; the accommodation suite's card/PNG dimension regression passed.
- New-person and child creation remain staged inside the family payload and therefore roll back atomically or disappear on Cancel without a database write.

## 2026-11-24 final accommodation removal and transaction-order closure

### Baseline and implementation

- Requested baseline: `22c386dbdd82b175faee92feb7afed90a9ad40bb` on `develop`.
- Runtime/migration implementation: `d0e108c540de32102d6e9c0f44446fd1e77ed23c`.
- Final handoff SHA is the commit containing this report; no runtime code changed after the implementation SHA.
- No `main`, Production, operational person data, Cards/print, PNG, or WhatsApp path was touched.

### Root cause closed

- Removing the room key holder invokes `clear_conference_room_key_on_stay_delete`, which increments `conference_room_assignments.revision`. The family draft now validates client revisions before mutation under its existing locks, then uses the resulting current revisions for the structure write under the same transaction and locks.
- The earlier ordering still attempted a capacity reduction before moving an occupant out. Structure expansion remains before a move when capacity is needed, while equal/reduced base or extra-bed capacity is applied after moves free their beds. The authoritative stay order remains `remove -> move -> replace -> assign`.
- Accommodation removal continues to preserve participation, guardian-child links, and transport. Apology/deletion retain their existing lifecycle cleanup ownership. Historical stay segments remain preserved by the existing effective-day cleanup contract.

### Files changed in the final closure

- `supabase/migrations/20261124085051_canonical_family_room_draft_transaction_order.sql`
- `tests/canonical-family-accommodation-integration.test.js`
- `tests/canonical-family-room-draft-transaction-postgres.test.js`
- `docs/audits/develop-canonical-cleanup-live-handoff-2026-11-24.md`

No dead runtime path was found in this final pass, so none was deleted without reachability proof.

### Verification evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Isolated PostgreSQL transaction contract | PASS | Real migration applied to a disposable database; key-holder removal + structure change + assignment ordered `remove,structure,assign`; capacity shrink ordered `move,structure`; replay returned duplicate; stale revisions failed; injected assignment failure rolled back the complete transaction. |
| Targeted family/lifecycle suites | PASS | 95/95 tests. Includes cross-room guardian/child cleanup, participation and transport preservation, replace/move, concurrency, and current/future period behavior. |
| All accommodation suites | PASS | 221/221 tests. Includes historical stay preservation and unchanged Cards/PNG dimensions. |
| Development Preview validation | PASS | `npm run check:development-preview`. |
| Static syntax, duplicate function, undefined/dependency and diff checks | PASS | `node --check`, declaration scan (575 functions, no duplicates), dependency reference scan, executed PostgreSQL paths, and `git diff --check`. |
| `npm run check` | FAIL (pre-existing/out of scope) | 663 PASS, 5 FAIL, all in `platform-promotion-readiness.test.js`; they require Production/public-config/cache-revision changes prohibited by this task. |
| Browser/visual acceptance | BLOCKED | `AGENTS.md` explicitly prohibits browser and automated UI tests in this workspace. |
| GitHub Actions for implementation | PASS | Run `45366718742`, “Validate Reservations integration on develop”, completed successfully for `d0e108c540de32102d6e9c0f44446fd1e77ed23c`. Conference workflow did not trigger because the final paths do not match its path filter; Conference accommodation suites were run locally as listed above. |

### Supabase Development application

- Confirmed linked project: `gppwltrifgfxrkzvvxoe` only.
- A direct repository `db push` was rejected as unsafe because old local/remote migration drift would include unrelated files. An isolated CLI worktree fetched the remote migration history, then a dry run proved that only `20261124085051_canonical_family_room_draft_transaction_order.sql` would apply.
- Migration `20261124085051` was then applied alone through the approved CLI path. Remote history records name `canonical_family_room_draft_transaction_order` with 7 statements.
- Post-application checks confirm: ordered remove/move markers, current locked room and assignment revision reads, deferred capacity shrink, active `clear_conference_room_key_on_stay_delete` trigger, SECURITY DEFINER removal function, and EXECUTE limited to `service_role`. Supabase health advisor returned no findings.
- Existing older migration-history drift remains visible and was deliberately not repaired or hidden because it predates and exceeds this scope.

## 2026-11-24 truthful administrative removal correction

### Baseline and proven failure

- Baseline: `9bc2c64f3acf7e5ef879792c4b324fc57502d3af` on `develop`.
- Implementation SHA: `da3bcc95330eeaf140e55678bd9815b574e65e71`.
- Production logs proved the reported HTTP 500 was `ACCOMMODATION_ROOM_CAPACITY_EXCEEDED` from `assign_conference_accommodation`, called by `save_conference_family_accommodation_draft`. The preceding removal was a no-op, so the full room never released its bed before the replacement assignment.
- The false success originated when `20261101213650_canonical_family_lifecycle_final_cutover.sql` routed administrative removal through the effective-day participation cleanup. `20261124085051_canonical_family_room_draft_transaction_order.sql` later preserved that call and returned `deleted: true` without proving the requested occupancy disappeared.
- For an active conference whose dates had elapsed, `effective_day=conference_days+1`; an open-ended stay already ending at that boundary was skipped. Hydration therefore correctly found the supposedly removed occupancy still present.

### Corrected central contract

- New migration: `20261124101624_administrative_accommodation_removal_contract.sql`.
- `accommodation_removed` is now an authorized administrative correction: it deletes the selected participant's accommodation rows, and the existing family ownership rule applies the same correction to linked children across rooms.
- `participation_apologized` and `participation_deleted` retain the prior effective-day lifecycle behavior. No parallel RPC or frontend path was added.
- `remove_conference_accommodation` now raises `ACCOMMODATION_REMOVAL_NOT_APPLIED` if the requested occupancy remains; it cannot return success for a no-op.
- Participation, central Person, guardian links, transport, leases, revisions, idempotency, room-key cleanup, and audit ownership remain unchanged. Audit metadata explicitly records `administrativeCorrection=true` while retaining the previous row in `old_values`.
- Completed conferences remain protected by the existing `require_conference_accommodation_context(..., true)` guard.

### Files and cleanup

- Added `supabase/migrations/20261124101624_administrative_accommodation_removal_contract.sql`.
- Updated `tests/canonical-family-room-draft-transaction-postgres.test.js` with real PostgreSQL temporal, family, key, atomicity, replay, and conflict cases.
- Updated `tests/canonical-family-accommodation-integration.test.js` to reject reintroduction of the mixed administrative/lifecycle contract.
- No runtime JavaScript or design file changed. No dead runtime path was removed because dependency tracing found one active canonical path and no proven duplicate.

### Verification and deployment

| Gate | Result | Evidence |
| --- | --- | --- |
| Reported past-date active-conference scenario | PASS | Disposable PostgreSQL used 2026-11-01 through 2026-11-04 while database date was 2026-11-24; removal freed the key-holder bed and the same transaction assigned its replacement. |
| Before/during/after dates and completed conference | PASS | Administrative removal succeeded for active conferences independent of wall-clock phase; completed status raised `COMPLETED_CONFERENCE_IMMUTABLE`. |
| Family and lifecycle | PASS | Guardian removal cleared linked child stays across rooms; child-only removal retained guardian; participation and transport remained; historical apology cleanup retained its previous effective-day behavior. |
| Atomicity and concurrency | PASS | Remove/add/structure, move/shrink, rollback on injected failure, replay, stale revisions, and room-key trigger passed in isolated PostgreSQL. |
| Targeted suites | PASS | 96/96 tests. |
| All accommodation suites | PASS | 222/222 tests. Cards/print/PNG/WhatsApp contracts remained untouched. |
| Development Preview validation | PASS | 658/658 tests across 88 platform test files. |
| `npm run check` | FAIL (pre-existing/out of scope) | 663 PASS, 5 FAIL, all Production-promotion requirements prohibited by this task. |
| GitHub Actions | PASS | Run `45374110040` succeeded for implementation SHA `da3bcc95330eeaf140e55678bd9815b574e65e71`. |
| Supabase Development | PASS | Dry-run listed only `20261124101624`; it was applied to `gppwltrifgfxrkzvvxoe`. Remote history records 8 statements; post-apply function definitions, ACLs, key trigger, migration list, and advisors passed. |
| Browser/manual operational acceptance | BLOCKED | `AGENTS.md` prohibits browser and automated UI tests. No real guest or room data was mutated for testing. |

No `main`, Production, Vercel, React, operational guest data, or independent Cards/print/PNG/WhatsApp path was touched.


## 2026-11-24 user operational acceptance and continuation

- User confirmed individual removal and addition/save work after the administrative removal migration and refresh. Combined remove/add in one save is not separately confirmed by the user; isolated PostgreSQL coverage passed.
- Empty slot text `يُطبّق عند حفظ الغرفة` remains visible after reopening because it is unconditional in the existing template. User explicitly deferred this cosmetic issue; do not change it in this round.
- Resume central Conference cleanup and design unification, starting with reachability audit of room editor dependencies. Do not remove functions based on naming alone. Preserve accepted accommodation behavior, family rules, cards/print/PNG/WhatsApp, and reservations. Develop and Supabase Development only; no main/Production.

### Legacy room editor reachability audit
- `getCanonicalConferenceCoreLink(id)` returns a canonical link for every nonempty trimmed ID; `requireLocalOnlyAccommodationMutation` throws `LINKED_CONFERENCE_LEGACY_ACCOMMODATION_FORBIDDEN` for such a current conference.
- `openRoomEditor` and `saveRoomData` are guarded local-only paths; the latter writes `current.houses` from `draftHouses` and invokes `save()`. The room settings action still contains a canonical/local conditional. Local transfer and room management helpers also share this guard.
- `renderRoomEditorFromDraft` and `applyEditorFormToDraftRoom` have local editor and transfer dependencies. Shared DOM and helper dependencies must be audited before deletion. No runtime code changed in this audit. Next: verify conference ID invariants and cross-file callers/tests, then remove the proven dead closure atomically with regression coverage. No Codex used.


### Unreachable conference selector cleanup
- Runtime commit `2b98c6abed67ed5d6a46c878b88034a782c52338`: removed 3,343 characters after unconditional return in `showSelectConferenceModal`; preserved active startup flow and public function name.
- GitHub Actions confirmed success: Reservations integration `45380627812`, Conference canonical people flow `45380627860`. Preview deployment and independent static scans not yet verified. No browser automation (AGENTS.md). No database or Production changes.
- Next: audit remaining selectConfModal references and legacy room editor closure, including cross-file tests, before deletion.


### Obsolete selection modal cleanup
- `0a6a7bf06067ccd7b56a76c60cf1b0abcb3fff2e`: removed two obsolete selection-modal cleanup references.
- `9801a75bddd211b9c4c13feea32b1cae38cafa61`: removed six exclusive CSS rules and stripped obsolete selectors from thirteen shared rules, preserving completed-conference selectors.
- CI and preview acceptance pending; no database change. Legacy room editor removal remains pending dependency/test review.

### Continued dependency audit (2026-11-24)
- Verified develop HEAD `413a4f00a49ca908c74869b3f5c5458f9e986139`. Combined status and PR-filtered workflow lookup returned empty; current push CI and preview remain UNVERIFIED.
- Scanned declarations in script.js lines 3769–5380 against the remainder of that file. External references include `cloneHouseTemplateToConference` (10199), `renderActiveRoomsManager` (9344), `openRoomEditor` (6584, liveSearch conditional), `closeRM` (3194, 3550, 3565, canonical), `bindGuestPersonRow` (8993), and `bindChildPersonRow` (9004, 9010). This is a textual intra-file scan, not complete cross-file reachability proof.
- Reviewed `tests/canonical-accommodation-legacy-ui-parity.test.js`: existing tests explicitly require legacy save-button binding, local guard delegation, and local writer guard. Preserve canonical save/cancel/failure behavior when retiring the legacy closure. Do not weaken tests just to pass.
- Next: trace person-dialog callbacks, active-room manager, house-template application, HTML event handlers, and cross-file tests on develop. GitHub code search covers default branch only, so it cannot prove develop-wide absence. No runtime deletion or database change in this audit; static/runtime tests and live acceptance remain UNVERIFIED. Deferred Arabic slot text unchanged. No Codex used.


### Continued Conference design cleanup — 2026-11-24
- `962230d229cce9ecb5fc686b4051f3c8ad15c5e9`: removed redundant room body padding override.
- `4adb9e5eec43fa1d24f0063972d260af1ae46af7`: merged adjacent identical-selector floor title and arrival declarations without changing declaration order or responsive rules.
- Scope: existing central design, Conference module first; retire competing CSS, preserve mobile/tablet/desktop, operational behavior and print/cards. No new design system. CI and visual acceptance UNVERIFIED. Develop only; no database changes. Remaining card header and other overlapping selectors require cascade and dependency audit before removal.


### Conference CSS cleanup continuation — 2026-11-24
- `be47cb90f365e30444c18574fe90942c8fc981a2`: consolidated adjacent accommodation occupancy badge and house metric declarations; CI run `45389615497` succeeded.
- `9027ac2e9927e1f8c49ec6cdadeecece9e5fbf56`: removed the superseded first `gap:var(--app-space-2)` declaration from `.accommodation-dashboard .accommodation-house-metrics`; the effective later `gap:4px`, grid columns and flex behavior remain unchanged.
- No renderer, operational behavior, breakpoint, mobile/tablet rule, or Supabase object changed. This is a cascade-preserving cleanup only.
- Pending: verify exact-SHA CI and Development Preview for `9027ac2`; continue whole-module CSS ownership/dependency audit. Visual acceptance remains pending; no claim of full legacy-design removal.

## 2026-11-24 legacy room editor retirement

### Baseline and implementation

- Baseline after integrating concurrent `develop` cleanup: `98462ffa7bc7ec21a961686166f147f774f43b60`.
- Implementation: `26f22932f7e426b9441a095f7a821d04a9b31211`.
- No database, migration, Supabase project, `main`, Production, Cards/print, PNG, WhatsApp, or Reservations runtime file was changed.
- The deferred text `يُطبّق عند حفظ الغرفة` was not changed.

### Reachability proof

- `getCanonicalConferenceCoreLink(localConferenceId)` returns a canonical link for every non-empty Conference id. `renderAccommodation()` renders only `renderCanonicalAccommodation(canonicalAccommodationState())`; its non-linked branch is an error state, not a local renderer.
- Repository-wide JavaScript, HTML, CSS, inline-handler, dynamic-string, and test scans found the legacy room editor reachable only from its own generated handlers plus one Search-tab conditional fallback.
- The Search-tab fallback was the only caller outside the legacy block. It now dispatches directly to `editCanonicalHouseRoom(roomId)`.
- `roomModal`, `closeRM()`, room fields, canonical responsive selectors, and `reconcileAccommodationRoomKeyHolders()` remain because they are shared or have proven persistence consumers.
- The old `guestRowId` / `childRowId` person-dialog branches were generated only by the retired editor. Canonical person creation continues through `accommodationAssignment` and `accommodationRoomSlotKey`.

### Deleted legacy unit

- Removed `editRoomData` / `draftHouses` ownership and the complete legacy editor call graph: `openRoomEditor`, `renderRoomEditorFromDraft`, `applyEditorFormToDraftRoom`, `saveRoomData`, `openMoveGuestDialog`, `openMoveRoomDialog`, `pickTargetRoomPrompt`, legacy guest/child row binders, the legacy guest picker, and partial-room transfer helpers.
- Removed the dead `partialTransferModal`, its inline handlers, and all `#partialTransferModal` CSS.
- Removed the dead legacy guest-picker CSS and obsolete child-row markup/CSS. The canonical slot picker and canonical family-child dialog remain unchanged.
- Removed the unused static child-add button from `roomModal`; the canonical editor continues to create its owned family-child action dynamically.
- Net implementation change: 63 insertions and 1,551 deletions across 10 files.

### Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Syntax, duplicate functions, dependency and inline-handler scans | PASS | `node --check`; zero duplicate declarations; retired names absent from active JS/HTML/CSS; remaining unresolved inline names are established external/browser owners (`showAuthView`, `signOut`, `ge`, `click`, `preventDefault`). |
| Canonical room/design regression selection | PASS | 107/107 tests, including central draft, replacement, permissions, house directory, responsive compact room UI, and design foundation. |
| Legacy-retirement boundary tests | PASS | Tests now require the old editor, picker, transfer modal, and local save owner to remain absent while requiring canonical slot/person/save ownership. |
| `npm run check:development-preview` | PASS | 658/658 tests across 88 platform test files. |
| `npm run check` | FAIL (pre-existing/out of scope) | 663 PASS, 5 FAIL in the existing Production-promotion baseline; resolving them requires prohibited Production/public-config/cache changes. |
| Browser visual and operational acceptance | BLOCKED | `AGENTS.md` prohibits browser and automated UI tests in this workspace. No visual acceptance is claimed. |
| Supabase Development | NOT NEEDED | This was a frontend/test cleanup with no schema or data change. |

### Files changed

- Runtime: `script.js`, `index.html`, `style.css`.
- Regression contracts: `tests/canonical-accommodation-legacy-ui-parity.test.js`, `tests/conference-legacy-functional-canonical-cutover.test.js`, `tests/conference-section-permission-ui.test.js`, `tests/legacy-linked-runtime-state-retirement-p6f.test.js`, `tests/people-accommodation-regressions.test.js`, `tests/room-mobile-input-ux.test.js`, `tests/room-person-picker-free-text.test.js`.
- Evidence: this handoff document.

### Remaining gates

- GitHub Actions passed for evidence SHA `657ded2661d0299563f3e4007a6959f30d04684b`: Conference run `45392715781` and Reservations run `45392715756`.
- Development Preview run `45393134015` passed; live `development-preview-sources.json` recorded both `platform.ref` and `platform.sha` as `657ded2661d0299563f3e4007a6959f30d04684b`. The final report-only successor SHA must receive the same exact-SHA verification before handoff.
- Manual Desktop/Tablet/Mobile visual acceptance and approved-device operational smoke remain BLOCKED by the local browser-test prohibition and require an authorized manual pass.
- Remaining local-only house/active-room compatibility functions are still guarded by `requireLocalOnlyAccommodationMutation()` and were not deleted in this unit because their wider template-management dependencies were outside the proven room-editor closure.

## 2026-11-24 Conference design-token canonical cutover

### Accepted baseline and protected behavior

- Baseline: `e745037972f73a7623e133212b670f0aaef66476` on `develop`, matching `origin/develop` with a clean worktree before this unit.
- User manually accepted deployed individual guest removal, guest addition, and room save from the previous unit: PASS. The deferred text `يُطبّق عند حفظ الغرفة` remains unchanged by explicit user decision.
- This unit changes CSS ownership and cache revisions only. Accommodation save/move/remove/family logic, permissions, database/RPC contracts, Reservations behavior, Cards/print/PNG/WhatsApp, `main`, and Production remain untouched.

### Ownership and cutover evidence

- Before: active CSS contained 2,123 `--app-*` references, 15 `--ds-*` references, 29 `--acc-*` references, and ten local `--acc-*` definitions under `#tab0`.
- Exact semantic aliases now consume `--platform-*` directly. Approved Conference density values that are intentionally smaller than the general platform scale use a single reusable `--platform-compact-*` contract in `shared-design-tokens.css`.
- Removed the complete `--app-*` and `--ds-*` compatibility-definition blocks and the local `#tab0` `--acc-*` alias block. Active runtime CSS now has zero definitions or consumers for all three prefixes.
- Shared foundations/components remain owned by `shared-design-tokens.css`; Conference layout and responsive geometry remain in `style.css`; shell geometry remains in `canonical-platform-shell.css`; Reservations-specific layout remains in its existing module stylesheet.
- CSS load order is unchanged. Revisioned URLs in `index.html` and `service-worker.js` were advanced atomically so deployed clients cannot mix old token definitions with new consumers.

### Before / after

| Measure | Before | After implementation |
| --- | ---: | ---: |
| Active CSS `--app-*` references | 2,123 | 0 |
| Active CSS `--ds-*` references | 15 | 0 |
| Active CSS `--acc-*` references | 29 | 0 |
| Local `--acc-*` definitions | 10 | 0 |
| `style.css` bytes | 320,496 | 333,157 |
| `shared-design-tokens.css` bytes | 17,916 | 15,218 |
| `canonical-platform-shell.css` bytes | 10,665 | 10,675 |

The Conference stylesheet grew because the canonical and compact token names are intentionally explicit; no selector, renderer, or business path was duplicated. Final tests, commit SHA, CI run IDs, and deployed Preview SHA are recorded below after those gates complete.

### Local verification

| Gate | Result | Evidence |
| --- | --- | --- |
| Syntax and static ownership | PASS | `node --check` passed for active JavaScript/service worker; duplicate-function scan found 0 duplicates across 498 `script.js` declarations; `git diff --check` passed; active non-test runtime scan found zero `--app-*`, `--ds-*`, or `--acc-*` references. |
| Design/accommodation selection | PASS | 30/30 tests, including compact room width, RTL grid, room editor geometry, shared component ownership, and exact cache graph. |
| Development Preview regression | PASS | 658/658 tests across 88 platform files. |
| `npm run check` | FAIL (unchanged baseline/out of scope) | 663 PASS, 5 FAIL: the same prohibited Production promotion/public-config/version/cache requirements; no new failure was introduced. |
| Browser visual acceptance | BLOCKED | `AGENTS.md` prohibits browser and automated UI tests. User must perform the final Desktop/Tablet/Mobile review after exact-SHA Preview publication. |
| Supabase / database | NOT NEEDED | No schema, RPC, migration, environment, or operational data change. |

### Implementation CI and Preview evidence

- Implementation commit: `7e68069c82044386b252354f1ceff4ac9924da6c` (`refactor(conference): complete canonical design token cutover`).
- Conference canonical people flow: run `45412373703`, PASS on the implementation SHA.
- Reservations integration: run `45412373505`, PASS on the implementation SHA.
- Development Preview: run `45412872313`, PASS. The live `development-preview-sources.json` recorded both `platform.ref` and `platform.sha` as `7e68069c82044386b252354f1ceff4ac9924da6c`; the revisioned token asset returned HTTP 200 with publication timestamp 2026-11-24 14:20 UTC.
- This evidence update is documentation-only. Its successor SHA must receive the same exact-SHA CI and Preview provenance check before final handoff.

## 2026-11-24 final Conference component-ownership closure

### Baseline and protected acceptance

- Baseline: `c65059ad49e395e3864fb48d598f8770de3751e4`, clean and equal to `origin/develop` before implementation.
- The previous room-editor retirement, manual remove/add/save acceptance, token cutover, appearance acceptance, CI, and exact-SHA Preview publication remain closed and were not reimplemented.
- No Arabic copy, accommodation operation, Cards/print/PNG/WhatsApp behavior, Reservations runtime, database, Supabase object, `main`, or Production asset changed.

### Component ownership matrix

| Family | Central owner | Active Conference consumers | Removed local ownership | Retained local declarations and reason | Status |
| --- | --- | --- | --- | --- | --- |
| Buttons | `shared-design-tokens.css` `.btn`, `.btn-sm`, semantic variants, focus/disabled states | Accommodation, transport, reports, settings, houses, users, startup and active dialogs | Repeated display/alignment/gap/border/radius declarations in transport toolbar/footer, transport rider/bulk controls, reports actions, room guest buttons, settings/house/user action groups | Width, compact height, padding, wrapping, grid/flex placement, business colors, and mobile touch sizing remain layout/density responsibilities | PASS |
| Cards and titles | Central `.card` / `.card-title` | Settings accounts, reports, house library, accommodation KPI cards | Repeated border/background/shadow and title color/margins where the central value is effective | Compact padding, local section dividers, KPI grid geometry, specialized radius and functional zero-margin composition remain scoped | PASS |
| Dialog/backdrop | Central `.ui-dialog*` plus centrally owned active `.overlay` / `.modal` compatibility contract | Static and generated Conference room, transport, house, person, search, account and confirmation dialogs | Unscoped `.overlay` and `.modal` definitions removed from `style.css` | `.app-modal`, headers/bodies, sticky footers, widths and business sections remain scoped; opening, closing, backdrop click, save and focus JavaScript is unchanged | PASS |
| Fields and choices | Central standard input/select/textarea, focus and disabled contracts | All Conference forms and dialogs | No unsafe broad deletion; duplicate focus ownership remains absent from the unscoped layer | Compact heights, data-entry density, grids and specialized disabled/business states remain scoped where values differ | PASS |
| Filters, tables, badges and UI states | Central `.ui-*` contracts | Accommodation/search/report/settings surfaces that use those contracts | No competing unscoped `.ui-*` definitions exist in `style.css` | Module selectors retain only data layout, responsive columns, scrolling and semantic state placement | PASS |
| Room editor tokens | Canonical platform tokens plus room layout in `style.css` | Canonical room details and candidate picker | Removed the invalid `+#roomModal` local token definition and every ineffective `--room-modal-*` consumer; the undefined-variable declarations had no computed-style effect | Room widths, guest column templates, sticky footer, responsive breakpoints and compact row geometry remain functional layout | PASS |
| Cards/print/share | Existing protected module ownership | Independent Cards tab, Print, PNG, WhatsApp | None in this unit | All component-specific declarations intentionally retained; outside this cleanup scope | PASS |

### Ownership metrics

| Selector family in `style.css` | Before rules / declarations | After rules / declarations |
| --- | ---: | ---: |
| `.btn` related | 117 / 364 | 116 / 325 |
| `.btn-sm` related | 2 / 13 | 2 / 12 |
| `.card` related | 55 / 212 | 54 / 203 |
| `.card-title` related | 4 / 15 | 3 / 11 |
| `.modal` related | 12 / 53 | 11 / 46 |

Rule counts remain intentionally high because most selectors own functional placement, compact density, responsive behavior, or semantic variants rather than the base component appearance. Regression tests now require the unscoped dialog foundation to remain central and reject reintroduction of the confirmed button/card competitors and `--room-modal-*` variables.

### Local verification

| Gate | Result | Evidence |
| --- | --- | --- |
| Syntax / dependencies | PASS | Active JavaScript and service worker parse; CSS braces balance; duplicate-function scan remains zero; active scans find no unscoped `.modal`/`.overlay` owner in `style.css` and no `--room-modal-*` runtime reference. |
| Focused component and Conference regression | PASS | 62/62 tests, including dialog ownership, compact room geometry, accommodation cards, administration, shell and cache graph. |
| Development Preview validation | PASS | 659/659 across 88 platform test files (one new ownership regression added to the previous 658-test baseline). |
| `npm run check` | FAIL (unchanged expected baseline) | 664 PASS and the same 5 prohibited Production promotion/version/cache failures; the extra PASS is the new component-ownership test. |
| Browser visual automation | BLOCKED | Prohibited by `AGENTS.md`. The user's accepted appearance from the baseline is preserved by declaration-equivalent inheritance and no browser acceptance is claimed for this commit. |
| Supabase / database | NOT NEEDED | No database, migration, RPC, environment, or operational-data change. |

### Implementation delivery evidence

- Implementation commit: `8b9a18f9420c0f41218a5e68e8d921798662d0cb` (`refactor(conference): centralize shared component ownership`).
- Conference canonical people flow run `45418308417`: PASS on the implementation SHA.
- Reservations integration run `45418308267`: PASS on the implementation SHA.
- Development Preview run `45418676055`: PASS. The live `development-preview-sources.json` recorded both `platform.ref` and `platform.sha` as `8b9a18f9420c0f41218a5e68e8d921798662d0cb`, and the revisioned central stylesheet returned HTTP 200.
- The following evidence-only successor commit must be subjected to the same exact-SHA Reservations and Preview provenance gates before final handoff.

## 2026-11-25 final shared-state ownership and active-runtime audit

### Baseline and scope

- Baseline: `14bfb34aaa5190392fde3af6d1ddeb5b4619b977`, clean and equal to `origin/develop` before this unit.
- The closed room-editor, family-accommodation, component-ownership and token-cutover units were not reopened. No Arabic copy, operational mutation, database object, Reservations behavior, Cards/print/PNG/WhatsApp surface, `main`, or Production asset changed.

### Root cause and cleanup

- The prior empty-state cutover had reduced `.settings-empty-state` to compact density, but 59 active generated-markup consumers still emitted that class without the central `.ui-state` contract. Seven modal result/validation states similarly retained a complete local visual definition through `.modal-empty-state`.
- All 66 active generated empty-state consumers now compose `ui-state` with their existing semantic/local class. The local modal rule now owns only `min-height`, padding and font size; its duplicated color, background, border, radius and alignment were removed. A regression contract scans every active JavaScript file under `js/` plus `script.js` and rejects either local class without `.ui-state`.
- The stylesheet cache revision advanced atomically from `conference-empty-state-cutover-v18` to `conference-state-ownership-v19` in HTML, the Service Worker and all cache-contract tests.

### Dead CSS, `!important`, dependencies and performance

- Active runtime HTML, generated JavaScript markup, `style.css`, shared tokens, shell and module CSS were scanned together. No selector was deleted merely because it was absent from static HTML. The only proven redundant CSS in this unit was the five visual declarations on `.app-modal .modal-empty-state`; all runtime consumers were migrated before removal.
- `room-more-actions` remains active for permission-aware room operations, outside-click and Escape handling; it was retained because removing CSS alone would break the live path and a functional cutover would reopen accepted accommodation behavior.
- The active styles contain 152 `!important` declarations: 132 in `style.css`, 4 in shared reduced-motion accessibility rules, 16 in Reservations. The protected print/card rules, mobile 16px input safeguard, reduced-motion enforcement, and scoped transport/modal/table specializations remain intentional cascade boundaries. No new `!important` was added and no case was removed without an equivalent specificity proof.
- Static dependency and renderer scans found no newly duplicated initialization/listener or render owner. Existing regression coverage confirms hydration deduplication, one route/hash owner, one operational refresh coordinator, and atomic cache URLs. No speculative startup or refresh optimization was made.

### Local verification

| Gate | Result | Evidence |
| --- | --- | --- |
| Syntax / dependency checks | PASS | `node --check` passed for `script.js`, every active `js/**/*.js`, and `service-worker.js`; `git diff --check` passed; all 66 local state consumers include `ui-state`. |
| Duplicate-function scan | PASS | No new duplicate was introduced. The three same-name findings in `js/conference/accounts.js` are existing function-local helpers (`numericValue`, `selectOptions`, `options`) in separate closures, not competing globals. |
| Focused Conference/design tests | PASS | 113/113 before the final ownership assertion; the new assertion also passed in both full gates. |
| Development Preview validation | PASS | 665/665 tests across 88 platform test files. |
| `npm run check` | FAIL (unchanged Production-only baseline) | 670 PASS, 5 FAIL: Production public-config source approval, application-version advance, Production cache revision, and shell revision requirements. They are prohibited by this develop-only unit. |
| Browser visual acceptance | BLOCKED | `AGENTS.md` prohibits browser and automated UI tests. No visual acceptance is claimed. |
| Supabase / database | NOT NEEDED | No schema, migration, RPC, environment or operational-data change. |

Implementation SHA, final CI run IDs and exact Development Preview provenance are appended after commit, push and deployment verification.

### 2026-11-24 shared dialog base follow-up

- Baseline `f8b09bfc751baf92de99ffe932094e13a19eca42`; Preview run `45419341166` independently verified successful build/deploy with exact source SHA.
- Unified default modal/dialog border, radius and shadow in the shared rule; removed competing app-modal base border/shadow and mobile radius. Preserved markup, visibility and layout. Specialized room/transport/house surfaces remain pending consumer-specific verification. Visual differences in default dialog chrome require manual acceptance. Cache URLs and ownership assertion updated together. No JS or database changes. CI and visual acceptance pending.

- CI on `1cf732adb1f83bbb6695ed6a9e7f6f01a7230b9c`: Conference `45421041374` PASS; Reservations `45421041391` FAIL, three stale exact CSS revision expectations in administration sidebar, administration unification and conference round4 tests. Corrected only revision literals to match the already atomic HTML/service-worker URLs; all assertions retained. Successor CI pending.

### Specialized dialog shell cutover
- Baseline `e330cf62b0dbf10fee1553752340ad02017363fe`: Reservations CI `45421931709` PASS; Preview `45426890150` PASS, exact source SHA verified in deploy log.
- Removed competing shell border/background/radius/shadow from room, transport, house and general dialogs; retained width, height, layout and header/body styling. Central default and responsive chrome inherited. Updated all four known revision test contracts with HTML and worker. Added shell ownership regression. No operational JS or database change. CI and manual visual acceptance pending; shell colors may differ from baseline.

- Specialized shell commit `552e892867e5e83efabac6515f551e6d0b0503ec`: Conference CI `45429421683` PASS; Reservations `45429422030` FAIL (test 122 requires trailing semicolon after approved 880px max-width). Restored CSS declaration terminator; no computed style or test change. CI pending.

### Room control geometry cleanup
- Baseline `d3e55ef3fd7807703769f704526409313a165a78`: Reservations CI `45430005086` PASS, Preview `45430423597` PASS exact SHA, user reported no noticeable visual difference.
- Removed two local button radius declarations in guest rows and room footer; preserved dimensions and padding, inherited central control radius. Updated runtime revision and four known cache test contracts; added radius regression. No JS, DB, cards, printing or sharing changes. CI and preview pending.

### Retired child title button styling
- Baseline `5a66e9708caf6c256f49da6ea52364adbaba85a9`: CI runs `45431811750` and `45431811715` PASS.
- Inspected index child heading and script canonical addFamilyChildButton: active button is `btn btn-blue btn-sm` nested in `canonical-room-family-draft-actions` in guest heading, not direct child of child section heading. Removed two obsolete selector rules, no JS or markup change. Updated cache contracts and regression. CI pending. Report action color overrides remain for separate visual review.

### Report action soft button ownership
- Moved existing report soft surface and semantic color rules to shared `.btn-soft` variant; three report buttons opt in explicitly. Preserved report geometry and handlers. Updated runtime cache revisions and known test contracts. CI pending; hover specificity and visual acceptance require verification. No DB or protected cards changes.

### House library action radius ownership
- Baseline `32bc68671e4df3de54d040b5371f506d8dc48d16`: CI `45434169425`, `45434168417` PASS; user reported successful publishing.
- Removed redundant central-radius declaration from scoped house library action group. Kept compact typography, dimensions, wrapping and all handlers. Updated runtime revision and four known cache test contracts, added regression. CI pending; no JS or DB changes.

### Settings control radius
- Baseline `ed932e56e30d5b342837b8b188e48a1db93901d7`: CI `45434579091`, `45434579203` PASS.
- Removed local settings button radius; retained geometry and compact typography. Updated runtime revision and known cache test contracts. Remaining action-specific color rules require consumer audit. CI pending; no JS or DB changes.


### Settings action color ownership
- Baseline `dd725e410f75d35e8a695fbbea44ff1b9f327976`: prior CI runs `45435944046` and `45435944278` PASS.
- Removed settings-only semantic color duplication and the fragile `onclick^="edit"` / `onclick^="startEditing"` color override with `!important`. Active settings actions now inherit the shared semantic button variants (`.btn-blue`, `.btn-green`, `.btn-red`) from `shared-design-tokens.css`; settings retains only compact geometry/icon spacing. No handler, Arabic copy, markup, database, Cards/print/PNG/WhatsApp, `main`, or Production change.
- Updated the stylesheet runtime revision and the four known cache-contract tests atomically. CI and Preview provenance pending.


### Accommodation room action radius ownership
- Baseline `d5c925f85e7debd445a63f1c08f6bd613acd77c7`: settings-color Conference CI `45440597617` PASS; Reservations run `45440597108` was still in progress when this follow-up started.
- Removed the remaining local `border-radius:7px` from `#tab0 .accommodation-room-actions .btn`; retained its compact 28px minimum height and all room action layout/handlers. Buttons now inherit the canonical control radius from the shared button owner. No room save/remove/move behavior, family draft behavior, Arabic copy, Cards/print/share, database, `main`, or Production change.
- Runtime stylesheet revision and four cache-contract tests advanced atomically. CI and Preview provenance pending.


### Accommodation detail action base ownership
- Baseline `213a479766ec77a47bc23d73bfeeeadfb1ab39ff`: Conference CI `45440774922` PASS; Reservations `45440775158` was still in progress at audit time.
- Removed duplicated base button display/alignment/gap/border declarations from `#tab0 .action-button`; retained accommodation-specific minimum height, flex growth, soft surface/color and shadow. The active button keeps the shared `.btn` base contract and its existing handler.
- Consumer audit proved `.room-more-actions` is not dead CSS: `script.js` still renders it for room open/close and unassign actions and has Escape/outside-close behavior. It was intentionally not deleted in this visual cleanup; retiring it requires an explicit functional cutover rather than CSS removal.
- Runtime stylesheet revision and four cache-contract tests advanced atomically. No accommodation mutation behavior, Arabic copy, Cards/print/share, database, `main`, or Production change. CI/Preview pending.


### Accommodation quick-filter button base ownership
- Baseline `24ea511e2eb3c09abfacd648da14baa536543885`: Conference CI `45440900220` PASS; Reservations `45440899469` was still in progress at audit time.
- Removed duplicated base button display/alignment/gap/radius from accommodation quick-filter buttons; retained their compact height/padding, neutral/active surfaces, typography, icon sizing and responsive horizontal-strip behavior. The controls continue to inherit the shared button foundation without changing filter semantics.
- Runtime stylesheet revision and four cache-contract tests advanced atomically. No JavaScript handler, accommodation mutation, Arabic copy, Cards/print/share, database, `main`, or Production change. CI/Preview pending.


### Accommodation candidate filter field ownership
- Baseline `0dcf1b6efa5630785e204cd290be7caed49e6c02`: Conference CI `45441003979` PASS; Reservations `45441004358` was still in progress at audit time.
- Removed local border/radius/background ownership from canonical accommodation candidate-filter selects; retained modal-specific 36px height, compact padding/font size and grid sizing. Standard field surface, border, radius and focus now come from `shared-design-tokens.css`.
- Audited transparent accommodation search inputs separately and retained their borderless/focusless declarations because they are intentionally composed inside a styled search container, not standalone competing fields.
- Runtime stylesheet revision and four cache-contract tests advanced atomically. No JS, accommodation mutation, Arabic copy, Cards/print/share, database, `main`, or Production change. CI/Preview pending.


### Accommodation room/child field base ownership
- Baseline `fd311c4c458293247890816f0ef5dbf4711dbf45`: Conference CI `45441132808` PASS; Reservations `45441133150` remained in progress at audit time.
- Removed duplicate border/radius/surface ownership from readonly room candidate-filter selects and duplicate border/radius/surface/text/font ownership from canonical child-form fields. Both now inherit the global field contract while retaining their local compact height/padding/box sizing.
- Retained the transparent search-field composition, hidden room-key select overlay, and settings-account custom focus treatment as intentional specialized consumers rather than deleting them during this accommodation pass.
- Runtime stylesheet revision and four cache-contract tests advanced atomically. No JS handlers, family draft/mutation behavior, Arabic copy, Cards/print/share, database, `main`, or Production change. CI/Preview pending.


### Report subcard base ownership
- Baseline `90eb4f61e596a3711a25b3de90757ba16a4b8394`: Conference CI `45441325157` PASS; Reservations `45441325072` remained in progress at audit time.
- Card/table audit preserved intentional compact card geometry in accounts/reports and the transparent wrapper used by the house library. Removed only exact shared-card duplication from `.reports-v3-subcard`: border, surface and shadow now inherit from `.card`; report-specific margin, compact padding and smaller radius remain local.
- Cards/print/PNG/WhatsApp surfaces were explicitly excluded from this audit and remain untouched.
- Runtime stylesheet revision and four cache-contract tests advanced atomically. No JS/business behavior, Arabic copy, database, `main`, or Production change. CI/Preview pending.


### Shared empty-state cutover
- Baseline `a731495b95f0174b763e6c4dbba323450bf9c75e`: Conference CI `45441545890` PASS; Reservations `45441545904` remained in progress at audit time.
- Audited accounts/report tables and preserved their intentional specialized density/header/zebra styling instead of forcing `.ui-table` and changing accepted visuals.
- Migrated generated `settings-empty-state` markup to also consume canonical `.ui-state`. The legacy class now owns only compact min-height/padding/font-size adaptation; shared state owns surface, border, radius, color and alignment. Arabic copy/state semantics unchanged.
- Runtime stylesheet revision and four cache-contract tests advanced atomically. Cards/print/PNG/WhatsApp, business handlers, database, `main`, Production untouched. CI/Preview pending.

### Final shared-state delivery evidence — 2026-11-25

- Implementation commit: `ed34b037ef86aeeb0d574c127d9cd3eedb7fb84f` (`refactor(conference): complete shared state ownership`).
- Exact implementation SHA CI passed: canonical system access run `45567457428`, Conference canonical people flow `45567457523`, and Reservations integration `45567457550`.
- Development Preview run `45567676588` passed. Its build required the successful exact-SHA Reservations run, checked out `ed34b037ef86aeeb0d574c127d9cd3eedb7fb84f`, and the deploy job logged `Deploying Platform develop SHA ed34b037ef86aeeb0d574c127d9cd3eedb7fb84f`.
- This documentation-only successor is the final source SHA and must pass the same CI and exact-SHA Preview provenance gates before the final external handoff.


### Reservations canonical source/runtime cutover — 2026-11-25

- Reservations source repository remains the sole implementation owner; Platform stores only the generated runtime plus its source-owned contract. No generated runtime compatibility layer or parallel booking path was introduced.
- Reservations source fixes: `04f461873e7977e78b191bffe70266bac2259ea9` enforces non-active booking read-only payment/void UI and preserves newborn age zero in edit flows. Source CI `45606635752` PASS and develop validation `45606635781` PASS.
- Source contract publication: `9c8b37d9cc4835777b942c1c2770ccedf2378141`; Reservations CI `45607151746` PASS. Artifact `15018840910` contains JS SHA-256 `51f3667750da2dc2f37b7ef99c0b028ed8b85c0e63c109073e0483f1e4172c65`, CSS SHA-256 `e7430e2c87dbb646039466d25604f2963f52ac4d4acd1c45f38fd800d98bfa9d`, and `reservations-contract.json` SHA-256 `d202be299bae5bfc2281852bf010ac45ebd5796a2456d3915d2a15a9d12f90b1`.
- Platform runtime cutover commit `00a55dddac094d71d66ee636d8300eccd8863291` replaced the previous generated runtime atomically on `develop`; no `main`, Production, Vercel, or Supabase Production change.
- Platform contract ownership commit `243fa80878ee5c68796b59b3586d5227c3a7b623` adds the source-owned artifact contract and retires duplicate assertions against minifier-local symbol names from the dedicated apology/identity workflow gates while retaining Platform DB guards and operational-review checks.
- Development Preview remains BLOCKED until the exact Platform SHA completes the full integration/preview validation successfully.


## 2026-11-25 Public Registration V2 — family, child/guardian, notification and parity handoff

### Current canonical baseline
- Current proven `develop` bootstrap HEAD before this documentation update: `0b84a4cb9ccd411907ed938d488f574e557cfddc`.
- Work remains restricted to `develop` and Supabase Development project `gppwltrifgfxrkzvvxoe`. No `main`, Production, Supabase Production, or Vercel change was made.
- Public Registration V2 is a single family-capable canonical flow. The browser submits `submit_family`; individual registration is represented by a family request containing only the primary member, not a separate UX path.

### Canonical family and person contract
- `platform.people` remains the central person bank. Public-registration member identity fields are pre-approval request snapshots; after identity resolution the canonical person is reused or created in `platform.people`.
- Date of birth is required in the public family form and maps to canonical `platform.people.date_of_birth` when a new person is approved. Do not introduce a Public Registration person store.
- Family member roles are `primary`, `adult`, `child_paid`, and `child_dependent`.
- Every child, paid or dependent, must select a guardian from a preceding `primary` or `adult` member in the same request.
- `child_paid`: guardian required, DOB required, booking type required, independent booking/price, while retaining guardian linkage in Conference participation.
- `child_dependent`: guardian required, DOB required, no booking type and no independent booking/price.
- Migration `20261125163000_public_registration_child_guardian_contract.sql` replaces the previous family-member structural rule; it does not add a compatibility route.
- Family approval remains one PostgreSQL transaction. The paid-child approval path now resolves the guardian's canonical person and links the child's Conference participation to the guardian participation; a conflicting existing guardian raises `PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT`.

### Operational child/guardian verification
| Check | Result | Evidence |
| --- | --- | --- |
| Paid child without guardian | PASS (expected rejection) | Development gateway raised `PUBLIC_REGISTRATION_GUARDIAN_INVALID`. |
| Paid child with guardian + DOB + booking type | PASS | Family submit returned `submitted` with two members. |
| Test-data cleanup | PASS | The submitted smoke request was deleted before approval; no test Person or Booking was created. |
| Public form contract | PASS | Every `child_*` requires `guardianMemberKey`; guardian candidates are preceding adult/primary members; DOB remains required. |
| Reservations integration | PASS | Runs `45634238742`, `45634365279`, and `45634403485` succeeded for the child/guardian implementation/test sequence. |

### Shared reference data and family UX
- Browser reference ownership is centralized in `js/platform-reference-data.js`. Reservations and Public Registration consume the same governorate and service-sector arrays; `other` retains the explicit `serviceSectorOther` value.
- Public form supports adding adults, paid children, and dependent children to one request.
- UX direction still pending final acceptance: present the primary person's normal fields first, then progressive `+ إضافة فرد من العائلة`, then a final family summary. Do not expose the backend concept of “primary” as an unnecessary user decision.
- Family financial summary is still **PENDING**: verify/display each paid member's canonical booking-type price and the family total; dependent children contribute no independent charge. Current status behavior must not be accepted if it only reports the primary member's financials.

### Platform Notification Foundation
- Notifications are platform infrastructure, not a Reservations-only implementation. Public Registration is the first consumer.
- Canonical Development tables: `platform.notification_push_subscriptions`, `platform.notification_events`, and `platform.notification_deliveries`.
- Protected device operations own push subscription enable/disable; service-role notification gateway owns enqueue/delivery work. PWA/Service Worker bridges incoming push to open clients and the Public Registration admin panel refreshes on `platform-notification` plus bounded polling.
- Real OS Push end-to-end acceptance is **PENDING** because the last Development check found zero push subscriptions. An approved admin device must opt in before a real delivery can be proven.
- Notification click deep-link is **PENDING**: current Public Registration emission targets the Reservations area; final acceptance requires routing to the relevant request/event through the canonical navigation owner, not a second router.

### Public Registration legacy retirement gate
- The current public Edge contract still exposes both `submit` and `submit_family`; the active browser uses `submit_family`.
- **PENDING:** trace all consumers/tests of V1 `submit`. If no live consumer remains, retire the old Edge/gateway/DB submit path atomically with replacement tests. Do not retain two submission systems merely for compatibility, and do not delete before reachability proof.

### CI/parity closure
- Child/guardian function changes intentionally changed semantic structural fingerprints without changing function count.
- Zero-data run `45634365319` initially failed only at structural parity: functions expected `298/0988ce929acf8f4bbe8063121f85c753`, actual `298/1adf3b83a307e48d096bfe0f06e9b790`.
- Commit `d5ab657ed407d6596faf0f2065dc2d99caeb0349` updated the canonical structural digest to the proven Development value; no function count increase or Legacy function was introduced.
- Run `45635106543` (zero-data production preparation) **PASS** and run `45635106435` (Reservations integration) **PASS** on `d5ab657...`.
- The successful workflow generated canonical clean bootstrap `0b84a4cb9ccd411907ed938d488f574e557cfddc`; follow-up Reservations run `45635381093` **PASS**.
- The earlier structural-parity rejection is CLOSED; do not reopen it unless the schema/function bodies change again.

### Next execution gates
1. Prove paid-child guardian-linked Conference participation through a safe end-to-end family approval test and clean all test data.
2. Finish progressive family UX and family financial summary using canonical booking-type prices.
3. Trace and, if safe, retire V1 `submit` so one canonical submission path remains.
4. Deep-link notification clicks to the relevant request/event through existing canonical navigation.
5. Verify the actual Development Preview provenance for the current runtime; source CI alone is not visual/operational acceptance.
6. Enable a push subscription on an approved Development admin device and perform real OS Push delivery/click/live-refresh acceptance.
7. Append exact SHAs/run IDs and PASS/FAIL evidence here after each completed unit; preserve prior evidence.


## 2026-11-25 Public Registration family UX + V1 retirement + notification routing continuation

### Progressive family UX and financial summary
- `444b25cd3dcf5f1575cede8b09944016cb31d334`: Public Registration now starts with the submitting person's normal fields, then exposes `+ إضافة فرد من العائلة` with adult / paid child / dependent child choices.
- Paid children now render both canonical booking type and guardian selection. This closes a real UI defect where the backend required `guardianMemberKey` but the paid-child card did not render a guardian selector.
- Booking type options display the canonical event-owned name and price. The pre-submit family summary lists every member, guardian where applicable, paid booking type/price, dependent child as no independent cost, and the canonical-price family total.
- `80e5da9c62b699ab1c6f21fbfb83f5575f46e6b3`: page regression tests now lock the one family-capable browser submission route and the progressive guardian/financial UX. Reservations CI `45638562458` **PASS**. The implementation commit itself also passed Reservations CI `45638535531`.

### V1 submit canonical retirement
- Reachability evidence: the active browser already used only `submit_family`; Development database function-body scan found V1 `reservations.public_registration_submit` referenced only by `public.public_registration_gateway`; stale tests/contracts still named V1 and were corrected rather than used as a compatibility reason.
- Supabase Development migration history now contains `20261125145150 retire_public_registration_v1_submit`.
- V1 `reservations.public_registration_submit(...)` was dropped; `public_registration_gateway` no longer accepts `submit`; Public Registration Edge v6 removed the V1 operation and branch. Post-change Development verification: V1 function absent, family gateway present, V1 gateway branch absent.
- Repository migration: `supabase/migrations/20261125145150_retire_public_registration_v1_submit.sql`. Edge/tests/parity were updated on `develop`; no compatibility route or fallback was retained.
- Structural parity intentionally changed from 298 functions to 297. The first family-only digest was `777ace1b0e079db4a494188d0f021b4a`; the later notification-target change below changed function semantics again without changing the count.

### Notification deep-link
- Root-only `./#reservations` notification targeting is retired.
- Supabase Development migration `20261125145319 public_registration_notification_event_deeplink` makes the family submit RPC return the internal event id to the service boundary; the Edge strips that internal field before returning the public response.
- Public Registration Edge v7 emits `./#reservations/events/<eventId>?tab=registration`, which routes through the existing Reservations canonical router to the correct event registration panel. No second router was added.
- Current structural parity after this semantic function change: **297 functions / `a5317978d9223dc92acde0bcb4aae705`**.
- Notification regression requires an event deep-link and forbids the old root-only target.

### Approval E2E / Preview / Push truth status
- Paid-child approval E2E was attempted through a rollback-only SQL transaction. The first attempt stopped at the existing approved-device guard with `AUTH_REQUIRED` before approval; no permanent test data was created. The available database tool blocks session impersonation, so the guard was **not bypassed**. Full approved-device family approval remains **PENDING**, not falsely marked PASS.
- Development Preview is currently **STALE / NOT ACCEPTED** for this unit. Latest successful Preview run checked was `45633384470`; its build provenance logged Platform source SHA `ee960f87c47fc444e00002a55199008d07e959e7`, older than this work. A new Preview deployment is required before visual/operational acceptance.
- Push subscription count on Development remains **0 active / 0 total**. Real OS Push delivery/click acceptance therefore remains **BLOCKED on an approved admin device subscription**; Notification Foundation is unchanged and no parallel notification system was added.
- Security advisor output after the DDL changes contained existing informational RLS-no-policy findings and pre-existing SECURITY DEFINER warnings; no new policy was added merely to silence advisor output.

### Current execution gates after this continuation
1. Wait for exact-SHA Reservations and zero-data/parity CI for the latest family-only/deep-link source state; investigate any real rejection from its job logs.
2. Produce a fresh Development Preview whose provenance points to the latest accepted Platform SHA, then verify the deployed public-registration assets rather than source CI alone.
3. Complete approved-device paid-child family approval E2E (independent booking, central DOB, Conference participation, guardian link, rollback/cleanup) through an authorized device-session path.
4. Real OS Push remains pending until Development has an approved active push subscription.

- Zero-data run `45639060128` exposed a digest-recording mistake, not a schema defect: guards and disposable replay passed, extracted Development schema reported the same per-schema function fingerprints as live Development, while the expected combined digest had been calculated with an incorrectly escaped separator. Exact assertion semantics on Development produce `297/a5317978d9223dc92acde0bcb4aae705`. Commit `7581b829b0066df4e4913e9930762775dd27ff49` corrects only that expected digest; follow-up zero-data is required before PASS.


### 2026-11-25 — Public registration regression recovery
- Zero-data run 45639409352: structural PASS, ACL FAIL (retired V1 grant); live ACL 340/9018274dbceece379cf1854a2aae4c25, corrected in 129a85a5e2f2d281c2cdcb8676e92bcae98dd8c2.
- Public event load HTTP 500: gateway stripped two backslashes instead of one; reproduced invalid hexadecimal digit 22023. Development migration 20261125150328 fixes all three canonical operations using chr(92). Source bd91670b84c465376001a13c31030e6a4b18f874.
- User browser confirmed form loads and HTTP 500 disappeared: PASS for event load only. Family submit/approval E2E remains pending.
- Live structural digest 297/6f3efe87a90399e33569cdc3d28910b2; other structural digests unchanged. Source f566761c282ff8b21b92f573ec10ebed13d7e14c. CI pending. No production changes.


### 2026-11-25 — Canonical family admin review + standalone/conference approval closure
- Reservations source `a334223c1b1ce0b1cc8ffacc7d0258680f6f6191`: admin Public Registration review now consumes the family request contract, renders every member/guardian/current booking price, requires an explicit central-person identity resolution for every member, and approves through `decide_public_registration_family_request`. The admin UI no longer calls the single-request decision operation.
- Reservations CI `45643450904` **PASS** and Development Validation `45643450453` **PASS**. The first CI rejection was stale single-person UI assertions; tests were changed to require the canonical family decision path and explicitly forbid regression to `decide_public_registration_request`.
- Supabase Development migration `20261125172000 public_registration_family_standalone_scope` guards Conference participation projection with `e.conference_id is not null`. Standalone events therefore do not attempt Conference participation writes; conference-linked events retain the existing guardian-participation projection. Repository source: `9c6105fbb35e86c2e7a8524ce06c621a23c98263`.
- That function-body change intentionally changed the combined function structural fingerprint, with count unchanged at 297. Exact Development assertion semantics produce `297/6c3adadcd27e7d4ef157186c7f3c0847`; source parity update: `653707beec965f148432c376fc9bf3c6c657783b`.
- Zero-data run `45645317940` **PASS**: zero-data guards, disposable catalog replay, Development schema export, disposable PostgreSQL 17 rehearsal, bootstrap staging/upload, and generated-HEAD Reservations dispatch all passed.
- Platform Reservations validation `45645317989` **PASS** on the parity correction; latest validation `45645384906` **PASS** on `c4b8c3f17af4031d21c380e07e7bce020216bddc`.
- Artifact preflight `45645384812` **PASS**. The earlier `45645202004` failure was an attempted automatic private-artifact download without `RESERVATIONS_SOURCE_TOKEN`; that incomplete automation was removed and the preflight restored to read-only in `c4b8c3f17af4031d21c380e07e7bce020216bddc`. Do not treat that superseded run as an active regression.
- Verified Reservations artifact source remains `a334223c1b1ce0b1cc8ffacc7d0258680f6f6191`; its approved JS/CSS hashes are recorded in `tools/reservations-artifact-policy.json`. The artifact has **not** been manually copied into Platform; integration remains gated by the canonical artifact utility rather than an untracked bundle edit.
- No `main`, Production, Supabase Production, or Vercel changes were made.

#### Remaining acceptance gates
1. Integrate the approved Reservations artifact into Platform through the canonical artifact utility with valid private-repository artifact access; do not bypass hash/contract policy.
2. Produce a fresh Development Preview from the resulting Platform `develop` SHA and perform visual/operational family review acceptance.
3. Complete approved-device family approval E2E for both standalone and conference-linked events, including paid child guardian linkage and cleanup/rollback evidence.
4. Real OS Push remains blocked until Development has an approved active push subscription.

### 2026-11-25 — Canonical artifact and event-scoped guardian closure

- Platform baseline was `ce65ff4f53418458138b6a23a13cea7e734070f9`. The approved family artifact from Reservations source `a334223c1b1ce0b1cc8ffacc7d0258680f6f6191` exposed one real Platform regression: its generated JS embedded governorate/service-sector catalogs instead of consuming `window.PlatformReferenceData`.
- The source fix is Reservations commit `e576e5a6abd0a0527e9a3ee4b5ccf70a16fd3cac`. Local TypeScript, all 309 source tests, and the platform-module build passed. Reservations CI run `45649396164` passed and published artifact `15039213031` with JS SHA-256 `1d69356e9073a65ac389321ef0349249d646c39337ddca3ceb0c6056db6dbf89`, CSS SHA-256 `2b4edb80f5993e48b8c1ecc7f4209774be583c97b63fd5a8e1c81164caca07be`, and contract SHA-256 `d202be299bae5bfc2281852bf010ac45ebd5796a2456d3915d2a15a9d12f90b1`.
- Platform's canonical integration tool was corrected to preserve the independently owned suffix in the composite Development cache revision and to write a real trailing newline. The official artifact was then integrated through that tool as `reservations-family-registration-review-v2`; no hand-edited generated bundle or parallel runtime was introduced.
- Platform Development validation after the final artifact is `671/671 PASS`. `npm run check` is `676 PASS / 5 FAIL`; all five are the established Production-promotion negative fixtures (application/cache/shell revision advancement), not Development regressions.
- Migration `20261125180000_reservations_event_guardian_child_relationship.sql` was applied to Supabase Development only. It adds the event-partitioned `reservations.event_guardian_children` authority, captures both paid and dependent child resolutions, keeps dependent children outside Bookings/financial totals, and replaces the family flow's direct dependent Person insert with the private audited helper.
- A rollback-only live test exposed and then closed a pre-existing canonical mismatch: family child snapshots used `gender='child'`, while `platform.people` permits biological `male/female`. Migration `20261125183000_public_registration_child_gender_canonicalization.sql` was applied without rewriting historical operational rows; new family submissions now require `male/female`, and the public form collects that canonical value for children.
- Supabase Development verification: relation RLS is enabled and forced; anon/authenticated/service_role have no direct table or helper access; trigger and private helper exist; the family function uses the helper and no longer contains the direct dependent Person insert. Rollback-only tests passed for both standalone and conference scopes: audited Person creation and event-isolated guardian relationship were true, with `child_dependent` retaining a null booking.
- Migration `20261125184000_reservations_event_guardian_child_indexes.sql` adds covering indexes for every new relationship foreign-key path; no advisor-warning workaround or public RLS policy was introduced.
- Initial zero-data run `45650686153` rejected the disposable rehearsal only because the fail-closed foundation count still expected 19 Reservations tables after the intentional addition of the twentieth table. Zero-data guards and disposable catalog replay had already passed. The expected count was advanced to 20; no assertion was removed or weakened.
- Follow-up run `45651096857` passed that object-count gate and then rejected the stale structural baseline. The extracted Development truth was registered exactly: relations `96/3a42a4ebe83dd98eac89270f3449bac3`, columns `1215/807984d8b6c48dea374fab2e43de8de7`, functions `299/b4de4d76a343422535e6d8c08925b686`. The deltas are one relationship table, its ten columns, and the private helper/trigger functions; schema-specific semantic fingerprints were unchanged from the extraction log except for the expected Reservations surfaces.
- `platform-device-operation` Development Edge Function version 44 is ACTIVE with JWT verification and only `decide_public_registration_family_request` exposed for this decision flow. The first deployment request failed locally on import-map packaging and made no live change; the corrected canonical package deployed successfully.
- Browser/automated UI tests were not run because workspace `AGENTS.md` explicitly forbids them. Development Preview provenance and HTTP asset verification remain the final delivery gate at this point in the log.
- Throughout this unit, `main`, Production, Supabase Production, Vercel, real participant data, Cards/print/PNG/WhatsApp were not modified.
- Reservations exact-source closure: CI `45649396164` PASS and develop validation `45650616769` PASS on `e576e5a6abd0a0527e9a3ee4b5ccf70a16fd3cac`.
- Platform exact implementation validation: Conference people `45650685910` PASS and Reservations integration `45650686648` PASS on `8892d5480a6f704093c689418169087f61dce7bc`. Final parity correction Reservations integration `45651342214` PASS on `36ab47fe89f074102eacfa17570dace4bb4a56ce`.
- Zero-data run `45651362833` PASS produced canonical bootstrap successor `dc430f09c61e9e8cee1ed4f2550b135780ee752f`; its exact-SHA Reservations integration `45651527597` PASS.
- Development Preview run `45651708964` PASS. Deploy job `139337905541` logged `Deploying Platform develop SHA dc430f09c61e9e8cee1ed4f2550b135780ee752f`. Live `development-preview-sources.json` reported that exact Platform SHA and Reservations hashes `1d69356e...` / `2b4edb80...`; live `index.html` loaded `reservations-family-registration-review-v2`, and live `public-registration.js` contained the canonical `male/female` guard. HTTP checks returned 200.
- Automated/static/rollback acceptance is PASS. Visual browser acceptance remains explicitly BLOCKED by `AGENTS.md`; no visual PASS is claimed.


### 2026-11-25 — Family approval root closure and public form canonical cleanup

- The Development Preview family approval regression was reproduced on pre-cutover request `PR-E3289359A693`: `decide_public_registration_family_request` returned `CONFERENCE_OPERATION_ARGUMENT_MISSING`. Root cause was canonical create-booking arguments being built through `jsonb_strip_nulls`, while the exact-key contract requires nullable keys such as `p_service_sector_other` and `p_notes` to remain present.
- The first family-loop correction exposed the deeper ownership defect: the primary member still delegated to `reservations_private.decide_public_registration_request`, which independently rebuilt and stripped the same booking arguments. The final root fix introduced one private owner, `reservations_private.public_registration_booking_args`, and both single-primary and additional-paid-member decision paths now consume it. No second booking writer or fallback path remains.
- Development structural truth after that owner was registered as functions `300/b1e4d857a901ae2c590599617b317e0c`; access truth was `341/825f4d597dcf7a03d5e24b171aabc68f`. The new helper remains executable only by `postgres` and `service_role`; anon/authenticated/public access was not widened. Final closure runs were zero-data `45661510948` PASS and Reservations `45661510888` PASS, producing bootstrap successor `ebf6bfad47d9b6e66dfab4914977806b654ad09a`; exact-successor Reservations run `45661868374` PASS.
- The public family form was then cleaned in-place, not forked: member edits no longer rerender every card on each change; summary and conditional fields update locally; the add-member panel, member cards, total summary, required-field affordances, and mobile composition were refined in the existing `public-registration.js/css` owners. CI runs `45664084479` and `45664119260` PASS.
- A destructive UX edge was removed at the same owner: deleting an adult guardian no longer silently cascades removal of linked child drafts. Removal is blocked until linked children are explicitly reassigned or removed. CI `45664579453` PASS.
- Deep live Development checks returned zero for child-booking/event mismatches, self-guardian relationships, missing child/guardian Person references, and noncanonical stored child genders. Public exposure remains a single path: Edge operations are exactly `event`, `status`, and `submit_family`; the DB gateway maps them to `event`, `status_family`, and `submit_family` and rejects unsupported operations/excess keys. No legacy public `submit` path remains.
- Server-side validation review found one remaining contract asymmetry: the browser enforced biological `male/female` for every family member, while `reservations.public_registration_submit_family` explicitly enforced it only inside the child branch. Migration `20261125174500_public_registration_family_canonical_gender.sql` patches that existing canonical writer itself so every submitted member must use `male/female`; it does not add a parallel writer or endpoint. Applied to Supabase Development only. Live verification confirms the all-member guard and child guard are both present and existing noncanonical family-member rows = 0.
- Final source commit for the canonical gender closure is `52256878bc4d52e82a256a4adabb6aad8c2381eb`. Reservations run `45664764926` PASS and zero-data run `45664765030` PASS without weakening or manually advancing a parity baseline. The workflow generated canonical clean-bootstrap successor `2c5e0e595e1adfcb04a519fcc397d96750cb50eb` with sourceCommit `52256878bc4d52e82a256a4adabb6aad8c2381eb`, workflowRunId `45664765030`, and bootstrap SHA-256 `009ec05095da7f39e6f7fd6f9828a5db6194ee14b2fc3728a6c14e7a5f240a57`. Exact-successor Reservations run `45664976846` PASS.
- A fresh Development Preview for successor `2c5e0e595e1adfcb04a519fcc397d96750cb50eb` and UI retry of old request `PR-E3289359A693` remain pending because no new workflow dispatch has been started yet. No Preview or approval PASS is claimed for this final successor until those gates are actually run.
- No Platform `main`, Production, Supabase Production, or Vercel changes were made in this closure.


## 2026-11-25 — Public registration identity/preview closure

- Approved live request `PR-E3289359A693` was verified in Supabase Development: state `approved`, revision `2`, active booking, resolved canonical person, participant snapshot `service_sector=media`.
- A second public request `PR-D5F142154313` proved a duplicate-identity gap: same event and exact same canonical phone key could be submitted with a different DOB because the public duplicate guard used `event + phone + DOB`.
- Root fix is one canonical public writer, not a parallel guard: migration `20261125224500_public_registration_phone_identity_duplicate_guard.sql` serializes by `event + person_phone_key(phone)`, checks idempotent submit replay before duplicate rejection, and blocks same-phone `submitted`, `under_review`, `waitlisted`, plus `approved` requests whose booking is still `active`. Rejected requests and approved requests with non-active bookings remain eligible, preserving apology/rebooking policy.
- Contract regression: `tests/public-registration-phone-identity-duplicate-guard.test.js`.
- Supabase Development live function updated from the same migration source. Direct execute remains revoked from `anon` and `authenticated`; `service_role` only. Canonical function structural digest is `ff879201423a537c4807863db5931e1c` for 301 functions.
- Platform SHA `eb20f50c9d520fafd7fc05c19e01d5cc773eeb80`: Reservations CI `45697725204` PASS and zero-data/schema replay CI `45697725244` PASS.
- The pre-fix duplicate request `PR-D5F142154313` was moved through the supported admin decision path to `waitlisted`; DB verified revision `2`, with no booking and no resolved person. Do not treat it as a valid post-fix duplicate submission.
- A separate Preview frontend regression was then found: `public-registration.js` contained literal backslash-n tokens between function declarations, causing `SyntaxError: Invalid or unexpected token` at line 11. Source was fixed by restoring real newlines, and `tests/public-registration-page.test.js` now parses the full script with `vm.Script` so invalid JavaScript cannot pass this contract again.
- Platform SHA `bc8db1cceeffcfb9a76a7c8bd9997e6796b9e40f`: Reservations CI `45698333124` PASS, including Development preview validation.
- Required next acceptance after Development Preview publishes `bc8db1cceeffcfb9a76a7c8bd9997e6796b9e40f`: hard refresh the public page; confirm no syntax error; attempt a fresh submission for the same event/phone with changed DOB/data and confirm no new request reference is created. Then validate waitlisted -> approved only with a non-duplicate identity/request as appropriate.
- Scope remains Development only. Platform `main`, Production, Supabase Production and Vercel were not touched.


## 2026-11-26 — Public registration age and private helper closure

- Age migration `20261126053000_public_registration_canonical_age_validation.sql`; route and age regression CI 45760986026 PASS.
- Zero-data 45760603764 failed structural parity (301 expected, 302 actual); live Development also had default PUBLIC execute on age helper.
- Applied `20261126054947_public_registration_age_helper_private_acl.sql`; anon/authenticated/service_role direct execute denied; owner age calculation returned 26.
- Commit `0a0e39de662a2ea2669de2a326107b0565c662db`: live structural fingerprints 96 relations, 1215 columns, 302 functions/a693d3115332697a267e4de313d581ed, 15 policies; access 342/a6692964e1900b01d6d59724016de852 unchanged.
- Reservations CI 45764171990 PASS; zero-data CI 45764171976 PASS (all three jobs). Preview deployment and manual UI acceptance pending. No main or Production changes.

## 2026-11-26 — Central notification architecture
- User approved one Platform notification engine, durable recipient inbox, authorized private Realtime Broadcast for foreground and standards Web Push for background. No Firebase/OneSignal or parallel legacy engine.
- Development observed zero registration notification events, zero active reservations subscriptions, zero deliveries. Logs confirmed missing PLATFORM_WEB_PUSH_VAPID_PUBLIC_KEY; prior web-push default import boot failure fixed.
- Commits 34732dea and a137d725 separate browser GET origin from authenticated backend POST and expose activation failure. CI 45765516288, 45765516319, 45765580542 PASS; Development platform-notifications v3 ACTIVE.
- Pending: provision VAPID secrets outside source control; verify actual subscription and recipient authorization at delivery/read time, including revoked devices and event scope; transactional durable event creation, retry/claim and expiry handling; authorized inbox/read state and private Broadcast; canonical request route with event selection; retire polling only after acceptance. No claim of delivery or UI acceptance. Develop and Development only.


## 2026-11-26 — Central notification internal-system closure track

### Accepted architecture and completed internal path
- One canonical Platform notification engine remains the only internal notification path. No Firebase, OneSignal, legacy polling inbox, or parallel notification store was introduced.
- Durable internal source of truth is `platform.notification_events` + `platform.notification_recipients`; read/unread state is server-owned. The signed-in Platform shell exposes the central bell/inbox and uses canonical device-session operations to list and mark notifications read.
- Foreground delivery uses private Supabase Realtime Broadcast on the per-user topic. Authorization is rechecked against the user, active device/account, module permission and event scope; the notification resource identity is separate from authorization scope.
- Public-registration submission creation is transactionally staged in the database: request INSERT -> canonical notification outbox -> core enqueue -> durable event/authorized recipients/push deliveries. Edge no longer owns durable creation and only requests a push flush after the DB transaction succeeds.
- Web Push delivery is server-authoritative. Browser subscription alone is not treated as enabled unless the matching server registration is active.
- Push concurrency is closed with atomic claim/lease, `FOR UPDATE ... SKIP LOCKED`, a two-minute lease token and lease-protected mark. The old plain pending consumer is not used.
- Push failure lifecycle is closed: retryable failures use `next_attempt_at` exponential backoff (30 seconds increasing to a 30-minute cap, maximum five attempts); HTTP 404/410-style expired deliveries deactivate the dead subscription so future events do not keep targeting it.
- Applicant decision notifications are intentionally NOT part of the internal Platform inbox because applicants are not Platform users. Decision transitions to approved/rejected/waitlisted are transactionally staged in the separate external outbox for future WhatsApp/SMS provider delivery. That external sending layer is explicitly deferred until the internal notification system is fully accepted; no provider delivery is claimed.
- Public request recovery/tracking no longer requires retaining the request reference. Canonical recovery uses full name + phone/WhatsApp + DOB within the public registration channel, requires exactly one identity match, preserves rate limiting and rotates the tracking secret. Direct helper execution remains revoked.

### Current Development proof
- Internal notification authorization, durable inbox, private Realtime, transactional request notification staging, explicit event scope, server-authoritative push state, push claim/lease, retry/backoff and dead-subscription retirement are present in Supabase Development and source migrations.
- Latest proven clean-bootstrap HEAD before this documentation update: `ffdaf16e8a847edf87af69af149d1b5e67553f4b`; its exact Reservations validation run `45802980259` PASS.
- The source run immediately before that bootstrap, `37624a9cdb022797c18512ac93c5384dcad3d85f`, passed Reservations run `45802657631` and zero-data/schema replay run `45802657717`.
- Development-only scope remains enforced. Platform `main`, Production, Supabase Production and Vercel were not modified.

### Internal notification closure gate — finish this before external delivery
The internal notification system is not declared CLOSED until all of the following are verified together:
1. New public registration creates exactly one durable admin notification for authorized users of the correct event and none for unauthorized users.
2. Bell/unread count and notification list update without page refresh through the private Realtime path.
3. Opening an item marks the durable recipient read and routes to the canonical registration-requests target without losing event context.
4. Permission/device revocation prevents subsequent read/delivery authorization; no stale recipient or Push subscription bypass exists.
5. Push subscription enable/disable/server-state lifecycle is internally consistent, including dead endpoint retirement and retry/backoff behavior.
6. No notification polling timer, duplicate internal producer, obsolete pending delivery consumer, or parallel inbox remains in source/runtime.
7. Clean bootstrap, structural/access parity, notification contract tests and exact-successor CI remain PASS after the final internal cleanup.
8. Background Web Push network acceptance remains dependent on Development VAPID secrets; absence of those secrets must be reported as an external configuration blocker, not bypassed in code.

### Explicitly deferred until the internal gate is CLOSED
- Actual WhatsApp provider delivery.
- Actual SMS provider delivery.
- Email provider/model and applicant email collection if required.
- External-delivery worker/provider credentials, receipts and provider-specific retry semantics.


## 2026-11-26 — Internal notification closure final cleanup

- Final source audit found one remaining non-canonical refresh path: the Reservations registration-request workspace still ran a 15-second `setInterval` alongside the canonical `platform-notification` event. The runtime polling timer was removed; initial load plus the central notification event now own refresh. The existing contract was inverted so reintroducing that 15-second polling fails.
- Push enable lifecycle now distinguishes an existing browser subscription from a newly-created one. If module discovery or server registration fails after creating a new browser subscription, that new subscription is unsubscribed before the activation error is returned. This prevents browser-only orphan subscriptions while preserving an already-existing subscription for safe retry.
- The PWA asset revision was advanced to `notification-lifecycle-closure-v1` in both `index.html` and `service-worker.js`; a contract test pins the pair so the lifecycle fix cannot be hidden behind a stale asset revision.
- Supabase Development inspection confirms one durable inbox authority (`platform.notification_events` + `platform.notification_recipients`), one transactional registration producer through `notification_outbox`, private Realtime broadcast, and the claim/lease push worker. Development currently contains zero notification events, recipients, push subscriptions, and deliveries, so there is no stale pending-delivery backlog to preserve or migrate.
- Live function inspection confirms list/unread and mark-read recheck current authorization; broadcast rechecks authorization before `notification_created` / `notification_read`; push claim rechecks active subscription, active device, approved account, module and event authorization; 404/410 expiry deactivates the subscription; retry uses bounded exponential backoff and lease-protected marking.
- ACL inspection confirms `platform.notification_gateway` and the backend enqueue entry are service-role only, while private inbox, subscription, authorization, staging and broadcast helpers are not directly executable by anon/authenticated/service_role.
- Security Advisor after this frontend-only cleanup shows no new notification-specific warning. Existing RLS-with-no-policy informational findings and unrelated pre-existing SECURITY DEFINER/Auth warnings remain outside this notification change and were not bypassed.
- Background Web Push network acceptance remains blocked only by the Development VAPID secrets; no key was placed in source, database, or chat and no bypass was added.
- Cleanup commits on `develop`: `1ed1ef94cc1b8e4d9c69cf6a3e2d4081d2b6070c` (remove request polling), `0e8d73cb5edad1b519bb2ddb028cecbffe0ba5b6` (forbid polling contract), `86f1b001833635586c766b2c8cf4f1940d574d87` (push activation rollback), `8a35431dacafb38e50cd450370835f8597f2e6ed` (push rollback contract), `954c729f3df65687c5cb8cc2bff7bd4fdc5ee8d1` + `e8e1dd20624e21198421a555d00dfe2d0c944ec3` (PWA revision), and `d86b1cae7f570b6ce18669f23015a12b1dddd6d1` (revision contract).
- Final CI / zero-data / clean-bootstrap successor validation is still a mandatory gate after these source commits. Do not declare `INTERNAL NOTIFICATION SYSTEM = CLOSED` until those automatic runs and the exact bootstrap successor are PASS.


### 2026-11-26 — CI rejection-chain correction

- The rejection chain after notification cleanup was traced to a malformed test boundary in `tests/public-registration-live-notification.test.js`: the polling-removal assertion test was not closed before the transactional-outbox test began, nesting subsequent tests and causing CI rejection independently of the notification runtime.
- Root correction: restored the missing `});` boundary. No runtime fallback, polling, duplicate path, DB mutation, or Production change was introduced.
- Corrective commit: `a7059cf0722afb91472d0e8b7cc3797ea3b0f18a`.
- Re-validated source ownership after correction: the Reservations runtime still contains no `setInterval(F,15000)`; canonical `platform-notification` refresh remains the only live refresh event beyond initial load.
- CI successor remains the acceptance authority; continue through the entire successor chain rather than treating earlier failures as current after this root correction.
