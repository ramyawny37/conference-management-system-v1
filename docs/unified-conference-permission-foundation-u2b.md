# U2B: canonical Conference permission foundation

Status: foundation only, on develop. No runtime cutover, live grant backfill, member migration, deployment, or live database application. The JSON under tests/fixtures is review/test data, not a permission service and not a runtime role registry.

## Phase A conclusion and evidence

Reuse is valid. `public.platform_modules` already registers `conference` exactly once through its primary key (`20260830120000_integrated_platform_module_registration.sql`). `public.module_permission_catalog` supports module/resource/both scope modes and namespaced three-or-more-component keys (`20260829130000_module_permission_catalog_and_grant_adapter.sql`). `public.module_permission_grants` already stores `(user_id,module_key,permission_key,resource_type,resource_id)` with revocation history. Its current device foreign keys target `platform.user_device_authorizations` (`20260920221928_canonical_platform_device_authority_reconciliation.sql`). No additional grant, role, compatibility, or permission-resolution object is needed.

`require_effective_module_permission` (`20260907140000_module_access_delegation_enforcement.sql`) uses current approved-device admission, validates the business catalog, preserves the existing System Owner path, then requires module access and an active matching grant. Resource grants match exact type and ID. `module.manage` implies module admission, not arbitrary business permission. Both foundation permissions are module-wide and remain outside the business catalog. Existing account approval, device/session binding, revocation, operation intent and audit history remain authoritative.

Reservations uses event-scoped grants and `require_effective_module_permission` (`20260915220000_reservations_authorization_architecture_reconciliation.sql`); Warehouse uses store-scoped grants through `warehouse_private.require_permission` (with `warehouse_private.authorization_entry` recording audit context) (`20260829140200_warehouse_v1_guarded_rpc.sql`). U2B changes neither implementation nor catalog. Existing Organization prerequisites in Reservations are consumers to inventory, not a basis for new Conference permission definitions.

Grant administration remains `manage_foundation_module_grant`, `manage_catalog_module_grant`, `list_module_permission_grants`, `list_module_permission_catalog_for_administration`, and the existing operation/audit tables. The current catalog-grant administrator requires System Owner or module-wide `module.manage`. Conference owners MUST NOT receive that foundation permission automatically. The new resource-level `conference.members.manage` describes the future exact-Conference administration boundary; it does not make the current grant administrator accept it. U2C must migrate that canonical administration consumer without an old/new OR check, retaining intent binding, audit and revocation protections. Generic resource discovery currently implements Warehouse/store and Reservations/event only (`20260916120000_generic_module_permission_resource_administration.sql`); Conference discovery is a later consumer change, not an alternate discovery service in U2B.

## Catalog and scope

The migration only inserts missing catalog rows, fails on conflicting pre-existing definitions, and is idempotent. It requires the existing active Conference module and canonical validation/resolution objects. It neither registers another module nor creates grants. All rows have `catalog_version=1`, `status=active`. `sensitive_mutation` follows existing catalog conventions, including exports as sensitive capabilities.

All existing-Conference business permissions are **resource-only**, type `conference`, ID equal to the exact canonical `public.conferences.id::text`. This intentionally prevents converting one membership into all-Conference authority. Creation is the sole module-scoped business permission and is never inferred from a role on an existing Conference.

