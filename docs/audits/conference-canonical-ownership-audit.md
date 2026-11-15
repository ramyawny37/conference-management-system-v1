# Conference canonical ownership audit

Audit baseline and current `develop`: `83237d82058a255efe1c8662dffe40ac03573868`  
Audit date: 2026-11-16 (Africa/Cairo)  
Related specifications: GitHub issues #28 and #29

## Safety result

The approved runtime, Arabic text, public globals, design, database, and business rules were not changed. No file or function was deleted. The audit found no candidate that could be classified `PROVEN-DEAD` without browser instrumentation and a live Development identity. Large root files are active because `index.html:637-655` loads them directly and inline handlers call their public globals dynamically.

The only implemented change in this group is an executable ownership contract. It proves the active load graph is singular, rejects direct table mutation writers in active browser domains, requires protected canonical dispatch/readback, and keeps the rejected Reservations artifact policy in force.

## Runtime and design graph

```text
index.html
  -> shared-design-tokens.css                 shared semantic tokens
  -> style.css                                Conference/Warehouse specialized layouts
  -> canonical-platform-shell.css             Platform shell/header/sidebar
  -> js/supabase/device-session.js             authenticated device envelope
  -> js/platform-integration.js                canonical state + protected facade
  -> canonical domain adapters                 transport/restaurant/templates
  -> generated Reservations artifact           Platform module consumer
  -> presentation files                        people/houses/transport/cards/accounts/script
  -> platform-device-operation Edge Function   module/operation allowlist
  -> platform.execute_device_operation          one protected database dispatcher
  -> canonical RPC transaction                  authoritative mutation/audit/revision
  -> integration state replacement/readback
  -> presentation render
```

Load evidence: design styles are loaded once at `index.html:13-16`; device and operation contracts at `index.html:599-607`; canonical adapters at `index.html:609-613`; presentation files at `index.html:637-655`.

## Responsibility and data-path inventory

| Feature | Presentation / state consumer | Authoritative read | Authoritative write/delete | Refresh / isolation | Classification |
|---|---|---|---|---|---|
| Platform shell, navigation, module visibility | `index.html:29-89`; `js/application-routing.js`; `js/platform-integration.js:168-182` | registered module state | `openModule` / route reconciliation | selected Conference event at `platform-integration.js:169` | ACTIVE |
| Design tokens and shared controls | `shared-design-tokens.css:1-154` | CSS variables | Platform stylesheet only | shell loaded after module CSS intentionally | ACTIVE |
| Authentication | `js/supabase/auth.js:97-303` | Supabase Auth session | Supabase Auth methods | session reset event | ACTIVE |
| Device authority | `js/supabase/device-session.js:34-72` | device binding/session | protected Edge invocation | session/token envelope per request | ACTIVE |
| Users, roles, module grants | `js/sync/platform-administration-ui.js`; permission UIs | protected Platform operations | administration services via dispatcher | render from returned state | ACTIVE |
| Conference core | `script.js:318-369` | `hydrateConferenceCore`, `platform-integration.js:36` | `mutateConferenceCore`, `:37` | local/remote IDs checked; mutation result replaces state | ACTIVE |
| People and participation | `people.js`; participant consumers in `script.js` | `hydrateConferenceParticipations`, `platform-integration.js:51` | participation/person methods `:53-79` | per-local-id generation rejects stale hydration | ACTIVE |
| Accommodation hierarchy | `houses.js`; `script.js:3692-3806` | `hydrateConferenceAccommodation`, `platform-integration.js:93` | structure/pricing operations `:96-103` | mutation rehydrates authoritative accommodation | ACTIVE |
| Guardian/child and family room draft | room editor in `script.js:3345-3602` | participation + accommodation projections | `saveConferenceFamilyAccommodationDraft`, `platform-integration.js:106` | one transaction; both projections rehydrated | ACTIVE |
| Extra beds | accommodation room draft and accounts UI | canonical room projection | family draft / accommodation operation | room leases and expected revisions | ACTIVE |
| Room locks | UI diagnostics in `js/sync/conference-locks.js` | resource lease operations `platform-integration.js:44-47` | acquire/renew/release protected operations | conference + room + scope key | ACTIVE |
| Transport | `transport.js`; render/save consumers `script.js:5615-6266` | `CanonicalConferenceTransport.hydrate`, adapter `:13-60` | `mutateVehicle`, `setAssignment`, `removeAssignment` | mutation calls `hydrate(localId)` | ACTIVE |
| Cards | `cards.js`, loaded `index.html:646` | canonical person/participation projections | no independent database writer | Conference-scoped selected records | ACTIVE |
| Accounts, accommodation prices, meals, A/C | `js/conference/accounts.js:3960-5262` | canonical finance/A-C/restaurant projections | protected canonical facades | renders after mutation promise | ACTIVE |
| Reports | `js/conference/accounts.js:3152` and report renderers | Conference-scoped canonical projections | export only; no second operational writer | current Conference context | ACTIVE |
| Reservations bridge | generated `modules/reservations/**`; loaded `index.html:614` | Platform module services | protected `reservations` operations | event/conference identifiers owned by contract | GENERATED / ACTIVE |
| Warehouse | `js/warehouse/workspace.js:60` and sibling UI files | warehouse transport | protected warehouse contract | current-store context | ACTIVE |
| Local persistence/backups/templates | `js/storage/**`, `houseTemplates.js`, root `save()` consumers | namespaced IndexedDB/local repository | local-only compatibility writes | environment namespace | COMPATIBILITY-IN-USE |
| Service Worker | `service-worker.js:8-45` | versioned asset list | cache replacement | deterministic revisions | ACTIVE |
| Edge dispatcher | `supabase/functions/platform-device-operation/index.ts:32-71` | authenticated account/device session | `platform.execute_device_operation` | module/operation allowlist + audit context | ACTIVE AUTHORITATIVE BOUNDARY |
| SQL/RPC history | `supabase/migrations/**` | canonical projections/functions | transactional functions | expected revisions/idempotency/audit | ACTIVE or historical dependency |

