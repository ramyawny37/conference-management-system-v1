# Public Registration — canonical contract and implementation handoff

Status: IMPLEMENTATION HANDOFF — PR0–PR5 are implemented on `develop` / Supabase Development; Production remains untouched.
Repository: `ramyawny37/conference-management-system-v1`
Branch: `develop` only.
Contract baseline: `5204d14054f1646c2a6b6e0794d321dd738a6918`

## 1. Purpose

Public Registration lets an organizer publish a public registration entry point for one Conference/Reservations event, receive a person's submitted details as a reviewable request, and approve, reject, or waitlist that request. Approval must enter the existing canonical Reservations booking path; Public Registration is an intake layer, never a second booking system.

The first consumer is Conference/Reservations. The design must remain portable enough that a future stable-product rewrite can expose the same business contract through ASP.NET Core + Angular/PWA, but no C#/.NET or Angular migration is part of the current implementation.

## 2. Non-negotiable boundaries

- Work on `develop` and Supabase Development only. Never modify `main`, Production, or Production data.
- One canonical path. No legacy fallback, parallel booking writer, second Person store, second permission engine, or second operation ledger.
- Every event remains independently scoped. A public link for event A must never expose or mutate event B.
- `platform.people` remains the permanent Person directory.
- `reservations_private.mutate_scoped` remains the canonical Reservations mutation/writer boundary unless a later contract change proves and replaces it atomically.
- Operational booking price continues to resolve from the current event booking type contract; Public Registration must not introduce an independent price authority.
- Public submission is not a confirmed booking when approval mode is active.
- Public clients never receive direct table write privileges and never call privileged internal helpers directly.
- Public identity matching never auto-merges people based on name or phone.
- Notification delivery failure must not roll back or duplicate a successfully approved booking.
- Existing apology, cancellation, refund, credit, payment, attendance, accommodation, transport, Cards/print/PNG/WhatsApp and reporting ownership remains unchanged unless explicitly included in a later implementation phase.
- Follow `AGENTS.md`: no browser/automated UI tests, no redesign, no unrelated Arabic copy changes, no public-global rename, no ES-module conversion.

## 3. Existing contracts that this feature must reuse

### Conference root
`public.conferences` is the sole Conference root. Public Registration must not create a second event/conference root. Canonical Conference creation and mutation already use the protected Platform dispatcher, revision checks, idempotency/audit conventions, and exact permission boundaries.

### Person identity
`platform.people` is the canonical permanent Person store. Name and phone are search/candidate signals, not unique identity keys. Duplicate names and shared phone numbers are valid.

Reservations already has explicit manual identity resolution for booking creation:
- candidate discovery by normalized exact name/phone;
- no automatic merge;
- an explicit decision between an existing candidate and a different/new Person;
- stale challenge protection;
- identity-key advisory locking around creation.

Public Registration must preserve that meaning. A public submitter may provide identity data, but only the protected approval flow may bind/create the canonical Person. Public submission itself must not silently mutate an existing Person.

### Reservations booking
The protected device operation currently exposes `create_booking`, and the current database contract identifies `reservations_private.mutate_scoped` as the sole booking writer. Approval must reuse this canonical behavior rather than insert directly into `reservations.bookings`.

`reservations.bookings_operational` resolves operational price from the event-owned active booking type. A request may display/store the submitted selection for review/audit, but approval must validate the current canonical booking type/eligibility/price state. A stale or invalid selection must require operator resolution rather than creating a booking with a private public-form price.

## 4. User journeys

### Organizer
1. Create/select an event through the existing canonical administration flow.
2. Enable Public Registration for that event.
3. Configure registration mode and window.
4. Copy/share the public URL or QR representation.
5. See pending requests inside Reservations for that event.
6. Open a request and review submitted data, current booking type/period eligibility, duplicate-booking state, and Person identity candidates.
7. Approve, reject, or waitlist.
8. Approval executes the canonical booking flow and returns the resulting booking identity.
9. Notification delivery is queued/attempted after the durable decision and is independently retryable.