| Permission key | Scope mode | Resource type | Sensitive | Business scope |
| --- | --- | --- | --- | --- |
| `conference.access.view` | resource | conference | false | Discover the granted Conference and read its access metadata; section data requires its own permission. |
| `conference.lifecycle.create` | module | NULL | true | Create a Conference; existing Conference membership alone does not grant this module-level capability. |
| `conference.lifecycle.manage` | resource | conference | true | Edit metadata and complete the granted Conference. |
| `conference.lifecycle.archive` | resource | conference | true | Archive or restore the archive of the granted Conference. |
| `conference.lifecycle.delete` | resource | conference | true | Delete the granted Conference subject to its lifecycle protections. |
| `conference.data.export` | resource | conference | true | Export or back up data for the granted Conference; never authorizes other Conferences. |
| `conference.data.restore` | resource | conference | true | Restore data for the granted Conference; creation and other Conferences require separate authority. |
| `conference.members.view` | resource | conference | false | Read the membership directory of the granted Conference. |
| `conference.members.manage` | resource | conference | true | Administer user access only for the granted Conference; does not confer Platform module administration. |
| `conference.sync.write` | resource | conference | true | Synchronize authorized changes to the granted Conference; never bypasses section or revision checks. |
| `conference.conflict.resolve` | resource | conference | true | Resolve synchronization conflicts for authorized data in the granted Conference. |
| `conference.people.view` | resource | conference | false | Read people data within the granted Conference. |
| `conference.people.manage` | resource | conference | true | Manage people data within the granted Conference. |
| `conference.accommodation.view` | resource | conference | false | Read accommodation data within the granted Conference. |
| `conference.accommodation.manage` | resource | conference | true | Manage accommodation data within the granted Conference. |
| `conference.transport.view` | resource | conference | false | Read transport data within the granted Conference. |
| `conference.transport.manage` | resource | conference | true | Manage transport data within the granted Conference. |
| `conference.accounts.view` | resource | conference | false | Read accounts data within the granted Conference. |
| `conference.accounts.manage` | resource | conference | true | Manage accounts data within the granted Conference. |
| `conference.restaurant.view` | resource | conference | false | Read restaurant data within the granted Conference. |
| `conference.restaurant.manage` | resource | conference | true | Manage restaurant data within the granted Conference. |
| `conference.air_conditioning.view` | resource | conference | false | Read air conditioning data within the granted Conference. |
| `conference.air_conditioning.manage` | resource | conference | true | Manage air conditioning data within the granted Conference. |
| `conference.reports.view` | resource | conference | false | Read reports data within the granted Conference. |
| `conference.reports.export` | resource | conference | true | Export and print reports data within the granted Conference. |
| `conference.cards.view` | resource | conference | false | Read cards data within the granted Conference. |
| `conference.cards.export` | resource | conference | true | Export and print cards data within the granted Conference. |
| `conference.search.view` | resource | conference | false | Read search data within the granted Conference. |
| `conference.settings.view` | resource | conference | false | Read settings data within the granted Conference. |

## MIGRATION/BOOTSTRAP MAPPING (future migration planning only)

For an already-authorized `(user_id, conference_id, role)`, map only the explicit keys below into existing `public.module_permission_grants` using module `conference`, resource type `conference`, resource ID `conference_id::text`. No Organization ID or Organization role enters the new grant identity or permission predicate. Unknown/null roles have no mapping. Revoked or otherwise invalid legacy authority must not be promoted merely because a historical membership row remains; current account/device eligibility remains a separate requirement. U2B migrates no rows.

Future admission needs the existing module-scoped `module.access` prerequisite, which conveys no Conference data authority. Provisioning admission is separate from resource grants and must retain the canonical administrator/audit boundary. Do not infer `module.manage`, Conference creation, Platform account administration, or Organization administration from any Conference role.

### owner

`conference.access.view`, `conference.lifecycle.manage`, `conference.lifecycle.archive`, `conference.lifecycle.delete`, `conference.data.export`, `conference.data.restore`, `conference.members.view`, `conference.members.manage`, `conference.sync.write`, `conference.conflict.resolve`, `conference.people.view`, `conference.people.manage`, `conference.accommodation.view`, `conference.accommodation.manage`, `conference.transport.view`, `conference.transport.manage`, `conference.accounts.view`, `conference.accounts.manage`, `conference.restaurant.view`, `conference.restaurant.manage`, `conference.air_conditioning.view`, `conference.air_conditioning.manage`, `conference.reports.view`, `conference.reports.export`, `conference.cards.view`, `conference.cards.export`, `conference.search.view`, `conference.settings.view`.

