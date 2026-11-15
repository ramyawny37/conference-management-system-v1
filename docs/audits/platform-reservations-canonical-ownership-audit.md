# Platform and Reservations canonical ownership audit

Audit date: 2026-11-16 (Africa/Cairo)  
Platform baseline: `14102f906a3646487903c8d2459788b56f209497`  
Approved pre-integration tree: `2623b528d1d0a4910bd954822c05933639368a93`  
Reservations candidate source: `c56a8fdd2ccde4405a3c73f3580b27b08b1cf5c9` (not approved for integration)

## Scope and safety result

This round audited the active Development code paths and implemented only the fail-closed artifact-policy correction. It did not change the active Reservations bundle, the approved UI, application business behavior, Supabase data, `main`, or Production. No runtime file was deleted because no candidate reached the `PROVEN-DEAD` threshold with complete consumer and visual evidence.

The Platform tree at `14102f9` is identical to the approved pre-integration tree. The active Reservations runtime fingerprints are:

- `modules/reservations/reservations-module.js`: `a4dcee66e7fe4d3d76ec686537c901ca844b0416318b26186ad02b74df6f7739`
- `modules/reservations/reservations-module.css`: `a191be2233f3fe4cad475d261c5dc4216b17ac4f451a79b50c04ffb31d7fdbbb`
- cache revision: `reservations-lifecycle-active-only-v4`

## Canonical dependency graph

```text
Reservations TypeScript/React source repository
  src/platform-module.tsx
    -> Vite IIFE + one CSS asset
    -> candidate CI artifact
    -> Platform artifact policy and acceptance gates
    -> tools/integrate-reservations-artifact.cjs
    -> modules/reservations/{reservations-module.js,reservations-module.css}

Platform browser shell
  index.html + shared-design-tokens.css + canonical-platform-shell.css
    -> js/platform-integration.js
    -> PlatformDeviceSession.invokeModuleProtected(module, operation, args)
    -> platform-device-operation Edge Function
    -> module dispatcher / private database contracts
    -> canonical mutation result
    -> module cache invalidation / immediate readback / render
```

The module entry contract is owned by the Reservations source at `/Users/apple/Desktop/reservation-management-system/src/platform-module.tsx:1-78`. It requires Platform services, mounts into a Platform-owned container, and registers exactly one `reservations` module. The build is owned by `vite.platform-module.config.ts:11-29`, producing one IIFE and one CSS asset. The Platform loads those generated files at `index.html:15` and `index.html:614`.

## Ownership inventory

| Area | Canonical owner | Active entry/evidence | Status |
|---|---|---|---|
| Global tokens, colors, typography, control primitives | Platform | `shared-design-tokens.css:1-154` | ACTIVE |
| Header, sidebar, workspace geometry, responsive shell | Platform | `index.html:29-89`, `canonical-platform-shell.css:1-47` | ACTIVE |
| Route ownership and module workspace selection | Platform | `js/application-routing.js`; Reservations links at `index.html:57-71` | ACTIVE |
| Module registration, selected Conference, protected service bridge, cache invalidation | Platform | `js/platform-integration.js:1-16`, protected calls beginning at `:36` | ACTIVE |
| Auth session | Platform/Supabase adapter | `js/supabase/auth.js:97-288` | ACTIVE |
| Device-bound protected invocation | Platform | `js/supabase/device-session.js:34-36` | ACTIVE |
| Startup account/device gate | Platform | `js/sync/startup-access-gate.js:3-100` | ACTIVE |
| User, role, module permission administration | Platform | `js/sync/platform-administration-ui.js`, `module-permission-administration-service.js:11-28` | ACTIVE |
| Reservations page layouts and components | Reservations source | `src/features/reservations/components/**` | ACTIVE SOURCE |
| Reservations browser JS/CSS in Platform | Generated artifact | `modules/reservations/**` | GENERATED, ACTIVE RUNTIME |
| Reservations reads/writes | Reservations source delegates to Platform | `src/features/reservations/backend.ts:199-216`, `:249-798` | ACTIVE SOURCE |
| Reservations database authority and permissions | Platform database/Edge contracts | `supabase/migrations/**`, `supabase/functions/platform-device-operation/index.ts` | ACTIVE |
| Conference core and participation hydration/mutation | Platform | `js/platform-integration.js:36-79` | ACTIVE |
| Accommodation, child/guardian and room operations | Platform | `js/platform-integration.js:93-95`, `houses.js`, `people.js` | ACTIVE |
| Conference transport | Platform | `js/supabase/canonical-conference-transport.js:13-30`, `transport.js` | ACTIVE |
| Conference cards | Platform | `cards.js` loaded by `index.html` | ACTIVE |
| Conference accounts/reports | Platform | `js/conference/accounts.js`, root runtime/report consumers | ACTIVE |
| Warehouse UI and operations | Platform | `js/warehouse/**`, protected contract loaded at `index.html:602-604` | ACTIVE |
| Service Worker and cache ownership | Platform | `service-worker.js:8-45` | ACTIVE |
| Migration archive | Historical evidence only unless a named test/tool reads it | `supabase/migration-archive/**` | COMPATIBILITY-IN-USE or UNKNOWN; not deleted |
| Release/ZIP/archive copies | Outside active runtime | excluded by repository rules | ARCHIVED; not evaluated as runtime |

Repository counts at the baseline: 12 root JavaScript files, 57 files under `js/`, 4 CSS files, 318 test files, 319 active migration files, 351 archived migration files, 12 Edge Function files, and 79 tool files. Counts are inventory facts, not proof that a file is dead.

## Read and mutation paths

### Reservations

