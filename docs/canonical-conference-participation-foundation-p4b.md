# P4B canonical Conference Participation foundation

P4B links one canonical `platform.people` identity to one exact canonical
Conference. `public.conference_participations` uses a surrogate UUID so future
Accommodation and downstream records can hold a stable participation reference;
a unique `(conference_id, person_id)` constraint enforces one participation per
person per Conference. It copies no Person, booking, or Accommodation data.

Each row stores `conference_id`, `person_id`, `status`, independent optimistic
`revision`, timestamps, and trusted creator/updater identities. Live status is
`active` or `apologized`. Apologized rows remain visible but are excluded from
the active count. Reactivation is allowed. Deletion hard-deletes only the
participation; the restrictive Person foreign key and immutable Platform audit
preserve identity and deletion evidence.

Completed Conferences remain readable and are immutable for create, status, and
delete operations. Deleted Conferences are neither readable nor mutable.
Authority is the existing approved Platform session/device plus exact Conference
resource permission: `conference.people.view` for list and
`conference.people.manage` for mutations. Organization membership and
`conference_members` are never consulted.

The protected operations are `list_conference_participations`,
`create_conference_participation`, `set_conference_participation_status`, and
`delete_conference_participation`. The existing
`platform.execute_conference_device_operation` dispatcher validates the session,
injects the verified device, and routes to internal functions whose EXECUTE is
revoked from all client roles.

`public.conference_participation_operations` is the narrow actor-scoped mutation
ledger because existing ledgers bind other domains and request shapes. Identical
operation replay returns the stored result; immutable request mismatch fails.
Each successful first mutation writes verified actor/device, exact permission,
authority/grant, Conference, Person, participation, revisions/status, and
operation UUID to `platform.audit_events`.

The list response contains canonical rows plus `totalCount`, `activeCount`, and
`apologizedCount`. Mutation responses contain current canonical state for later
same-page UI updates without reload-driven synchronization.

Legacy `conference_snapshots.data.peopleDb` is **MIGRATE / REMOVE AFTER ZERO
CONSUMERS**. Existing `reservations.conference_person_links` and Reservations
legacy snapshot-person creation remain later migration consumers; standalone
Reservations remains independent. P4B adds no bridge or dual write.

The next Accommodation migration may reference participation UUIDs and must
admit only active participation. Apologized participation has zero current
operational effect; deleting participation must remove future Conference-specific
operational effects. P4B does not mutate Accommodation or snapshot JSON.