### manager

`conference.access.view`, `conference.lifecycle.manage`, `conference.members.view`, `conference.sync.write`, `conference.conflict.resolve`, `conference.people.view`, `conference.people.manage`, `conference.accommodation.view`, `conference.accommodation.manage`, `conference.transport.view`, `conference.transport.manage`, `conference.accounts.view`, `conference.accounts.manage`, `conference.restaurant.view`, `conference.restaurant.manage`, `conference.air_conditioning.view`, `conference.air_conditioning.manage`, `conference.reports.view`, `conference.reports.export`, `conference.cards.view`, `conference.cards.export`, `conference.search.view`, `conference.settings.view`.

### viewer

`conference.access.view`, `conference.members.view`, `conference.people.view`, `conference.accommodation.view`, `conference.transport.view`, `conference.accounts.view`, `conference.restaurant.view`, `conference.air_conditioning.view`, `conference.reports.view`, `conference.cards.view`, `conference.search.view`, `conference.settings.view`.

### accommodation_viewer

`conference.access.view`, `conference.members.view`, `conference.accommodation.view`.

### transport_viewer

`conference.access.view`, `conference.members.view`, `conference.transport.view`.

Owner receives the documented Conference business actions and owner-only member administration, all limited to that Conference. Manager maps the retained operational section capabilities, metadata/completion, synchronization and conflict resolution, but gains no member/grant administration, archive, Conference deletion, full export/restore, creation, or module administration. Viewer receives read capabilities only. Restricted viewers receive access metadata, the existing membership-directory read, and only their respective accommodation or transport business section. The membership-directory read is existing backend authority for all members (`list_conference_members`), not a new cross-section data grant.

The executable mapping test expands each grouped permission into existing `ConferencePermissionContract.roleBundles` actions and verifies equality for the retained Conference scope for every role, explicitly excluding the deferred template-library section. `members.view` additionally comes from the backend directory contract. This is a deterministic mapping of the **documented business contract**, not a claim that every current frontend action is already enforced. `conference-permission-contract.js` explicitly has `enforcementEnabled:false`; its resolver is a shadow gate. Enforced backend access flags in `get_my_conference_access` give member administration only to owner and sync/conflict/lock authority to owner and manager. Tests separately anchor those facts to their source.

The `20260815_6_11_0_launch_membership_integrity.sql` trigger rejects new assignments of `accommodation_viewer` / `transport_viewer`; the later integrity fix retains this restriction. These mappings describe legacy roles if encountered; U2B does not re-enable assigning them. Creation currently also checks `can_user_create_conferences`, approved account, and active Organization membership. The new creation catalog entry has no Organization condition and no automatic role-derived grant; replacing that old runtime prerequisite belongs to U2C.

## Boundaries that must remain explicit before runtime migration

- `conference.access.view` is discovery/access metadata, not permission to download all sections. The existing full-snapshot read is coarse and cannot simply be wired to this key for restricted viewers. Migrate its canonical reader with section-safe data disclosure before restricted grants are enforced; do not add a fallback reader.
- The existing section contract contains unresolved handlers (sharing, branding, archive/backup artifact deletion, and some compound template actions). U2B does not invent new rights for these. Audit their real effects and existing enforcement before U2C activation.
- Application-wide backup/restore and shared template libraries are not owned by one Conference. `data.export` / `data.restore` represent the Conference contribution only; multi-Conference operations must authorize every affected resource, and creation requires separate authority. The draft template keys are removed because current template storage is library-owned, not exact-Conference-owned. Existing library authorization stays until its own consumers are reviewed; importing into a Conference still uses accommodation authority and creating from a template still needs creation authority.
- Synchronization and conflict resolution are existing business capabilities (`canSync`, `canResolveConflicts`), so catalog entries are justified. They do not permit edits outside separately granted sections. Snapshot transport is not exposed as a business permission. Revision checks, approved sessions, conflict intent and operation history remain prerequisites.
- Edit locks are concurrency preconditions, not independently assignable business authority. Existing owner/manager writer checks are unchanged. Future lock acquisition must inherit the authorized write scope; a held lock never supplies a permission. Renewal/release ownership and token/expiry checks stay.
- The current `conferences_delete_owner` direct policy was removed by lifecycle hardening. The proposed delete key captures the documented business capability; it neither restores a direct SQL grant nor creates a new delete RPC. The existing canonical lifecycle path must be migrated and tested before this key is consumed.