### Public registrant
1. Open the public event URL without an administrator login.
2. See only public event information and currently selectable registration options.
3. Enter required personal/contact data and select an eligible booking option.
4. Review the submission before sending.
5. Submit once and receive a non-secret human reference plus a secret tracking capability/link.
6. Track status without seeing internal administration data.
7. Receive status notification when the request is approved/rejected/waitlisted if a configured delivery channel is available.
8. On approval, the status page may show the allowed booking confirmation summary, never internal audit/security metadata.

## 5. Registration modes

The model must support these values without creating separate booking paths:

- `approval_required` — initial/default mode. Submission becomes pending; an authorized operator must decide.
- `auto_approve` — reserved for a later phase. It may be enabled only after the same identity, duplicate, eligibility, capacity and canonical booking invariants can be enforced safely without an operator decision.
- `waitlist_when_full` — capacity policy, not a second registration system. When the canonical capacity rule says no place is available, the request may enter waitlist instead of becoming a booking.

Phase 1 must implement `approval_required` first. Other modes remain contract-compatible but must not be exposed as working UI until implemented and tested.

## 6. State machine

Canonical request states:

`submitted -> under_review -> approved`
`submitted -> under_review -> rejected`
`submitted -> under_review -> waitlisted`
`waitlisted -> under_review -> approved|rejected`

Rules:
- `approved` is terminal for the request and references exactly one canonical booking.
- Subsequent booking apology/cancellation is owned by Reservations; it does not rewrite the historical request decision.
- Repeated approve with the same operation identity must replay the same result and never create a second booking.
- A rejected request is not a deleted audit record.
- Editing/resubmission policy is a later explicit decision; do not silently reopen terminal requests.

## 7. Proposed storage responsibilities

Exact SQL names are finalized only during the schema phase after migration-history review. The conceptual ownership is:

### Public registration channel/configuration
One configuration per event/public channel, containing:
- event identity;
- public slug/opaque public identifier;
- enabled/open state;
- registration mode;
- optional open/close timestamps;
- optional capacity/waitlist policy;
- revision;
- trusted creator/updater and timestamps.

### Registration submission/request
Immutable submission identity plus controlled status fields:
- request UUID;
- event/channel identity;
- public reference number;
- submitted person/contact snapshot;
- requested booking type/attendance selection identifiers;
- submitted-at timestamp;
- current request state and revision;
- resolved canonical Person ID only after protected resolution;
- resulting canonical booking ID only after successful approval;
- decision actor/device/time and optional rejection reason where policy allows.

Do not use free-form JSON as the sole authority for fields that drive booking, identity, status, scope, revision, or approval. JSON may be used only for versioned non-authoritative presentation/audit snapshots when justified.

### Tracking capability
Tracking access must use a high-entropy opaque secret. Store a one-way digest where practical; never expose sequential database IDs as authentication. Rotation/revocation/expiry policy must be explicit before implementation.

### Notification delivery
Notification attempts are downstream records/events of a durable decision. They require idempotency and retry state. They must not own booking truth.

## 8. Public security contract

The existing `platform-device-operation` route is administrator/device protected and has a fixed GitHub Pages origin. Do not weaken it or add anonymous bypasses for Public Registration.

Public Registration requires a separate narrow public boundary with:
- exact operation allowlist;
- event/channel scope derived server-side from the public identifier;
- strict payload schema and length limits;
- server-side registration-window/enabled checks;
- rate limiting/abuse controls before broad release; PR2 applies a DB-backed per-channel/per-fingerprint minute bucket (submit 8/minute, read/status 60/minute);
- no service-role credential in the browser;
- no direct client table mutation;
- no ability to select actor/device/permission identities;
- safe error codes that do not leak Person candidates, private phone data, internal IDs, grants, audit rows, or database details;
- idempotent submission token/operation identity;
- tracking secret separated from public event URL.

Administrative approve/reject/waitlist remains behind the existing authenticated approved-device/permission boundary.

## 9. Identity resolution contract