`src/lib/platform/runtime.ts:11-59` exposes the only source-side call boundary, `invokeProtected`. `src/features/reservations/backend.ts:199-216` owns read and idempotent mutation dispatch. The same backend owns events (`:289-457`), bookings and participants (`:457-655`), settlement/cancellation/delete (`:655-703`), payments (`:704-730`), attendance (`:731-749`), operational review (`:750-797`), and reports (`:534-633`). The browser does not own database credentials or direct table writes.

### Conference and accommodation

Platform state is hydrated and mutated through `js/platform-integration.js`; core mutations are at `:36-37`, participation and canonical-person operations at `:51-79`, and accommodation hydration/mutation at `:93-95`. These calls delegate through the same protected module dispatcher. Root files such as `houses.js`, `people.js`, `transport.js`, and `cards.js` remain active presentation/interaction consumers loaded by `index.html`; their apparent overlap with canonical services is `COMPATIBILITY-IN-USE`, not proven duplication.

### Auth, devices and administration

`js/supabase/auth.js` owns Supabase authentication state. `js/supabase/device-session.js:34` sends module, operation and args to the Platform Edge Function with the bound device session. `js/sync/startup-access-gate.js:37-100` serializes authentication, account status and device approval before showing the app. Administration services call the `platform` module dispatcher and reject browser device overrides (`module-permission-administration-service.js:11`).

### Warehouse

The Platform owns warehouse presentation and state under `js/warehouse/**`, with one protected device operation contract loaded before the warehouse transport (`index.html:602-604`). No Reservations source file owns warehouse persistence.

## Design ownership and parity evidence

The canonical shell is Platform-owned. Reservations source maps its semantic variables back to Platform variables (`src/app/globals.css:4`, `:10`, `:51`, `:59`) and keeps module-local geometry at `:76-85` and later module scopes. That is the intended boundary: shared semantics from Platform; specialized page layout from Reservations.

The current candidate is not byte- or structure-equivalent to the approved runtime:

| Metric | Approved runtime | `c56a8fdd` candidate |
|---|---:|---:|
| JS bytes | 644,638 | 611,405 |
| CSS bytes | 77,116 | 76,346 |
| CSS media queries | 28 | 27 |
| CSS custom-property declarations | 152 | 152 |
| JS SHA-256 | `a4dcee…` | `4be3dc…` |
| CSS SHA-256 | `a191be…` | `729255…` |

These differences do not alone prove a bug, but they disprove deterministic parity and agree with the recorded visual regression. Therefore `c56a8fdd` is classified `REJECTED`, not merely unreviewed.

## Duplicate, legacy and dead-code findings

1. **Confirmed hazardous duplicate authority — fixed:** the active runtime was the approved bundle, while `tools/integrate-reservations-artifact.cjs` hard-coded the reverted bundle as the only accepted artifact. The tool could overwrite the approved runtime and cache references. Ownership is now moved to `tools/reservations-artifact-policy.json`; the reverted fingerprints are explicitly rejected and the approval list is empty until evidence exists.
2. **Generated files — retained:** `modules/reservations/*.js|css` are generated but active. They must never be edited manually and cannot be deleted.
3. **Reservations source design layer — retained:** `src/app/globals.css` contains module primitives and Tailwind theme mappings. Some selectors may overlap Platform primitives, but removing them before screenshot/DOM parity would risk the approved layout. Classification: `UNKNOWN` at selector level.
4. **Root Conference files plus canonical services — retained:** the root UI files and `js/supabase/canonical-*` services have different presentation/service roles and active consumers. Classification: `COMPATIBILITY-IN-USE` until a consumer graph and live flow prove otherwise.
5. **Migration archive — retained:** tests and release evidence may read historical SQL. A directory name containing `archive` is not sufficient proof of deadness.
6. **Old tests coupled to generated symbol names:** several tests inspect minified bundle internals. They are useful regression evidence for the approved baseline but should be migrated to stable contracts when a source-compatible artifact is prepared. They are not runtime code and were not deleted.

## Implemented in this round

- Added a single artifact policy containing the approved runtime baseline, rejected artifact fingerprints, and an empty explicit approval list.
- Changed the existing integration utility; no parallel integrator was created.
- Added fail-closed checks for rejected artifacts, unapproved artifacts, malformed approval entries, current-runtime drift, branch and clean-tree state.
- Added policy tests and wired them into both Platform workflows.
- Kept all active JS, CSS, database, and UI behavior unchanged.

## Blocked or not proven

- Reservations source verification at `c56a8fdd` passed type checking, all 301 source tests, and the Platform-module build. The build deterministically reproduced the rejected `4be3dc…`/`729255…` fingerprints, so test success does not satisfy the visual-parity gate.
- The Platform Development Preview suite passed all 647 tests. The broad `npm run check` command passed 652 of 657 tests; its five failures are confined to `platform-promotion-readiness.test.js`, which targets Production promotion and expects migration files absent from the approved `14102f9` baseline. The Development CI intentionally excludes that file. Production remediation is outside this task and was not attempted.
- Platform production-dependency audit reports zero vulnerabilities. Reservations source production-dependency audit reports one critical and three high advisories (`next`, `sharp`, `source-map-js`, and `zod`). Fixes require source dependency changes and candidate requalification; no forced dependency update was made in this guard-only change.
- Development database live contract verification is blocked unless a read-only Development connection or authenticated Supabase tooling is available. Local PostgreSQL contract tests do not prove hosted Development state.
- Interactive login/device/payment/refund/accommodation workflows require approved test identities and devices; static and local contract tests cannot replace them.
- Screenshot comparison at desktop/tablet/mobile is blocked by the repository rule that forbids browser or automated UI tests and by the absence of a committed screenshot baseline in the audited tree.
- No selector, component, writer, migration, or root runtime file is currently `PROVEN-DEAD`; therefore this round deletes none.