## Consumer-based removal manifest

No removal occurs in U2B. MIGRATE means replace authorization inside the canonical consumer in U2C. REMOVE AFTER ZERO CONSUMERS means a later forward cleanup migration/runtime edit in U2D, after repository searches, dependency tests, ACL checks and live rollout evidence show no remaining callers or replay dependencies. Historical files are never rewritten for cleanup. Data retention is separate from removing an authorization dependency.

| Component | Classification | Current consumers/evidence | Migration or removal gate |
| --- | --- | --- | --- |
| Platform modules, catalog, grants, grant operations/audit | KEEP | Reservations, Warehouse, generic administration and module entry gate | Reuse unchanged; no duplicate permission system |
| Approved accounts, Platform identities, device bindings/sessions, WebAuthn, dispatcher admission | KEEP | `require_current_approved_device`, `platform.execute_device_operation`, Edge protected allowlists | Preserve authoritative admission and audit; no Organization substitute |
| `conference_members.role` authorization | MIGRATE | `get_my_conference_access`, `has_conference_role`, snapshot/conflict readers/writers, section lock writer, member admin | Replace each predicate with exact-resource Platform permissions; keep membership data unchanged in U2B |
| `is_conference_member`, `is_conference_owner`, `has_conference_role` authorization helpers | REMOVE AFTER ZERO CONSUMERS | SQL RLS, lifecycle and member functions, lock and snapshot functions | Remove only after all SQL policies/functions, wrappers and replay callers migrate; do not delete identity/provenance fields |
| `js/sync/conference-permission-contract.js` | MIGRATE | `conference-permission-resolver.js`, 73 shadow gates, phase2a/2b/2e tests | Replace runtime role-bundle dependency with canonical capabilities after unresolved actions are audited; retain historical evidence in tests/docs |
| `conference-permission-resolver.js` / activation authorization | MIGRATE | `script.js`, `core.js`, active Conference selection, discovery, protected read/edit/sync | Preserve local provenance rules separately; replace cloud role derivation; no old/new OR fallback |
| `conference-members-service.js` | MIGRATE | `conference-members-ui.js`, discovery/activation; Platform device-operation client | Existing service must consume canonical exact-Conference access/admin operations; no parallel service |
| `conference-members-ui.js` | MIGRATE | Member display, role selector, owner-only controls | Bind to canonical capabilities after backend cutover; no behavior change in U2B |
| `get_my_conference_access`, guarded membership/access reads | MIGRATE | Members service, discovered Conference open, activation/reconciliation | Keep one canonical access result; replace role-derived capabilities, preserve approved-device/session checks |
| `list_conference_members` | MIGRATE | Guarded members service/UI; all members currently can read directory | Exact-Conference `members.view`; no module-wide user listing implied |
| `manage_conference_member` add/change/remove and guarded wrapper | MIGRATE | Members service addMember/changeRole/removeMember; dispatcher | Preserve owner-only authority as resource administration; migrate canonical grant administration with unchanged audit/intent/revocation semantics |
| Legacy add/remove-manager signatures and predecessor wrappers | REMOVE AFTER ZERO CONSUMERS | Service compatibility methods, dispatcher allowlists, stored membership operation replay | Migrate all callers and prove replay history remains readable before revoking/dropping; no blind duplicate deletion |
| Organization-derived Conference authority | MIGRATE | Conference creation, member integrity, discovery, Conference administration UI and Reservations Conference-scoped event access | Move only Conference authority predicates to Platform grants; Organization is not the universal authorization owner |
| Organization business data and independent administration | KEEP | Organization service/UI, names, classification/ownership relationships and shared template libraries | Preserve genuine business functionality; business ownership does not confer Conference authority |
| Organization authorization-only RLS/predicate/trigger branches | REMOVE AFTER ZERO CONSUMERS | Conference membership creation and authority branches in `prevent_invalid_conference_organization_change` | Split business-integrity requirements from authorization; prove zero remaining SQL, RLS, trigger, replay and cross-module consumers before removing only the authority branch |
| Organization authorization-only dispatcher branches | REMOVE AFTER ZERO CONSUMERS | `platform.execute_device_operation`, Conference Phase1C core, guarded Conference creation/linking compatibility routes | Remove only branches used solely to establish Conference authority, after zero remaining callers; KEEP genuine Organization administration, template operations and shared Platform admission |
| Obsolete authorization-only Edge Organization/member compatibility allowlist entries | REMOVE AFTER ZERO CONSUMERS | `supabase/functions/platform-device-operation/index.ts`; client operation contracts | Delete obsolete names only after canonical dispatcher/client migration; no Edge change now |
| Section-lock role checks | MIGRATE | `require_conference_section_lock_writer`, acquire/renew/release, `conference-edit-lock-manager.js` | Replace role admission with canonical authorized write scope; retain token/device/expiry/concurrency checks |
| Snapshot read/write and sync/conflict role checks | MIGRATE | `device_guarded_apply_conference_snapshot`, download/metadata, resolve/get/list conflicts, sync processor and conflict executor | Section-safe reads; canonical data write authorization plus sync/conflict capability; preserve revision, intent and ledger semantics |
| Conference creation/deletion/lifecycle authority | MIGRATE | guarded creation, `can_user_create_conferences`, lifecycle trigger/ACLs, local lifecycle handlers | No existing role automatically gains module-scoped creation; retain lifecycle invariants and exclusive canonical operations |
| Legacy tests asserting role/Organization authority | MIGRATE | conference-members/role-management/activation, section-lock, snapshot/conflict, Organization contract tests | Keep passing during U2B; replace assertions alongside each migrated consumer, retaining negative and replay coverage |
| Applied historical migrations | HISTORICAL ONLY | `20260728_*` through existing Conference/Organization and Platform migrations | Never edit/delete for cleanup; use forward migrations when removal is approved |
| Conference, Organization, membership, snapshot, sync, lock and audit data | KEEP | All active business and history consumers | No U2B mutation/backfill; later retention decisions require their own explicit scope |