Public submission captures proposed profile data only.

At review:
1. Server obtains canonical identity candidates using the existing Reservations/Person semantics.
2. If no candidate exists, the protected booking flow may create the canonical Person under its existing rules.
3. If candidates exist, operator must explicitly choose existing vs different/new.
4. If an existing Person is selected and submitted data differs, Public Registration must not silently overwrite canonical Person data. Reuse the existing explicit central-update vs booking-only policy or define its exact equivalent before implementation.
5. Duplicate booking for the same event must be rejected by the canonical booking invariant, not merely hidden in UI.
6. Public users must never receive the internal candidate list.

OTP/pre-fill is intentionally deferred. If later added, verified possession of a phone may authorize limited pre-fill for that registrant but still does not make phone a globally unique Person key.

## 10. Booking approval transaction

Approval is an authenticated administrative operation.

Required behavior:
1. Lock/read the request and verify expected revision/state.
2. Verify event/channel scope.
3. Resolve identity decision under existing canonical identity semantics.
4. Revalidate current booking type, attendance eligibility, duplicate state and all canonical booking requirements.
5. Invoke/reuse the canonical Reservations booking writer semantics with a stable operation ID.
6. Persist the request as approved with the resulting booking ID and decision metadata only if the booking succeeds.
7. Produce an auditable result.
8. Commit durable business state.
9. Trigger notification delivery separately.

No direct insert into `reservations.bookings` from the public endpoint. No client-calculated price authority.

The exact database transaction shape must be proven during implementation. If current `create_booking` cannot atomically bind the request decision and booking result, add a protected server-side orchestration operation around the canonical writer semantics; do not fork the writer logic.

## 11. Capacity and waitlist

Capacity already has a canonical event-level source: `reservations.events.capacity` (nullable positive integer). Public Registration must reuse that field and must not infer capacity from room beds, accommodation counts, request counts, or a second capacity column.

When capacity is implemented:
- `reservations.events.capacity` is the authoritative event-level capacity owner;
- approval and auto-approval must recheck it transactionally;
- waitlist promotion must be explicit/idempotent;
- position/order semantics must be defined before exposing a numbered queue.

## 12. Public page and administration UI

### Public
Mobile-first, Arabic-first, compatible with the current PWA/site deployment:
- event summary;
- registration availability;
- personal/contact fields required by the current booking contract;
- active eligible booking types/periods;
- review step;
- submit result/reference;
- tracking status page.

Do not expose administration navigation, internal Person search, audit data, permissions, settlement details, or unrelated events.

### Administration
Integrate into existing Reservations/Event UI rather than a new top-level parallel module:
- Public Registration settings for the event;
- copy-link action;
- pending count;
- request list/filter;
- review drawer/modal/page;
- approve/reject/waitlist actions according to implemented phase;
- notification delivery status/retry only when notification delivery exists.

## 13. Notifications

Phase ordering:
1. Durable request and tracking page work without notification provider dependency.
2. Add provider abstraction/delivery records.
3. Add the selected real channel(s) after credentials, sender identity, consent/template requirements and failure behavior are defined.

A successful approval is never rolled back because SMS/email/WhatsApp/push delivery failed. Retry uses the same notification identity and must not repeat booking approval.

Do not claim WhatsApp/SMS/email support until a provider is actually configured and tested.

## 14. Future portability contract

Current implementation remains in the existing Vanilla JS + Supabase/PostgreSQL architecture.

To keep a future ASP.NET Core + Angular/PWA rewrite practical:
- business states and invariants live in documented server/database contracts, not DOM-only state;
- public UI never depends on database table shape;
- operation payloads/results are explicit and versionable;
- public identifiers/tracking capabilities are transport-neutral;
- notification delivery is downstream from domain decisions;
- canonical Person and Booking identities remain stable domain concepts.

Future target may expose equivalent application operations through ASP.NET Core REST endpoints and Angular routes, but current code must not add speculative .NET/Angular layers or over-generalize into a generic forms platform.

## 15. Decisions

