# P3A: canonical server Conference core foundation

Status: schema/API foundation on `develop`. No frontend source-of-truth switch, section migration, snapshot change, database application, deployment, commit, or push.

## Existing root and reused objects

`public.conferences` is the only Conference root. Before P3A it contains UUID `id`, `name`, immutable legacy `owner_id`, `organization_id`, `created_at`, trigger-maintained `updated_at`, and soft-removal compatibility field `deleted_at`. Its UUID primary key is referenced directly by memberships, snapshots, sync history, locks, Reservations links, and other existing consumers. P3A extends this table and creates no second root.

P3A reuses:

- the existing UUID primary key and `conferences_set_updated_at` trigger;
- `platform.execute_conference_device_operation_phase1c_core` and its approved account/device/session validation;
- `require_effective_module_permission` and U2B `conference.lifecycle.manage` exact-resource authority;
- the U2B module-scoped `conference.lifecycle.create` definition, without adding or changing a creation operation;
- `platform.audit_events` for immutable actor/device audit history;
- existing `owner_id` as legacy ownership and creation attribution, instead of adding a duplicate creator column.

No new operation ledger, authorization engine, device/account model, Organization abstraction, trigger, index, or Conference table is introduced.

## Narrow schema finding

The existing root safely supports extension, but lacks dates, lifecycle state, completion time, and a core concurrency version. Snapshot `revision` belongs to `conference_snapshots`; using it for Conference identity/lifecycle would couple the new server core to the retiring snapshot architecture. P3A therefore adds a separate `public.conferences.revision` for the row it protects.

The final core columns are:

| Concept | Canonical field/contract |
| --- | --- |
| Identity | `id uuid` primary key |
| Name | trimmed, 1–500 character `name` |
| Dates | nullable paired `start_date` / `end_date`; `end_date >= start_date` |
| Lifecycle | `status` constrained to `active` or `completed` |
| Completion | `completed_at`, null for active and required for completed |
| Creation time/attribution | existing `created_at` and legacy `owner_id` |
| Update time/attribution | existing `updated_at`, plus trusted `updated_by` |
| Concurrency | `revision bigint`, starting at 1 and incremented once per canonical mutation |
| Legacy removal compatibility | existing `deleted_at`; no new delete behavior |

Dates remain nullable only so the migration does not rewrite current rows. The canonical mutation requires both dates, so any row entering the new contract becomes complete. `days`, `nights`, and `schedule` are not columns: the mutation response derives inclusive days, nights, and a date-array schedule from the date range.

## Organization classification

`organization_id` is **BUSINESS DATA with legacy authorization consumers**. Business evidence is the unique `(id, organization_id)` key and Reservations composite foreign key binding Conference-scoped Events to the same Organization. Existing Conference creation, membership integrity, discovery, and Reservations access also use Organization membership as legacy authorization. P3A preserves all of those consumers unchanged and does not clean them up.

The new `mutate_conference_core` operation neither accepts nor queries Organization identity or membership. Its authority is the exact Conference UUID in the Platform grant engine. The retained `organization_id` therefore does not become the canonical authorization owner.

## Protected mutation contract

`mutate_conference_core` is added to the existing Conference protected dispatcher. Its accepted payload is exactly:

`p_conference_id`, `p_expected_revision`, `p_name`, `p_start_date`, `p_end_date`, `p_status`.

The dispatcher derives the device from its verified Platform session. The function derives the user from `require_effective_module_permission`; client actor or device overrides are rejected by the existing dispatcher/exact-key boundary. Authorization is `conference.lifecycle.manage` with `resource_type=conference` and `resource_id=p_conference_id::text`.

The operation locks the exact row, rejects missing/soft-deleted Conferences, rejects stale revisions with SQLSTATE `40001`, validates name/date/state server-side, and increments the revision. Current live semantics establish `active -> completed`; a completed core is terminal in P3A because no current reopen behavior was verified. Archive and delete remain separate legacy capabilities and are not implemented here.

Every applied mutation writes the actor user, verified Platform device authorization, old/new core values, authority source, and grant ID to immutable `platform.audit_events`. The row also stores trusted `updated_by`. No client-supplied actor identity exists in either function or dispatcher payload.

P3A adds no create operation. The current creation path is coupled to Organization membership by existing owner-membership triggers. Adding a new create operation without that dependency would require changing legacy consumers, which is outside P3A; carrying the dependency into a new canonical operation would violate the no-new-Organization-authorization rule. The U2B module-scoped `conference.lifecycle.create` contract remains ready for the later isolated creation cutover.

## Explicit boundaries

No `conference_v2`, `conference_people`, Person Bank link, section table, day/night/schedule column, section payload, local-data import, or compatibility snapshot layer is created. P3A does not touch `conf_v5`, IndexedDB, localStorage, ConferenceRepository, snapshots, sync queues, conflict resolution, rescue/recovery, realtime behavior, Reservations, Warehouse, frontend code, or Arabic text.