## Revision decisions and operation evidence

The original 31-row draft becomes **29 permissions**. Remove `conference.templates.view` and `conference.templates.manage`: `script.js:saveTemplate` writes `appData.templates`, the house-template editors write `appData.houseTemplates`, and `js/conference-template-houses-editor.js` edits library templates. No current exact-Conference-owned template CRUD resource was established. These capabilities remain intact; this catalog does not invent a replacement template subsystem or broad module permission. Review template-library authority separately before cutover. Applying a house template to a Conference is an existing accommodation import; creating a Conference from a template needs the module creation permission.

All other permission keys, scope modes and sensitivity flags are unchanged after consumer review. Air conditioning is retained because current pricing/settings and accounts operations implement it. Search and settings are existing Conference views, not hypothetical domains. People operations use `people.js:getPeopleDb`, which resolves `getCurrentConference().peopleDb`; Conference accounts are financial business data (`js/conference/accounts.js`), never Platform account identities. No Platform Person, peopleDb, room/person, snapshot or template data is altered.

Each anchor below is an existing consumer/operation to protect at later cutover, **not a claim that the new key is consumed at runtime today**. The fixture verifies every anchor exists outside the descriptive role contract.

| Permission | Current operation evidence |
| --- | --- |
| `conference.access.view` | `js/sync/conference-members-service.js` — `'get_my_conference_access'` |
| `conference.lifecycle.create` | `script.js` — `function createConferenceFromSelection(` |
| `conference.lifecycle.manage` | `script.js` — `function completeCurrentConference(` |
| `conference.lifecycle.archive` | `core.js` — `function archiveCurrentConference(` |
| `conference.lifecycle.delete` | `script.js` — `function deleteCurrentConference(` |
| `conference.data.export` | `script.js` — `function exportJsonFile(` |
| `conference.data.restore` | `script.js` — `function executeConfirmedFullRestore(` |
| `conference.members.view` | `js/sync/conference-members-service.js` — `'list_conference_members'` |
| `conference.members.manage` | `js/sync/conference-members-service.js` — `'device_guarded_manage_conference_member'` |
| `conference.sync.write` | `js/sync/sync-processor.js` — `snapshotSync.uploadSnapshot(uploadInput)` |
| `conference.conflict.resolve` | `js/sync/conflict-executor.js` — `'device_guarded_resolve_sync_conflict'` |
| `conference.people.view` | `people.js` — `function getPeopleList(` |
| `conference.people.manage` | `people.js` — `function upsertPerson(` |
| `conference.accommodation.view` | `script.js` — `function renderAccommodation(` |
| `conference.accommodation.manage` | `script.js` — `function saveRoomData(` |
| `conference.transport.view` | `script.js` — `function renderTransports(` |
| `conference.transport.manage` | `script.js` — `function saveTransport(` |
| `conference.accounts.view` | `js/conference/accounts.js` — `function renderAccounts(` |
| `conference.accounts.manage` | `js/conference/accounts.js` — `function saveFinancialItemsSettings(` |
| `conference.restaurant.view` | `script.js` — `function renderRestaurantV3Settings(` |
| `conference.restaurant.manage` | `script.js` — `function setRestaurantV3BasePrice(` |
| `conference.air_conditioning.view` | `script.js` — `function renderAirConditioningV3Settings(` |
| `conference.air_conditioning.manage` | `script.js` — `function updateAirConditioningV3Setting(` |
| `conference.reports.view` | `script.js` — `function renderV3Reports(` |
| `conference.reports.export` | `script.js` — `function exportV3ReportsExcel(` |
| `conference.cards.view` | `script.js` — `function renderCards(` |
| `conference.cards.export` | `script.js` — `function downloadCardPng(` |
| `conference.search.view` | `script.js` — `function renderSearch(` |
| `conference.settings.view` | `script.js` — `function renderSettings(` |

