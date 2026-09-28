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
nonnegative and closed days start at one. `closed_day` is the first Conference
day on which the room is unavailable. When `is_closed` is false it must be
null. When `is_closed` is true, null means immediately/fully closed under the
future protected mutation contract, while a positive value schedules closure
from that Conference day. Physical bed rows and temporary bed IDs remain
derived presentation details.

One occupancy table represents former guests and children. It records arrival
day, optional leave day, base/extra bed classification, and the adult/child fact
only for an extra bed because current account pricing consumes that fact. It
does not create a child identity; future rules should derive age from the
canonical Person where possible. An occupancy is effective on day `d` when
`arrival_day <= d` and `leave_day` is absent or greater than `d`.

`unique(participation_id)` makes the row the current/latest Accommodation
assignment and prevents simultaneous rooms. Move updates the same row; leave
sets `leave_day`; a P5B move increments that row's revision transactionally.
Historical movement belongs in immutable `platform.audit_events`, not
additional occupancy rows. Assign, reassign, apology cleanup, and deletion
cleanup belong to P5B protected mutations.

P5A validates numeric and stay-range shape. Capacity, Conference-duration,
active-participation, and room-closure rules require locked transactional P5B
mutations and are deliberately not implemented as race-prone triggers. Tables
are force-RLS and grant no client role direct mutation access.

Specifically, P5A enforces `arrival_day >= 1`, `leave_day IS NULL OR leave_day
> arrival_day`, and `closed_day IS NULL OR closed_day >= 1`; it does not claim
Conference-duration enforcement. P5B must calculate duration from canonical
Conference `start_date`/`end_date`, validate arrival, leave, and non-null closed
days against it, and exclude a room from occupancy/capacity operations from its
first closed day.

The composite identity keys ensure that occupancy references a participation
from the same Conference. P5A intentionally does not enforce participation
status through a trigger. P5B assign/move operations must require
`participation.status = 'active'`. An active-to-apologized transition must
transactionally remove the current Accommodation effect before or with the
participation transition. No independent Accommodation status is introduced.

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
