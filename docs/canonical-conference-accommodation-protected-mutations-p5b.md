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