| ID | Decision | Status |
| --- | --- | --- |
| PR-001 | Public Registration is intake before canonical booking, not a second booking system. | ACCEPTED |
| PR-002 | Initial registration mode is approval required. | ACCEPTED |
| PR-003 | Approval must reuse canonical Reservations booking semantics/writer. | ACCEPTED |
| PR-004 | Public submission never auto-merges Person identity. | ACCEPTED |
| PR-005 | Public user needs no administrator/platform account in Phase 1. | ACCEPTED |
| PR-006 | Tracking uses an opaque secret capability, separate from the shareable event URL. | ACCEPTED |
| PR-007 | Notification failure cannot roll back an approved booking. | ACCEPTED |
| PR-008 | Operational price remains owned by current event booking type. | ACCEPTED |
| PR-009 | Waitlist is a request state/policy, not another booking table/path. | ACCEPTED |
| PR-010 | OTP/pre-fill is deferred until its security/identity contract is explicit. | ACCEPTED |
| PR-011 | Future ASP.NET Core + Angular/PWA portability is a design constraint, not a current migration. | ACCEPTED |
| PR-012 | Event-level capacity is owned by existing `reservations.events.capacity`; no second capacity source is allowed. | ACCEPTED |

## 16. Implementation phases and progress

| Phase | Scope | Status | Evidence |
| --- | --- | --- | --- |
| PR0 | Repository audit + canonical contract | IMPLEMENTED | Baseline `5204d14054f1646c2a6b6e0794d321dd738a6918`; this document |
| PR1 | Schema/security foundation for channel + request + tracking | IMPLEMENTED | Migration `20261125090000_public_registration_foundation.sql` + static contract test |
| PR2 | Narrow public read/submit/status server boundary | IMPLEMENTED | Migration `20261125093000_public_registration_public_boundary.sql`, Edge Function `public-registration`, static boundary tests |
| PR3 | Admin list/review + identity resolution integration | IMPLEMENTED | Migration `20261125100000_public_registration_admin_review.sql`, protected device dispatch + static tests |
| PR4 | Protected approval/reject orchestration into canonical booking | IMPLEMENTED | Migration `20261125113000_public_registration_protected_decision.sql`, approved-device dispatch allowlist, and protected-decision regression tests |
| PR5 | Public/admin UI integration + event settings + public tracking projection | IMPLEMENTED | Platform public page + Edge deployment; Reservations event-tab settings/review UI; payment/accommodation visibility options |
| PR6 | Notification delivery foundation + selected provider | NOT STARTED | — |
| PR7 | Waitlist/capacity only after authoritative capacity contract | NOT STARTED | — |
| PR8 | Full Development verification, Preview evidence, acceptance closure | NOT STARTED | — |

Status values: `NOT STARTED -> IN PROGRESS -> IMPLEMENTED -> TESTED -> ACCEPTED`.
Every implementation commit must update this table or the Implementation Log below with exact SHA, migrations, tests, CI run IDs, Preview evidence, and outstanding blockers.

## 17. Phase acceptance gates

### PR1
- forward-only Development migration;
- RLS/privileges prove anonymous clients cannot mutate tables directly;
- revisions, scope constraints, state checks and tracking-secret storage contract tested;
- no Production application.

### PR2
- public event read returns only allowlisted public fields;
- disabled/not-open/closed channels reject submission;
- submission idempotency/replay proven;
- malformed/oversized/cross-event payloads rejected;
- tracking secret cannot enumerate requests;
- no Person candidate leakage.

### PR3
- authorized operator can list/review only permitted event requests;
- identity candidates stay administrative;
- stale identity/request revisions conflict explicitly;
- no automatic central Person overwrite.

### PR4
- approval creates exactly one canonical booking;
- duplicate/replay cannot create a second booking;
- stale/invalid booking type is rejected for operator resolution;
- request and booking linkage is consistent under injected failure/concurrency;
- reject/waitlist do not create bookings;
- audit evidence records trusted actor/device.

