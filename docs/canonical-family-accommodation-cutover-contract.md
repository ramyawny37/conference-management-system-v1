# Canonical family accommodation cutover contract (Development only)

Status: **design contract, not implemented**. Baseline: `6a0dcded4e81e3856dbd7bc133f2c15039174221`.

## Ownership and invariants

1. A guardian relationship belongs to the conference participation and is independent of accommodation room. An occupancy must never be the authoritative source of a family relationship.
2. An independently bedded child may occupy any eligible room and date range within their participation, including a room different from the guardian's. Moving or removing that child's occupancy must not change their guardian relationship.
3. A shared-bed child consumes no bed, must have a compatible live guardian occupancy, and must not become orphaned by a guardian move, replacement, or removal. Such operations must atomically migrate/resolve the shared stay or reject with a stable error.
4. Guardian move/replacement/removal must not silently move or delete independently bedded children's stays. Moving explicitly selected children is a separate group operation with per-child revisions and capacity validation.
5. A guardian-child relation does not imply a child is attending the event. Child participation and occupancy must be explicitly created or selected.
6. Room capacity, stay overlap, immutable history, authorization, audit, idempotency, revision checks, and room leases remain enforced by the database.

## Atomic operation boundary

The new family room draft API must accept an operation ID, the guardian participation or creation draft, zero or more child participation drafts, and zero or more occupancy mutations with explicit room, bed kind, and dates. It must derive and validate the complete set of affected rooms, require a valid lease for **every** affected room, lock rooms in a deterministic order, and commit all changes in one PostgreSQL transaction. No client-side save-guardian-then-save-child sequence. On any validation failure, the transaction rolls back.

## UI contract

A single RTL room editor allows guardian selection and any number of children before the first save; each child can be shared with the guardian, independently bedded in the same room, or independently bedded in another room. Show remote children under the guardian as links only, with their actual room number, and show their occupancy in the actual room. Count beds only in the actual room. No duplicate actions or nested save dialogs.

## Required acceptance scenarios

- New guardian + new shared child, one save.
- New guardian + independently bedded child in the same room, one save.
- New guardian in room A + independently bedded child in room B, one save and leases for both rooms.
- Existing guardian + child independently moved from B to C; guardian relation unchanged.
- Guardian moves without independently bedded child; child stays in B.
- Guardian moves with selected independently bedded child; each stay retains explicitly chosen bed properties.
- Guardian replacement/removal leaves remote bedded child intact.
- Shared child cannot be left without a compatible guardian occupancy after move/replacement/removal.
- Capacity/overlap/revision/lease/permission failures roll back the whole draft.
- Idempotent retry, refresh/rehydration, restaurant/transport/cards/report occupancy projections.

## Existing incompatible contracts to replace (not edit historical migrations)

- `20261026111500_reject_direct_linked_child_stay_moves.sql`
- `20261026162000_guardian_move_cascades_children.sql`
- `20261026170000_guardian_replacement_removes_housed_children.sql`
- `20261027150000_atomic_guardian_child_accommodation.sql`
- Single-room `save_conference_accommodation_room_draft` and one-room lease assumptions.

Create new forward-only migrations replacing the active RPC definitions, update dispatcher/integration/editor together, and revise historical behavior tests to assert this contract. Do not deploy an incomplete cutover.