### Exact scope and creation rationale

For 28 resource permissions: `module_key=conference`, `resource_type=conference`, `resource_id=public.conferences.id::text` (canonical UUID serialization). Never use an Organization UUID, local Conference ID, wildcard, or membership ID. Membership is a future migration input only. The existing generic grant schema stores resource IDs as text and its validator checks scope/type/format; it does **not** check Conference existence or parse UUIDs. At cutover, the canonical protected consumer must resolve/validate the UUID and resource existence, as Warehouse's `require_permission` already checks store existence. No new validation/resolution framework is needed.

`conference.lifecycle.create` alone is module-scoped with both resource fields NULL: no Conference UUID exists before creation. Current `can_user_create_conferences` is an account-wide capability, consumed by `create_organization_conference_idempotent`; the latter additionally requires active Organization membership today. That legacy prerequisite is MIGRATE, not part of the new catalog contract. Existing resource roles/grants never imply creation. The approved-device/account boundary, module admission and canonical System Owner handling remain in the shared engine.

No role lookup, Organization join or alternative allow branch is added. The mapping is a candidate bootstrap input subject to eligibility and scope review, never executable runtime authority. Final cutover authority must resolve Platform grants through the canonical engine (including its existing System Owner behavior). No membership or grant backfill occurs here.

