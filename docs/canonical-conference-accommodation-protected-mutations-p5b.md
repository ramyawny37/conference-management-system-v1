# P5B canonical Accommodation protected mutations

P5B adds one Conference-scoped hierarchy read and protected structure and
occupancy mutations through the existing Platform dispatcher and P4C router.
Reads require `conference.accommodation.view`; every mutation requires
`conference.accommodation.manage`, an approved account/device session, and an
active, non-deleted Conference. Completed Conferences remain readable.

The read returns ordered houses, floors, rooms, current occupancies,
participation status, and the limited canonical Person display projection. It
stores no denormalized read model.

Structure create/update/delete uses independent entity revisions. Parent
deletion rejects nonempty children and occupied-room deletion rejects. Room
closure updates reject existing stays that extend into the first unavailable
day. Day-dependent mutations derive inclusive Conference duration from
`start_date` and `end_date`; missing or invalid dates fail closed.

Assignment requires an active same-Conference participation. Assignment locks
the destination room before counting canonical occupancies. Movement locks the
source and destination room rows in ascending UUID order, locks the existing
occupancy, updates that same UUID, and increments its revision once. Separate
base and extra-bed counts enforce their respective capacities. Closed rooms and
stays overlapping a scheduled closure reject.

Removal deletes only the current occupancy. Participation and Person remain.
Assign, move, and remove write immutable Platform audit evidence; movement
records old/new room and row values. Ordinary relational commits and returned
canonical identities support later Realtime and immediate UI updates.

No operation ledger is added. These interactive mutations use expected
revisions, uniqueness, row locks, and deterministic current state; automatic
replay would otherwise risk hiding a stale user intent. No permission,
dispatcher, or audit framework is created.

Apology and participation-delete propagation remain for the next reviewed
round. That work must remove occupancy transactionally, audit cleanup, then
change status or satisfy the existing restrictive FK. Person remains.

Legacy snapshot Accommodation is **MIGRATE → REMOVE AFTER ZERO CONSUMERS**.
P5B performs no snapshot write, frontend migration, Reservations integration,
or dual write.

## Temporal capacity and closure correction

The original P5B ASSIGN, MOVE and capacity-update checks counted all stored
room/bed-type rows, incorrectly treating sequential stays as simultaneous use.
The canonical interval is `[arrival_day, effective_leave)`, where
`effective_leave = coalesce(leave_day, conference_duration + 1)`.
Two stays overlap exactly when `existing.arrival_day < requested_effective_leave`
and `requested.arrival_day < existing_effective_leave`. Equality at the
leave/arrival boundary is not overlap. NULL leave occupies through the final
Conference day. Arrival must satisfy `1 <= arrival_day <= conference_duration`.
Explicit departure must satisfy
`arrival_day < leave_day <= conference_duration + 1`; arrival on
`conference_duration + 1` is invalid. ASSIGN and MOVE use the same validation.
The former `leave_day <= conference_duration` check incorrectly rejected an
explicit departure immediately after the final Conference day while allowing
its NULL equivalent. For duration five, `[4,6)`, `[5,6)`, and `[4,NULL)` are
valid; departure seven, arrival six, and departure at/before arrival reject.
Executable ASSIGN/MOVE tests also verify `[1,3)` and `[3,6)` reuse capacity,
and explicit departure six still rejects against scheduled closure day five.

After locking the destination room, ASSIGN counts only overlapping canonical
rows for the requested bed type. MOVE uses the same overlap predicate and
excludes its own UUID, preserving deterministic room lock ordering and same-row
identity/revision behavior. Base and extra capacities remain independent.
These mutation checks count intersecting rows as requested; they do not compute
a daily peak across the requested interval.

Room updates retain their room lock and calculate daily occupancy with
`generate_series(1, duration)`, counting each bed type only when
`arrival_day <= day AND day < coalesce(leave_day, duration + 1)`.
Any day exceeding the proposed base or extra capacity rejects with
`ACCOMMODATION_CAPACITY_CONFLICT`; equivalently, each proposed capacity must
cover its separate peak. No daily rows or aggregate table are persisted.
Empty rooms retain support for undated capacity edits.

`closed_day = D` is the first unavailable day. ASSIGN and MOVE accept a stay
ending exactly D and reject arrival at/after D or effective leave beyond D.
Closure updates apply the same boundary to existing stays and never evict them.
Immediate closure (`is_closed = true`, `closed_day = NULL`) rejects all new
occupancy and cannot be applied to an occupied room.

Validation: run `node --check` and `node --test` against
`tests/canonical-conference-accommodation-protected-mutations-p5b.test.js`,
with `PGHOST`, `PGPORT`, and `PGUSER` pointing to an isolated disposable
PostgreSQL cluster, never a Development or Production server. The harness
creates and drops its own database and any missing test roles.

Executable cases cover sequential and overlapping base/extra stays, NULL leave
through day five, independent capacities, reductions from total rows to daily
peaks, scheduled/immediate closure for assignment/movement and room updates,
and MOVE rejection/success with UUID and revision preservation. The original
final-slot race remains. Additional temporal races hold the first transaction's
room lock and observe the second backend waiting on a lock: overlapping stays
produce exactly one success and one capacity rejection; sequential stays both
succeed. P5A schema and P4C routing remain unchanged.
