# Conference Accommodation Acceptance Matrix

Baseline for the complete original UX recovery: `4dbc348c1006e38bb7d1ec1b6e3955ead25f2b34`

Functional reference: `cccba23a9b13e800cd6e95c96c86bd02ad56bf2a`. The old commit is a behavior reference only; its local `conference.houses`, `room.guests`, `room.children`, `save()` and IndexedDB paths are not valid owners for a linked Conference.

Canonical runtime owner:

`Person -> Conference Participation -> Active Accommodation Occupancy -> Operational Modules`

The active UI owner is `renderCanonicalAccommodation()` in `script.js`. Reads and mutations are owned by `PlatformIntegration`, the protected Conference dispatcher, and the canonical PostgreSQL tables. Every successful accommodation mutation rehydrates Accommodation, Transportation, Restaurant, and the active tab before reporting refreshed state.

## Historical component evidence and restored surface matrix

The design chain was inspected component by component: `c0617e2` (exclusive room actions), `2e2c737` (room actions and editor), `9d878ac` (visual polish), `0d57ad9` (guest and extra-bed rows), `60e0381` (child rows), and `cccba23` (final historical polish and searchable person picker). The legacy local data writers from those commits remain reference-only.

| Surface | Git reference and original evidence | Difference at baseline `4dbc348` | Restored canonical behavior | Programmatic acceptance |
| --- | --- | --- | --- | --- |
| Room card | `c0617e2` through `cccba23`; compact `rcard-head/body`, status strip, resident names, arrival/key and exclusive quick menu | Geometry had already been restored, but still awaited visual confirmation | Preserved the compact 230–262px canonical card, guardian-linked child grouping, quick arrival/key/details actions and no contact/stay editor data in the card | PASS; visual BLOCKED |
| Room grid | `cccba23`; RTL auto-fill tracks, start alignment, 8px gap/padding | Canonical grid already matched measured source values | Preserved one scoped owner and content-driven card height, including one-column mobile layout | PASS; visual BLOCKED |
| Quick actions | `c0617e2`, `2e2c737`; direct primary action plus exclusive overflow actions | Canonical actions existed but are revisioned central mutations | Preserved details/add/arrival/key and central open/close/remove actions without a legacy writer | PASS; operational BLOCKED |
| Room details | `2e2c737` to `cccba23`; bounded editor, guest/child rows, room fields and persistent footer | Baseline canonical dialog already contained full actions and bounded scrolling | Preserved full canonical details, stay history, edit/replace/move/remove, notes/capacity, and visible sticky actions | PASS; visual/operational BLOCKED |
| Person picker | `cccba23` `renderGuestPersonPickerList`, `openGuestPersonPickerPopover`; immediate search, rich rows, inline new-person path | Period fields appeared first and people stayed hidden until pressing “عرض الأشخاص المتاحين” | Immediate searchable list on open; name/phone/church rows; stable Participation selection; integrated central-person creation; same draft resumes after creation; period and bed changes recalculate availability | PASS; visual/operational BLOCKED |
| Assignment lifecycle | Central `PlatformIntegration` contracts, dispatcher and PostgreSQL functions | Functional contracts existed but the picker interaction diverged from the original | Picker-first UI now feeds the same assign/move/atomic-replace contracts with permission, revision, lease, overlap, capacity, idempotency and hydration guards unchanged | PASS; live operational BLOCKED |

The canonical adaptation intentionally uses the original picker interaction rather than restoring the old row-anchored room editor: `Person -> Conference Participation -> Accommodation Occupancy` remains the sole data route. DOM interaction coverage verifies immediate rendering, search by identity details, selection by `participationId`, enabled confirmation, and removal of the intermediate load step.

## Original room-card restoration

The compact visual reference is the accommodation sequence `c0617e2`, `2e2c737`, `9d878ac`, `0d57ad9`, and `60e0381`, finalized by `cccba23a9b13e800cd6e95c96c86bd02ad56bf2a`. The historical renderer is a visual and interaction reference only; `renderCanonicalAccommodation()` remains the sole active owner.

