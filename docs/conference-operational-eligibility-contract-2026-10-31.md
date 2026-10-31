# Conference operational eligibility and family lifecycle — canonical contract

Status: SPECIFICATION ONLY. No database or runtime change is implied by this file.
Scope: `develop` + Supabase Development (`gppwltrifgfxrkzvvxoe`) exclusively. Never deploy to main/Production.

## Identity, participation, accommodation

1. `platform.people` is the permanent identity directory. Removing a booking, conference participation, or occupancy must never delete a person record.
2. A conference participation is distinct from an active occupancy. Removing an occupancy preserves the participation unless a separate participation-delete operation is explicitly requested.
3. An active occupancy is the source of eligibility for accommodation-dependent transport, restaurant, lodging charges, cards, and operational occupancy reports. Historical financial transactions remain auditable.
4. Removing an occupancy must synchronously invalidate dependent active transport assignments and any occupancy-specific overrides; all downstream counts and reports must derive from canonical state. No local or legacy fallback.
5. An apology preserves the booking and its historical payments, excludes it from active participation/attendance/operational counts, and removes occupancy and dependent allocations atomically. Refunds are a separate financial action.
6. A deleted booking removes only the booking's operational links, never `platform.people`. Booking cancellation and apology are distinct operations.

## Guardian and child

1. Guardian relationship is a participation/family relationship, not a requirement to occupy the same room.
2. A shared/no-bed child must occupy the guardian's room and matching interval.
3. A child with an independent base/extra bed may occupy a different room and interval while retaining the guardian relationship.
4. Moving/removing a guardian's occupancy moves/removes only shared child occupancy automatically; independent-bed child occupancy is not implicitly moved or deleted.
5. Deleting a guardian participation must not silently delete an independently accommodated child participation; resolve the relationship explicitly within the authorized atomic operation.
6. No new local state, parallel implementation, or legacy fallback.

## Acceptance scenarios (must be run against Development)

- A: Create adult person, conference participation, accommodation, transport allocation; remove accommodation. Person and participation persist; transport allocation and all accommodation-dependent active outputs disappear after refresh.
- B: Apologize a booked and accommodated participant. Booking remains visible as apologized, payment history remains, active counts drop, occupancy and transport allocation are removed; repeat request is idempotent.
- C: Guardian in room 201, shared child in 201, independent-bed child in 502. Move guardian to 102: shared child follows; independent child stays in 502; both retain guardian link.
- D: Remove guardian occupancy: shared child's occupancy ends; independent child's occupancy remains, guardian relation persists.
- E: Delete conference participation: all dependent occupancy/transport records cleaned; permanent person record survives; no dangling foreign keys.
- F: Verify room concurrency, revisions, approved-device permissions, audit events, idempotency, and rollback on partial failure.
- G: Verify counts in transport, restaurant, finance, cards, reports, and reservation attendance before/after mutations.
- H: Event-defined booking types and attendance periods work without hardcoded conference/caravans; gender and child filters read canonical person fields.

## Known verified gaps (2026-10-31)

- `public.set_conference_participation_status` removes accommodation on apology but does not directly remove transport assignments.
- `public.delete_conference_participation` deletes guardian-linked child participations, including cases requiring independent child retention.
- Reservation event periods, attendance records and booking snapshots constrain segments to `conference`/`caravans`.
- No PASS claim until migration, runtime changes, automated tests, and Development Preview acceptance are complete.
