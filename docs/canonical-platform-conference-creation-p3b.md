# P3B canonical Platform Conference creation

P3B adds `create_canonical_conference` to the existing verified Platform
Conference dispatcher. It creates the P3A `public.conferences` root for the
future server-first runtime. It does not connect or alter the current local
Conference UI, publishing engine, snapshots, synchronization, Reservations,
Warehouse, Conference sections, or Person Bank.

## Authority and input contract

The dispatcher accepts `create_canonical_conference` with exactly:

- `p_operation_id`
- `p_requested_conference_id`
- `p_organization_id`
- `p_name`
- `p_start_date`
- `p_end_date`

The verified session supplies the actor and approved device. The only creation
authority is the module-scoped `conference.lifecycle.create` Platform grant
(with the existing system-owner authority supported by the same resolver). An
exact Conference resource grant is neither accepted nor required before the
Conference exists. Clients cannot supply actor, device authorization, status,
revision, timestamps, completion state, permission, or grant identity.

`organization_id` remains required business data because current database and
Reservations contracts retain the Conference/Organization relationship. P3B
requires that the referenced Organization exists and is active. Organization
membership does not authorize or block canonical creation.

The created row has normalized `name`, the requested inclusive date range,
`status = active`, `completed_at = NULL`, and `revision = 1`. Days, nights, and
schedule remain derived values and are not stored as database authority.

## Execution, replay, and audit

The protected route is:

`platform.execute_conference_device_operation`
→ `public.create_canonical_conference`

The internal creation function has EXECUTE revoked from PUBLIC, `anon`,
`authenticated`, and `service_role`.

P3B reuses `public.conference_creation_operations`; it does not add another
operation ledger. Idempotency is scoped to the verified actor and operation
UUID. The ledger binds that identity to the requested Conference UUID and the
complete normalized immutable request. An identical replay returns the same
initial creation contract with `created = false` and creates neither a second
Conference nor another audit row. Reuse with different Conference,
Organization, normalized name, or dates fails with
`CANONICAL_CONFERENCE_CREATE_OPERATION_MISMATCH`.

Successful first creation writes `platform.audit_events` with the verified
actor, device authorization, operation UUID, module permission, authority
source, grant identity, Conference identity, Organization business link, and
initial canonical values. No audit identity comes from request data.

P3B removes the global `conferences_add_owner_membership` trigger and its
`add_conference_owner_membership` function. Canonical creation inserts only the
Conference row and does not bootstrap Conference membership or depend on
Organization membership. The surviving legacy Organization-aware creator now
inserts its required owner membership explicitly in the same idempotent
transaction. Its device, Organization membership, ledger, and replay behavior
remain unchanged.

The existing outer Phase1C Conference dispatcher now routes canonical create
and core mutation operations through explicit branches after one verified
session check. All unchanged legacy operations continue to the existing core.
No migration-time function-definition inspection or string replacement is
used, and no second dispatcher is introduced.

## Migration boundaries

The old `device_guarded_create_organization_conference_idempotent` operation is
classified **REMOVE AFTER ZERO LEGACY PUBLISHING CONSUMERS**. It remains solely
for the unchanged local/snapshot generation. The canonical operation never
calls it and has no Organization-membership fallback.

The future Platform UX contract is server-first: successful mutations update
the current UI without manual reload; changes from elsewhere propagate through
realtime, invalidation, or refetch; editing preserves search and selection
context where practical; failures preserve drafts where practical; duplicate
submission is prevented; revision conflicts are explicit; and sensitive
mutations rely on confirmed server results. P3B records this contract without
adding frontend infrastructure.