### Reservations Organization dependency — later cutover, unchanged now

Reservations and Conference reuse the same module registration, business catalog, grant storage, validation and effective-permission engine. Business vocabularies and resource types differ: `warehouse.*` uses store resources and module-wide operations; `reservations.*` uses event resources and module-wide operations; Conference uses the exact Conference resource above. No catalog row in either peer module is changed.

The remaining dependency is explicit: valid Reservations Platform permission can still be denied for a Conference-scoped Event without active Organization membership. Standalone Event access does not use this branch. Inventory for later MIGRATE:

- `reservations_private.conference_context` in `20260915190000_reservations_organization_booking_access_reconciliation.sql`: canonical permission followed by active Organization/membership and nondeleted Conference checks.
- `reservations_private.resolve_event_scope` originated in `20260915220000_reservations_authorization_architecture_reconciliation.sql`: event permission followed by Conference Organization membership. This definition is superseded by the report-scope correction below; it is not a second active resolver.
- `reservations_private.resolve_event_scope` in `20260920120000_reservations_report_event_authorization_scope.sql`: Conference-linked report/event scope still checks Organization membership.
- `reservations_private.booking_creation_context` in `20260922113000_reservations_standalone_zero_state_authorization_reconciliation.sql`: latest booking discovery keeps that condition for Conference scope.
- `reservations_private.effective_capabilities` in `20260922113000_reservations_effective_capability_contract.sql`: Conference capability discovery retains the same membership boundary.

These migration files identify current function definitions/lineage; applied files are HISTORICAL ONLY and must never be rewritten. Future forward migrations must replace authorization-only conditions after consumer and tenant-isolation tests, while preserving genuine Conference/Event/Organization business relationships. No Reservations correction is part of U2B.

### Additional authoritative removal gates

| Component | Classification | Evidence / zero-consumer gate |
| --- | --- | --- |
| Current Warehouse `warehouse.*` catalog, store operations and protected boundary | KEEP | `20260829140000_warehouse_module_permission_catalog.sql`, `warehouse_private.require_permission`; no stores/items/receive/issue/transfer/adjust/approve/post/report/frontend change |
| Current Reservations `reservations.*` catalog and protected boundary | KEEP | `require_effective_module_permission`, event grants; keep current behavior while recording the Organization dependency above |
| Retired `inventory.*` authority and obsolete compatibility helpers | REMOVE AFTER ZERO CONSUMERS | `20260907130000_inventory_authority_retirement.sql` and session-only reconciliation already retire legacy authority; do not revive it. Remove any surviving authority-only helper only after repository and DB dependency/ACL/replay audits prove zero remaining callers; retain required history |
| Retired-path allowlist entries | REMOVE AFTER ZERO CONSUMERS | Edge protected-operation allowlists, dispatcher cases and client contracts; prove no active client, historical operation replay, or SQL caller requires each exact signature; retain live Organization business routes |
| Template-library authorization consumers | MIGRATE | `saveTemplate`, `saveHouseTemplate`, `saveTemplateFloor`, template-house editor and Organization sharing; scope review is required before mapping library actions, with no invented exact-Conference template authority |
| Conference creation capability administration | MIGRATE | `can_user_create_conferences`, `set_user_conference_creation_permission`, `device_guarded_manage_system_user`, account/user-management flows; replace Conference creation authority with canonical grants without replacing Platform accounts |
| Person Bank P2A and shared people data | KEEP | Separate shared-data concern; no FK, Conference Person migration, Reservations adoption or `conference_person_links` edit |
| All already-applied permission, security, Organization and inventory migrations | HISTORICAL ONLY | Evidence/lineage only; later cleanup must be forward-only, never edit applied history |

