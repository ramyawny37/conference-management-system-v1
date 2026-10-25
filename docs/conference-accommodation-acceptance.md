# Conference Accommodation Acceptance Matrix

Baseline: `3b873074c80bdbd4f36c8b9aeb932dcafe6e0bd3`

Functional reference: `cccba23a9b13e800cd6e95c96c86bd02ad56bf2a`. The old commit is a behavior reference only; its local `conference.houses`, `room.guests`, `room.children`, `save()` and IndexedDB paths are not valid owners for a linked Conference.

Canonical runtime owner:

`Person -> Conference Participation -> Active Accommodation Occupancy -> Operational Modules`

The active UI owner is `renderCanonicalAccommodation()` in `script.js`. Reads and mutations are owned by `PlatformIntegration`, the protected Conference dispatcher, and the canonical PostgreSQL tables. Every successful accommodation mutation rehydrates Accommodation, Transportation, Restaurant, and the active tab before reporting refreshed state.

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
