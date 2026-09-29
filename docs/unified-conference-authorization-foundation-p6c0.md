# P6C0 unified Conference authorization foundation

## Current authority inventory

Canonical P3/P4/P5/P6B0 operations already use the Platform path:
approved account/session/device, `platform.execute_device_operation`, and
`require_effective_module_permission`. Exact Conference resource grants are
stored in `module_permission_grants`. System Owner remains the existing
Platform-wide owner authority. P6C0 adds the sole Conference-owner inheritance
rule to that resolver; it creates no permission engine or grant store.

Legacy runtime authority still exists separately and is temporary:

- `conference_members.role` drives `get_my_conference_access`, member listing
  and administration, snapshot upload/download, sync conflict handling,
  section locks, discovery and legacy RLS/trigger predicates.
- The roles are `owner`, `manager`, `viewer`, `accommodation_viewer`, and
  `transport_viewer`.
- `canManageMembers`, `canSync`, `canResolveConflicts`, and `canAcquireLock`
  are derived by the legacy access RPC. They are consumed by
  `conference-members-service.js`, `conference-members-ui.js`,
  `conference-queue-integration.js`, `automatic-sync-orchestrator.js`, and
  wrong-binding repair.
- Role consumers also remain in `conference-activation-authorization.js`,
  `discovered-conference-open-service.js`, `conference-realtime-manager.js`,
  `diagnostics-privacy-policy.js`, `user-management-ui.js`, and membership
  attempt/UI code.
- Organization membership remains a creation/linking and legacy tenant
  prerequisite. Organization owner/admin roles do not imply Conference
  resource permission.
- `conference_participations` and participant status are business data only;
  canonical authorization functions never consult them.

Account approval, Platform System Owner, approved device authorization,
session/token verification, module admission, catalog validation, module and
resource grants, revocation, intent/audit records, and canonical Conference
ownership are distinct sources. Only the existing Platform resolver combines
the applicable sources for canonical operations.

## Target contract and owner rule

Every non-System-Owner caller first passes approved-device admission and
`module.access`. Business authority then comes from an active matching module
or exact-resource grant. For `module=conference`, `resource_type=conference`,
the user in `public.conferences.owner_id` inherits the requested active catalog
permission for that Conference only. The result records
`authoritySource=conference_owner`; no boolean capabilities or grant rows are
generated. Conference membership, Organization ownership, and participation
never enter this rule.

The owner rule applies only after catalog validation and module admission. It
does not imply Conference creation because creation is module-scoped and has no
Conference resource. It does not authorize Conference B for the owner of
Conference A. Completed-Conference reads remain controlled by each canonical
operation's existing lifecycle rules.

## Current Conference permission catalog

The existing catalog contains 29 active permissions. Creation is module-scoped;
all others are exact `conference` resources.

| Permission | Current/target consumer |
| --- | --- |
| `conference.access.view` | canonical core read and granted-Conference discovery |
| `conference.lifecycle.create` | canonical Conference creation |
| `conference.lifecycle.manage` | canonical metadata edit and completion |
| `conference.lifecycle.archive` | legacy archive/restore; migrate next |
| `conference.lifecycle.delete` | legacy delete; migrate next |
| `conference.data.export` | legacy Conference export/backup; migrate next |
| `conference.data.restore` | legacy Conference restore; migrate next |
| `conference.members.view` | legacy access-directory read; migrate next |
| `conference.members.manage` | legacy access administration; migrate next |
| `conference.sync.write` | snapshot synchronization; migrate next |
| `conference.conflict.resolve` | snapshot conflict resolution; migrate next |
| `conference.people.view` | canonical participation listing |
| `conference.people.manage` | canonical participation create/status/delete and lifecycle accommodation cleanup |
| `conference.accommodation.view` | canonical Accommodation read |
| `conference.accommodation.manage` | canonical houses/floors/rooms and assign/move/remove |
| `conference.transport.view` | legacy transport view; migrate with domain cutover |
| `conference.transport.manage` | legacy transport mutation; migrate with domain cutover |
| `conference.accounts.view` | legacy Conference financial view |
| `conference.accounts.manage` | legacy Conference financial mutation |
| `conference.restaurant.view` | legacy restaurant view |
| `conference.restaurant.manage` | legacy restaurant mutation |
| `conference.air_conditioning.view` | legacy air-conditioning view |
| `conference.air_conditioning.manage` | legacy air-conditioning mutation |
| `conference.reports.view` | legacy reports view |
| `conference.reports.export` | legacy report export/print |
| `conference.cards.view` | legacy cards view |
| `conference.cards.export` | legacy card export/print |
| `conference.search.view` | legacy Conference search |
| `conference.settings.view` | legacy Conference settings view |

No dead operation receives a new permission. Locks remain concurrency
preconditions rather than a catalog business permission; legacy lock role
admission must migrate to the exact write permission for the locked section.

## Canonical operation mapping

- Core read: `conference.access.view`.
- Core edit/completion: `conference.lifecycle.manage`.
- Creation: `conference.lifecycle.create`.
- Participation list: `conference.people.view`.
- Participation create/status/delete and apology/delete propagation:
  `conference.people.manage`.
- Accommodation read: `conference.accommodation.view`.
- Houses, floors, rooms, assignment, movement and removal:
  `conference.accommodation.manage`.

All use the existing dispatcher and validated Platform device session. No Edge
or frontend runtime change is needed in P6C0.

## Peer-module comparison

Warehouse uses the same catalog/grant resolver through store-scoped
`warehouse_private.require_permission`. Reservations uses it with event-scoped
grants. P6C0 changes neither module's catalog, resource rules, functions,
dispatcher routes, Edge allowlists, or frontend behavior. The owner branch is
strictly `module_key=conference` and `resource_type=conference`.

## Legacy retirement map

### DELETE NOW

None. No legacy table, RPC, UI, or helper has zero consumers after this
foundation step.

### KEEP TEMPORARILY

- `conference_members`, membership operations and role values: member UI,
  discovery, legacy activation, snapshots, sync/conflicts, locks, diagnostics,
  repair, and user administration still consume them.
- `get_my_conference_access` and its four booleans: the named frontend sync,
  member and repair consumers remain.
- Conference Members UI: still administers legacy access roles; it is an
  authorization UI, not participant UI.
- Organization membership predicates: legacy creation/linking and retained
  Organization business administration still consume them.
- Historical role constraints, RLS, triggers and audit rows: required until
  their live forward replacements and retention rules are complete.

### MIGRATE NEXT

- Member directory and role administration → `conference.members.view` and
  `conference.members.manage`, using generic resource grant administration.
- Activation/discovery → `conference.access.view` effective capabilities.
- Snapshot/sync → section permission plus `conference.sync.write`.
- Conflicts → section permission plus `conference.conflict.resolve`.
- Section locks → the exact section write permission, retaining lock semantics.
- Diagnostics, repair and user-management Conference role controls → exact
  catalog permissions and existing generic grant audit paths.
- Archive, restore, delete and Conference-scoped backup/export → their catalog
  permissions when those operations receive canonical server boundaries.

### HISTORICAL MIGRATION ONLY

All applied migrations defining Conference roles, membership RLS, legacy RPCs,
snapshot authorization and lock authorization. They remain immutable evidence;
retirement must use forward migrations.

## Duplicate/dead-path conclusion

The repository still has two authority paths only because legacy consumers
remain: canonical Platform permissions and legacy membership roles. P6C0 adds
no third path. No role adapter, boolean derivation, dispatcher, session model,
catalog, grant table, or frontend gate is added. No current legacy artifact is
deleted because none has proven zero consumers in this round.