Canonical grant administration remains `manage_catalog_module_grant` / `manage_foundation_module_grant` with `module_grant_operations` and `module_grant_audit_log`; protected operations continue through `platform.execute_device_operation`. These existing primitives are sufficient. New DB authorization framework objects: **ZERO**.

## Validation interpretation

The isolated PostgreSQL regression loads repository catalog/grant DDL, canonical device FK alteration, and real `validate_module_permission_catalog`, `require_module_permission`, and `require_effective_module_permission` bodies. Only outer account/device identity admission is a fixture stub; this test does not claim full session/WebAuthn execution. It verifies exact-resource grants in the existing table, module admission, wrong-resource/device denial, revoked grants, role negative cases, catalog replay/conflict behavior, unchanged registration/grants/other catalogs and unchanged resolver definitions. Separate established Platform/security regressions cover the unchanged transport boundary.

No runtime file imports the mapping artifact. No grant rows are seeded by the migration. No frontend files, Edge files, Reservations or Warehouse runtime files are changed. No migration is applied to Development or Production by this round.


## Revision validation record (2026-09-28)

| Validation | Result |
| --- | --- |
| Focused U2B (`node --test tests/unified-conference-permission-foundation.test.js`) | 12 passed, zero failures/skips; includes isolated local PostgreSQL |
| Selected Platform authorization/security contracts | 400 passed across 56 files, zero failures/skips |
| Warehouse authorization and System Owner approval contracts | 14 passed across 2 files, zero failures/skips |
| Reservations authorization/scope/permission/tenant/dispatch contracts | 70 passed across 15 files, zero failures/skips |
| Conference backend/security and shadow permission contracts | 27 passed across 19 files, zero failures/skips |
| Syntax | `node --check` for the revised test; JSON parse; SQL compiled/executed in disposable local PostgreSQL |
| Undefined references and duplicate functions | ESLint `no-undef`, `no-redeclare`, `no-dupe-args`, `no-dupe-keys`; named helper scan; zero new SQL function definitions |
| Dependencies | All 29 operation anchors and SQL prerequisite function definitions verified; no runtime fixture imports; only one Conference catalog foundation migration |
| Migration behavior | 29 exact catalog definitions (including labels/descriptions); replay idempotence; conflict rollback; resource and creation scopes; module admission; wrong-resource/device and revoked-grant denial; module.manage does not imply business authority |
| Peer parity | Isolated test loads Warehouse catalog and Reservations catalog DML through its event-scope revision and verifies both unchanged by U2B |
| Change isolation | SHA-256 baseline of 754 repository files: only these four U2B files changed; 750 unrelated files unchanged; no unrelated pending/untracked files existed at baseline |

The Platform selection includes authorization, account, device/session, grant administration, WebAuthn, owner, inventory-retirement, creation-authority, private-recovery RLS and Phase1C dispatch contracts. UI/browser suites were excluded. The isolated U2B fixture explicitly targets the local `/tmp` PostgreSQL socket on port 5432, strips ambient PostgreSQL connection settings, creates a uniquely named disposable database and drops it in `finally`. Identity/device admission remains a test stub, not a new production model; established security contracts separately cover the unchanged boundary.

Exact revised files:

- `supabase/migrations/20260927180000_conference_platform_permission_foundation.sql`
- `docs/unified-conference-permission-foundation-u2b.md`
- `tests/unified-conference-permission-foundation.test.js`
- `tests/fixtures/unified-conference-permission-foundation.json`

Conference runtime authorization changed: NO. Warehouse runtime changed: NO. Reservations runtime changed: NO. Person Bank changed: NO. No frontend, Arabic text or public global function changed. No memberships or grants migrated. Development DB, Production DB, Edge and main untouched. Work remains on develop, uncommitted and unpushed. STOP FOR REVIEW.