| Surface | Historical behavior | Canonical restored behavior | Evidence |
| --- | --- | --- | --- |
| Room card | Fixed compact card with room state, names, and quick tools | Compact 230–262px card; full contact, stay, and per-person actions are excluded | `renderCanonicalAccommodation`, `renderCanonicalAccommodationCompactOccupants` |
| Room details | Full room and resident operations in the room dialog | Central room dialog keeps room edit, add, edit/replace, move, remove, arrival, key, notes, and stay history | `openCanonicalAccommodationRoomDetails`, `renderCanonicalAccommodationDetailOccupant` |
| Linked children | Child shown with its guardian | Exact `guardianParticipationId` grouping; one render per occupancy and a bed-type badge | `groupCanonicalAccommodationOccupancies`, `canonicalAccommodationChildBedLabel` |
| Missing guardian link | No name-based inference | Child remains visible with `ربط ولي الأمر مفقود` | `renderCanonicalAccommodationCompactOccupants` |
| Capacity | Bed occupancy drives room capacity | `shared` remains visible but does not consume a bed; `base` and `extra` do | `bedOccupancies`, available-room filter and summary |
| Workspace | Rooms are the primary work surface | Four compact headline metrics, secondary chips, unchanged search/filters, houses/floors, compact room grid | `renderCanonicalAccommodation` and scoped `#tab0` styles |

### Measured historical geometry

| Component | Historical source value | Active canonical value |
| --- | --- | --- |
| Room grid | `repeat(auto-fill,minmax(230px,262px))`; row flow; `justify-content:start`; `gap:8px`; `padding:8px`; RTL | Same single scoped owner: `#tab0 .accommodation-floor-rooms` |
| Room card | `align-self:start`; 11px radius; 3px status strip; header min-height 39px; body padding 5px 7px | Same dimensions; height remains content-driven for empty and occupied rooms |
| Desktop room dialog | 880px maximum width after the 940px base rule | `min(880px, calc(100vw - 32px))`; max 880px |
| Tablet room dialog | At 820px: max 760px and one body column | Preserved |
| Mobile room dialog | At 600px: full width, bottom-sheet corners, body padding 9px | Preserved |
| Resident scroll area | Historical desktop maximum 34vh; mobile content joins the modal scroll | Preserved, with the canonical modal body bounded to `100dvh - 24px` |
| Footer | Historical centered actions, 110–145px per action | Two visible canonical actions use centered 120–160px columns; sticky footer remains visible |
| Mobile room grid | Single column at 600px | Single column at 600px; the conflicting 680px override was removed |

At the historical minimum track width, the grid fits 1/2/3/4 cards in approximately 262/500/760/1020px of available floor width. CSS logical `start` under `direction:rtl` places the first card on the right.

## Functional matrix