### PR5
- current SPA consumes only the new canonical operations;
- no direct table writes or local fallback;
- mobile/desktop CSS follows shared design ownership;
- cache/runtime revision is atomic;
- browser automation remains prohibited by `AGENTS.md`; manual visual acceptance is recorded separately when available.

### PR6
- notification provider failure leaves approved booking/request intact;
- retries are idempotent;
- delivery status is observable to authorized admin;
- secrets remain server-side.

### PR8
- focused tests PASS;
- `check:development-preview` PASS;
- relevant GitHub Actions PASS;
- Development Preview SHA equals final implementation SHA where path filters trigger deployment;
- `main`/Production untouched;
- manual visual acceptance recorded or explicitly BLOCKED/UNVERIFIED, never fabricated.

## 18. Required test matrix

At minimum:
- two different events cannot cross-read/submit/approve;
- disabled/open/closed registration window;
- same submit operation replay;
- concurrent duplicate submissions;
- same-name different people;
- shared-phone different people;
- candidate requires explicit operator decision;
- new Person creation race;
- existing Person with changed submitted fields;
- duplicate existing booking in same event;
- same Person booking different events;
- booking type changed/deactivated/price changed after submission;
- request revision conflict;
- approve replay/concurrency;
- injected booking failure rolls back approval linkage;
- reject and waitlist create no booking;
- tracking token invalid/revoked/expired behavior once expiry policy is implemented;
- notification failure/retry once PR6 exists;
- no public access to admin/person candidates/audit/private tables.

## 19. Deferred decisions

These are deliberately not guessed:
- tracking token expiry/rotation duration;
- exact required public form fields and which event fields are public;
- whether registrants may edit/cancel a submitted request;
- exact capacity consumption semantics (which booking states count against `reservations.events.capacity`);
- waitlist ordering policy;
- canonical family registration with roles `primary`, `adult`, `child_paid`, and `child_dependent`; every child selects a preceding adult/primary guardian;
- OTP/pre-fill;
- payment during public registration;
- notification provider/channel/template/consent policy;
- QR presentation;
- auto-approval enablement criteria.

A deferred decision must be resolved in this document before code that depends on it is exposed.

## 20. Implementation log

### PR0 — contract baseline
- Baseline: `5204d14054f1646c2a6b6e0794d321dd738a6918`.
- Read: `AGENTS.md`, Person Bank foundation, Conference core/creation contracts, operational eligibility contract, current Reservations identity-resolution migration, canonical pricing migration, and active device-operation allowlist.
- Confirmed: `platform.people` is permanent identity; name/phone are nonunique candidate signals; current Reservations identity resolution is explicit/manual; `reservations_private.mutate_scoped` is the sole current booking writer; operational price comes from the event booking type; current admin operations are protected by approved user/device/session routing.
- Runtime/database change: none.
- Production/main/Supabase change: none.
- PR1 schema names resolved under `reservations`: `public_registration_channels` and `public_registration_requests`.
- Existing `reservations.events.capacity` confirmed as the event-level capacity source; consumption semantics remain deferred until PR7.
- Next: PR2 narrow public read/submit/status boundary, including hosting/origin and rate-limit design.


### PR1 — schema/security foundation
- Migration: `supabase/migrations/20261125090000_public_registration_foundation.sql`.
- One channel per Reservations event; channel uses an opaque UUID public identifier and stores no URL/host assumption.
- Requests are event/channel scoped by a composite foreign key and their booking type is constrained to the same event through the restored relational `(event_id,id)` booking-type key; they carry a UUID submit operation identity, immutable submitted profile fields, requested booking type, state/revision, tracking-secret SHA-256 digest, and optional canonical Person/Booking links.
- Tracking secret plaintext is never stored.
- Approval linkage is constrained so only `approved` requests can hold a booking and approved requests must hold both canonical Person and Booking identities.
- Tables use enabled + forced RLS and grant no table privileges to `public`, `anon`, `authenticated`, or `service_role`.
- No public/admin RPC is added in PR1. PR2/PR3 must add narrow server operations rather than table grants.
- Runtime/UI/Edge Function change: none.
- Production/main application: none.

