# P6B canonical Conference-core frontend cutover

For a linked Conference, `PlatformIntegration` is the single frontend boundary
for `get_conference_core` and `mutate_conference_core`. It delegates both calls
to the existing protected module-operation service and stores only the latest
canonical core projection needed for revision control and snapshot protection.

Successful hydration projects canonical identity, organization, name, dates,
status, completion, revision, timestamps, duration, and schedule onto the
active in-memory Conference. Existing participant, accommodation, transport,
and other legacy domain data remain in the same object. Snapshot, conflict,
recovery, linking, and realtime application retain those legacy domains but
restore the canonical core projection before replacing memory or persistence.

Linked Conference edits and completion use `mutate_conference_core` with the
hydrated revision. Success updates memory immediately without `save()`, local
snapshot persistence, or snapshot queue publication. Offline editing is
blocked. Revision conflict leaves the modal draft intact and rehydrates core
through the same boundary. Cross-device canonical realtime is not yet wired;
open and existing refresh paths rehydrate core.

Local-only Conferences retain their existing local edit path. Legacy snapshot
machinery remains for participants, accommodation, Reservations integration,
discovery, recovery, and other unmigrated domains. Its Conference-core merge
guards can be removed after those domains use canonical readers and snapshots
cease replacing Conference objects.