| Capability | Old reference | Canonical implementation / evidence | Gap closed or remaining acceptance | Acceptance test | Status |
|---|---|---|---|---|---|
| House directory | Local house templates and imported conference houses | `CanonicalConferenceHouses.listRoomOptions`, `chooseCanonicalConferenceHouse` | No local import is used for linked Conferences | `conference-room-assignment-foundation`, `canonical-central-conference-houses` | PASS (programmatic) |
| Assign house and rooms | Active-room manager mutating `conference.houses` | Explicit room assignment with revision, overlap checks and protected dispatcher | Batch UI reports per-room failures | `conference-room-assignment-foundation` | PASS (programmatic) |
| Floors and room hierarchy | Local nested arrays | Canonical house/floor/room projection | Visual layout requires user acceptance | `canonical-accommodation-legacy-ui-parity` | PASS (programmatic), visual BLOCKED |
| Room capacity | Local `beds` and `extraBeds` | `baseCapacity`, `extraBedCapacity`, revisioned room mutation | Server validates simultaneous use by bed type | P5A/P5B and parity tests | PASS (programmatic) |
| Open and close room | Local `closed` flag | Canonical `isClosed` and `closedDay` in room editor | Live interaction requires manual test | P5B tests | PASS (programmatic), operational BLOCKED |
| Search and filters | Room/name search and status filters | House, floor, room, notes, person, phone and church search; occupancy/arrival/key/child filters | None found | parity and frontend cutover tests | PASS (programmatic) |
| Rich room card | Guest rows, status, beds and notes | Current occupancies, history, status, capacity, extra beds, notes, arrival and key holder | Desktop/mobile visual acceptance required | parity and responsive contract tests | PASS (programmatic), visual BLOCKED |
| Room details/editor | `openRoomEditor` / `saveRoomData` | `openCanonicalAccommodationRoomDetails` / `saveCanonicalAccommodationRoomData` | Uses the existing modal but only central mutation | parity tests | PASS (programmatic) |
| Select existing participant | Local people list | Active canonical Participation picker, period availability and stable IDs | None found | frontend cutover tests | PASS (programmatic) |
| Add/select central Person from assignment | Legacy quick-add wrote a local guest row | Existing central Person dialog now opens from the active assignment, creates or attaches Participation, resumes the same room draft and selects it | Added in this round; needs live UI confirmation | parity contract test | PASS (programmatic), operational BLOCKED |
| Base/extra bed assignment | Local guest slots | Protected `assign_conference_accommodation` | Capacity and overlap validated server-side | P5B and frontend tests | PASS (programmatic) |
| Shared child without bed | No canonical representation in original UI | `bedType=shared`, guardian-linked Participation and DB enforcement; exposed in active assignment | Must already have a linked, housed guardian | guardian shared-child journey tests and Development DB proof | PASS (programmatic/DB), UI acceptance BLOCKED |
| Edit stay | Local room save | Same-room protected move with expected revision | None found | frontend and parity tests | PASS (programmatic) |
| Atomic replacement | Local identity replacement | `replace_conference_accommodation`, effective day separated from period edit, idempotency and audit | Live first-day/mid-stay scenarios required | atomic replacement tests | PASS (programmatic), operational BLOCKED |
| Individual/partial transfer | `partialTransferGuest` | Per-occupancy canonical move, explicit effective day and source/destination leases | Multi-person legacy batch is intentionally not a second owner; repeat per resident | parity and lifecycle tests | PASS (programmatic) |
| Removal with history | Local row deletion | Canonical remove closes the stay and preserves history | None found | preserve-history migration tests | PASS (programmatic) |
| Re-accommodation | Re-add local guest | New canonical occupancy after an ended stay | Live user flow required | lifecycle projection tests | PASS (programmatic), operational BLOCKED |
| Arrival | Local boolean | Revisioned occupancy arrival operation with actor and audit | Live interaction required | arrivals-room-keys tests | PASS (programmatic), operational BLOCKED |
| Room key | Local holder ID | Assignment-owned key holder restricted to a current occupant | Live clear/reassign required | arrivals-room-keys and parity tests | PASS (programmatic), operational BLOCKED |
| Apology/reactivation | Local person state | Canonical Participation status; apology transactionally removes active accommodation and downstream assignments | Reactivation does not manufacture a stay | frontend cutover and downstream tests | PASS (programmatic) |
| Concurrent different rooms | No server lock authority | Independent `accommodation_room` resource leases | Requires two-device manual confirmation | resource lease and P5B tests | PASS (programmatic), operational BLOCKED |
| Concurrent same room | Local edit lock | Same-room lease plus expected revision | Requires two-device manual confirmation | resource lease and conflict tests | PASS (programmatic), operational BLOCKED |
| Hydration and stale scope | Local snapshot refresh | Scoped/deduplicated hydration, generation and conference checks | Browser refresh acceptance required | lifecycle/session-stale tests | PASS (programmatic), operational BLOCKED |
| Transportation | Local guest-derived seats | Active occupancy/Participation projection and central transport assignments | Shared-child refresh previously accepted by user; independent seat still manual | downstream and guardian tests | PASS (programmatic), independent-seat BLOCKED |
| Restaurant | Local guest arrays | Operational resident projection from active accommodation | Live module acceptance required | downstream cutover tests | PASS (programmatic), operational BLOCKED |
| Cards | Local guest arrays | `CardEngine` consumes canonical resident projection | Existing baseline failures tracked separately | cards/downstream tests | PASS for ownership; regression suite status reported separately |
| Accounts and reports | Local room arrays | Current-day room people and temporal occupancy projections | Live report comparison required | downstream/nightly/stay-segment tests | PASS (programmatic), operational BLOCKED |
| RTL and responsive shell | Legacy accommodation CSS | Shared tokens/platform shell plus scoped accommodation styles | Browser automation prohibited by `AGENTS.md` | static responsive contracts only | BLOCKED (manual visual) |

## Legacy retirement evidence

- Linked Conferences enter only `renderCanonicalAccommodation`; there is no local renderer fallback.
- `requireLocalOnlyAccommodationMutation()` rejects legacy writers for linked Conferences.
- The active canonical renderer contains no calls to `openRoomEditor`, `saveRoomData`, local `save()`, `room.guests`, or `room.children`.
- Operational consumers use `getConferenceOperationalResidents()` and ignore legacy guest arrays for linked Conferences.
- Legacy functions remain only for unlinked historical/local data because repository rules prohibit deletion before every dependency is proven absent. They are not an active or fallback backend for the canonical Conference route.

## Manual acceptance still required

Browser tests are prohibited by `AGENTS.md`. The following cannot be marked PASS by automation in this workspace: desktop/mobile visual fidelity, modal focus/cancel behavior, two real devices competing for one room, two devices editing different rooms, independent child seat, guardian move/cancel behavior in the rendered UI, and end-to-end module displays after navigation and refresh.