### PR2 — narrow public boundary
- Edge Function: `supabase/functions/public-registration/index.ts`, configured with `verify_jwt = false`; it is separate from the administrator/device dispatcher.
- Exact operation allowlist: `event`, `submit_family`, `status`; individual registration is a one-member family submission. V1 `submit` is retired from Edge, gateway, and database; fixed GitHub Pages CORS origin; no browser service-role credential.
- Edge requires `PUBLIC_REGISTRATION_HMAC_SECRET`; it derives a stable tracking capability from channel public ID + submit operation ID and sends only its HMAC digest to PostgreSQL, so replay returns the same capability without plaintext storage.
- Database RPC execute is granted only to `service_role`; tables remain forced-RLS and ungranted.
- Public event read returns only event name/dates/location plus active booking-type public fields.
- Submission validates enabled/open window, event status, approval-required mode and same-event active booking type; it never writes Person or Booking.
- Submission uses advisory-lock idempotency and an intent digest; conflicting reuse of an operation ID fails closed.
- Status lookup requires the tracking capability digest and returns request state/reference/timestamps plus booking number only after approval.
- DB-backed minute-bucket abuse control: submit 8/minute; read/status 60/minute per channel/fingerprint.
- Runtime admin/UI change: none. Production/main application: none.

### PR3 — protected admin review
- Added protected Reservations operations `list_public_registration_requests` and `get_public_registration_request` through the existing approved-device dispatcher.
- Both reuse `reservations.booking.create` event scope/permission; no new permission engine or bypass.
- List is strictly event-scoped, state-filtered and bounded to 500 rows.
- Review returns the submitted snapshot, current booking-type active/price state, and up to 20 canonical Person candidates based on normalized exact name or phone signals.
- Candidate output includes whether that Person already has a booking in the same event; candidates are never exposed by the anonymous public endpoint.
- PR3 is deliberately read-only: it cannot update requests, create/update People, or create Bookings. Identity decision and approval remain PR4.

### PR4 correction — explicit different/new Person decision
- Canonical approval remains the existing Reservations booking writer; no direct Person/Booking insert was introduced.
- When identity candidates exist, the operator may explicitly choose a candidate or choose a different/new Person.
- The different/new path reuses the canonical identity-resolution challenge handshake with decision `different`.
- Development corrective migration history includes `public_registration_explicit_new_identity_canonical_challenge`; repository forward migration: `20261125120000_public_registration_explicit_new_identity_canonical_challenge.sql`.
- Reservations UI exposes `اعتماد كشخص جديد / مختلف` even when candidates exist.

### PR5 — implemented public/admin UI and event settings
- Public route is now resolved: `public-registration.html?event=<publicId>`.
- Public page files: `public-registration.html`, `public-registration.css`, `public-registration.js`.
- Public page is isolated from the authenticated Platform shell and calls only the `public-registration` Edge operations `event`, `submit_family`, and `status`.
- After submit, the same page retains the opaque tracking capability in the participant's tracking URL and renders status without exposing Person candidates or administrative data.
- Supabase Development Edge Function `public-registration` was deployed ACTIVE with `verify_jwt=false`; its narrow public boundary still enforces fixed origin, exact operation allowlist, HMAC-derived tracking digest, rate limits, and service-role-only database RPC execution.
- Edge deployment required an explicit import map; repository source now includes `supabase/functions/public-registration/deno.json`.
- Event-level Public Registration settings are integrated into the existing Reservations event UI, not a new top-level module. Settings use protected operations and revision/idempotency semantics.
- The admin UI exposes the actual public URL and a copy-link action. No fabricated/parallel URL path remains.
- `auto_approve` remains schema-reserved and is intentionally not exposed as a working UI mode; the implemented/default flow is `approval_required`.

