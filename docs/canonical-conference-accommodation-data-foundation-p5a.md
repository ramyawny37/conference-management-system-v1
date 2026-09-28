# P5A canonical Conference Accommodation data foundation

P5A replaces no runtime data. It establishes four normalized Conference-owned
tables for houses, floors, rooms, and occupancies. Each row has a stable UUID,
its own optimistic revision, timestamps, and trusted creator/updater fields.
Positions on houses, floors, and rooms preserve deterministic UI ordering.

Every hierarchy level carries `conference_id` and uses composite foreign keys,
so a floor cannot reference another Conference's house, a room cannot reference
another Conference's floor, and an occupancy cannot combine a room and
participation from different Conferences. Occupancy reaches Person only through
`conference_participations`; no Person profile fields are copied.

Rooms retain the active business facts: room number, base capacity, extra-bed
capacity, notes, closed state, and optional closed day. Capacities are
nonnegative and closed days start at one. Physical bed rows and temporary bed
IDs remain derived presentation details.

One occupancy table represents former guests and children. It records arrival
day, optional leave day, base/extra bed classification, and the adult/child fact
only for an extra bed because current account pricing consumes that fact. It
does not create a child identity; future rules should derive age from the
canonical Person where possible. An occupancy is effective on day `d` when
`arrival_day <= d` and `leave_day` is absent or greater than `d`.

`unique(participation_id)` makes the row the current/latest Accommodation
assignment and prevents simultaneous rooms. Move updates the same row; leave
sets `leave_day`; assign, reassign, apology cleanup, and deletion cleanup belong
to P5B protected mutations. The model does not attempt a movement-history
ledger.

P5A validates numeric and stay-range shape. Capacity, Conference-duration,
active-participation, and room-closure rules require locked transactional P5B
mutations and are deliberately not implemented as race-prone triggers. Tables
are force-RLS and grant no client role direct mutation access.

Occupancy uses `ON DELETE RESTRICT` for participation. P4B hard deletion must
therefore be extended in P5B to remove Accommodation operational effect and
write the required audit evidence before deleting participation. Accommodation
deletion never deletes `platform.people`.

Template source IDs are omitted: copied Conference instance structure is
independent after creation, and existing source IDs are migration metadata
rather than authority. No template system is added.

Legacy `conference_snapshots.data.houses` is **MIGRATE → REMOVE AFTER ZERO
CONSUMERS**. P5A adds no migration, mirror, trigger, or dual write. The current
frontend, Reservations, Transportation, Cards, Reports, Accounts, and snapshot
data remain unchanged. Existing `conference.accommodation.view/manage`
permissions and the P4C router are also unchanged; P5B will add protected
operations after independent schema review.