## Proven findings

### 1. Presentation/service overlap is intentional

`people.js`, `houses.js`, `transport.js`, `cards.js`, `script.js`, and `accounts.js` present and coordinate UI. `js/platform-integration.js` and canonical adapters own remote state and protected writes. Both layers are loaded and have different responsibilities; this is not duplicate ownership.

### 2. Local and linked Conference paths coexist

Several presentation actions select a canonical branch when a Conference is linked and retain `save()` for local/unlinked data. Examples include Conference core around `script.js:318-369`, accommodation/account settings around `js/conference/accounts.js:4015-4717`, and finance around `:5109-5177`. These paths look parallel but are `COMPATIBILITY-IN-USE`: removing the local branch would change existing offline/unlinked behavior. A future removal requires an explicit product decision plus migration evidence.

### 3. Canonical writers converge at one boundary

The browser scan found no `.from(...).insert/update/delete/upsert` writer in the active Conference, Warehouse, Reservations bridge, or Platform integration files. Canonical writes use `PlatformDeviceSession.invokeModuleProtected`; the Platform Edge Function validates module/operation and calls one protected database dispatcher at `supabase/functions/platform-device-operation/index.ts:58-71`.

### 4. Hydration and immediate update safeguards exist

- Participation hydration is keyed by local Conference and generation at `js/platform-integration.js:51-53`.
- Accommodation mutation refreshes canonical accommodation at `:103`; family drafts refresh accommodation and participation together at `:106`.
- Transport mutation rehydrates its Conference state in `js/supabase/canonical-conference-transport.js`.
- Core/finance mutations apply returned authoritative projections before rendering.

Static evidence proves the intended path, but interactive no-refresh behavior remains `BLOCKED` without an approved browser run and Development identity.

### 5. CSS ownership is mixed but active

Platform semantics live in `shared-design-tokens.css`; the shell lives in `canonical-platform-shell.css`; specialized Conference and Warehouse layouts live in `style.css`. Some later scoped rules refine earlier rules, including accommodation and organization sections. They cannot be labeled dead solely by cascade position. Selector-level removal needs DOM coverage and screenshot parity, which are unavailable under the no-browser rule.

## Deletion assessment

| Candidate | Status | Evidence / decision |
|---|---|---|
| Root presentation files | ACTIVE | directly loaded at `index.html:637-655`; inline/global callsites |
| Local `save()` branches | COMPATIBILITY-IN-USE | preserve local/unlinked/offline Conference behavior |
| Canonical service adapters | ACTIVE | remote protected state/write owners |
| Reservations generated files | GENERATED / ACTIVE | loaded by HTML and Service Worker; policy-controlled |
| Migration archive | UNKNOWN / historical consumers | tests and release tooling may address historical SQL |
| Scoped later CSS rules | UNKNOWN | cascade and responsive DOM evidence required |

No deletion is authorized by this evidence set.

## Verification limits

- No browser or automated UI test was run because repository instructions prohibit it.
- No hosted Development database mutation was performed. A live contract audit requires read-only Development credentials; operational flows require approved test identities/devices.
- Static tests cannot certify pixel parity or every dynamic inline-handler path. Those gates remain `BLOCKED`, never `PASS`.