### PR5 tracking visibility — canonical projections only
- Event settings now include two independent booleans: `show_payment_status` and `show_accommodation`.
- These settings live on the existing `reservations.public_registration_channels` row. No second settings table was created.
- Public request rows do **not** store room, paid amount, balance, or financial/accommodation snapshots.
- When payment visibility is enabled and the request has an approved booking, status reads the canonical operational booking and current event booking-type price plus active `reservations.payments`; it returns `price`, `paid`, and `remaining`.
- When accommodation visibility is enabled, status reads the canonical Conference participation/occupancy/room/floor/house chain. Before assignment it returns `assigned=false`; after assignment it returns the allowed room/house/floor projection.
- The public page renders these fields only when the server includes them.
- Development migration: `20261125133000_public_registration_tracking_visibility.sql`.

### Current handoff — 2026-11-25
- Platform repository: `ramyawny37/conference-management-system-v1`, branch `develop` only.
- Current Platform head at this documentation update: `0fe588b0cf9ec543a89b378a357d1753ad79ab17`.
- Relevant implementation commits include:
  - `9d70e7656e737554209fdcc84b01744ecfc4a78e` — Edge import map and successful Development deployment basis.
  - `f0dd16ffb979b2b630179378a581f01834b864df` — public registration/tracking page.
  - `7259ce116655c6f221c91901c75174c30b85c62f` — canonical payment/accommodation tracking projection.
  - `bf58bff944226154c25065d9d2dab2c30c1803c9` — render optional payment/accommodation tracking.
  - `36e16524fc034dd0ebcb50b8b3a6ac424ec71522` — structural parity pin after tracking visibility.
- Reservations source repository: `ramyawny37/reservation-management-system`, branch `develop`.
- Relevant Reservations commits:
  - `d11b43208b33277f1b88e8894eb99ba9354858b3` — expose canonical public link.
  - `014065a659611ef243c4bd7dc313eb3e9802dc5e` — event-level public tracking visibility controls.
- Reservations CI and develop validation for `014065a...`: PASS.
- Platform exact-SHA Reservations integration was PASS on the preceding PR5 commits; zero-data replay after the two visibility columns correctly reported the expected structural delta (columns 1154→1156; functions remain 288 with semantic fingerprint change), and `36e16524...` pins those Development-derived fingerprints. Re-check the latest head Actions before claiming final PR5 CI closure.
- Supabase Development project only: `gppwltrifgfxrkzvvxoe`. Do not use Production.
- `public-registration` Edge Function is deployed ACTIVE v1 on Development with `verify_jwt=false`.
- **Open operational blocker:** `PUBLIC_REGISTRATION_HMAC_SECRET` must exist in the Development Edge Function environment. The available Supabase connector can deploy functions but cannot read/create project secrets. Do not replace this with a hard-coded secret, publishable key, service-role key, or client-side fallback.
- After the HMAC secret is confirmed/set, run the real Development flow: enable one event → copy/open public link → submit → verify admin pending request → approve with existing or different/new Person → open tracking link → verify booking number → record payment and verify paid/remaining projection when enabled → assign accommodation and verify room projection when enabled.
- Browser automation remains prohibited by Platform `AGENTS.md`; visual acceptance is manual.
- No `main`, Production, Vercel, or Production data change is authorized.


### PR8 — Development verification checkpoint
- Verified Platform develop HEAD `f26d7f8edbf65af8e3f7bbfcad8140765cc1a611` and Reservations develop HEAD `014065a659611ef243c4bd7dc313eb3e9802dc5e` via GitHub.
- Development Edge listing confirms public-registration ACTIVE v1, verify_jwt=false, import map enabled.
- Live Development SQL confirms both tracking visibility columns exist as boolean.
- Latest Actions and full structural fingerprint parity remain UNVERIFIED: available workflow query is PR-only and returned no runs; combined statuses empty.
- HMAC secret remains UNVERIFIED: connector exposes no Edge secrets management operation. Use Development dashboard Edge Function Secrets; check existence before setting, do not rotate existing secret casually.
- End-to-end acceptance remains BLOCKED/UNVERIFIED; no runtime or database mutations performed in this checkpoint.
