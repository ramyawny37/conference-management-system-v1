# P5C Participation to Accommodation propagation

P5C extends the existing canonical Participation lifecycle operations,
`set_conference_participation_status` and `delete_conference_participation`.
It creates no parallel lifecycle API, dispatcher, ledger, participant status,
or Accommodation shadow state. Participation remains the lifecycle authority.

An active-to-apologized transition deletes the participation's current
canonical Accommodation occupancy before changing status. Participation stays
visible, its revision increases once, and Person remains. Reactivation changes
the Participation back to active and increases its revision once, but does not
restore Accommodation or infer a former room. A Participation hard delete first
deletes current Accommodation explicitly and then deletes Participation;
Person remains. The P5A restrictive foreign key is unchanged.

Both effects occur in the same PostgreSQL transaction as the original P4B
operation. Failure rolls back cleanup, Participation mutation, operation result,
and audit together. Existing P4B actor-scoped replay is retained. Replay returns
the stored result before cleanup, so cleanup and its audit occur once. Completed
Conference mutation policy is unchanged.

## Authority and audit

Mandatory cleanup caused by apology or deletion uses the already validated
exact Conference-resource `conference.people.manage` authority. It does not
require `conference.accommodation.manage`, because no independent room decision
is being made. Explicit assign, move, and remove continue to require
`conference.accommodation.manage` through the unchanged P5B context check.

The private cleanup helper records
`conference.accommodation.participation_cleanup` in `platform.audit_events`.
Its immutable old values contain the complete prior occupancy. Metadata records
Conference, Participation, occupancy, previous room, cause
(`participation_apologized` or `participation_deleted`), permission key,
authority source, and grant identity. Actor, approved device authorization, and
P4B operation ID are stored in their audit columns. The normal Participation
status/delete audit remains a separate event in the same transaction. The
helper has no client EXECUTE privilege, and direct canonical table mutation
remains denied.

## Lock protocol

All operations affecting this invariant lock the Participation row first.
ASSIGN then locks its destination room. MOVE locks Participation, rereads the
current occupancy, locks source and destination rooms in ascending UUID order,
then locks the occupancy. Apology and Participation deletion lock Participation
then the current occupancy through the cleanup helper. This serializes the
active-status decision with creation or movement of Accommodation while
preserving P5B's deterministic room order.

MOVE performs an initial non-locking occupancy read solely to discover its
Participation UUID. P5C makes `participation_id` and `conference_id`
structurally immutable for the lifetime of an occupancy through a `BEFORE
UPDATE` trigger. Canonical MOVE never reparents an occupancy, client roles
cannot update the table directly, and even a privileged direct update now
rejects. The discovered Participation is therefore the only possible owner.
After locking it, MOVE rereads the occupancy and verifies the same
Participation before locking rooms; concurrent REMOVE can only make the row
disappear, which produces `ACCOMMODATION_OCCUPANCY_NOT_FOUND` after safe
serialization.

Participation `conference_id` has no canonical mutator and direct client table
mutation is denied, but P4B did not make the column structurally immutable.
P5C therefore does not rely on the discovery read for final authority. Status
and delete first perform the established early permission check, then lock the
Participation row and revalidate `conference.people.manage` against the
locked row's `conference_id` before cleanup or mutation. The authorized
Conference and the mutated Participation are thus bound under the row lock.

Explicit REMOVE needs only its occupancy lock and acquires no later
Participation or room lock, so it cannot form a reverse-order cycle. If REMOVE
wins, lifecycle cleanup finds no occupancy; if lifecycle cleanup wins, REMOVE
finds no occupancy. Room structure mutations retain their existing room lock
and do not acquire Participation locks.

Consequently, concurrent ASSIGN/MOVE followed by apology or deletion completes
without an orphan: the lifecycle operation waits, observes and removes the
committed occupancy, then changes or deletes Participation. If lifecycle wins
the Participation lock first, later ASSIGN/MOVE observes apologized or missing
Participation and rejects. After either order, missing or apologized
Participation has zero canonical occupancy.

The P5C executable PostgreSQL proof observes actual lock waiting for ASSIGN vs
APOLOGIZE, MOVE vs APOLOGIZE, ASSIGN vs DELETE, MOVE vs DELETE, MOVE vs MOVE,
and REMOVE vs MOVE. Same-occupancy moves serialize and the stale expected
revision rejects after the first move increments it. REMOVE vs MOVE serializes
to a deleted occupancy, one removal audit, no move audit, and an unchanged
active Participation. The proof also covers cleanup/no-cleanup, reactivation
without restoration, Person survival, restrictive FK retention, authority
separation, exact-once audit/replay, ownership immutability, helper ACLs, and
direct-table ACLs. P4C routing and the outer dispatcher remain unchanged.

P5C writes ordinary canonical Participation and Accommodation rows for future
Realtime observation. It does not update legacy snapshot JSON, Reservations,
Transportation, Cards, Reports, Accounts, or Person Bank, and introduces no
generic event infrastructure or additional ledger.
