# P2A — canonical Platform Person Bank

Status: foundation only, on develop; no live migration, public RPC, mutation API,
permission grant, dispatcher change, legacy import, or module adoption.

## Precheck and scope

The active migration history contains no canonical Platform business Person bank.
`platform.profiles` is a login/account record keyed by `auth.users`, not a business
Person. `people.js` stores Conference-local `peopleDb` records (including age and
notes); Reservations participants carry operational fields and scope ownership.
Neither can be renamed into this contract without migrating existing consumers.
Both remain unchanged.

Evidence used:

- `people.js`: `normalizePersonRecord`, `normalizePersonKey`, `getPeopleDb`.
- `script.js`: `normalizePhoneNumber` (digit normalization, plus Egypt-specific
  rules that are deliberately not imported into a platform-wide identity bank).
- `20260908171814_reservations_event_booking_domain_reconciliation.sql`:
  participant full name, phone, church, governorate and city/village.
- `20260907155000_production_structural_platform_foundation.sql`: UUID defaults,
  profile actor references, timestamp trigger, RLS, Platform audit storage.
- `20260912192000_platform_module_entry_access_gate.sql`: approved profile,
  active key/device/authorization/session validation and module access.
- `20260907140000_module_access_delegation_enforcement.sql` and
  `20260829130000_module_permission_catalog_and_grant_adapter.sql`: canonical
  permission resolution and catalog/grant administration.
- `supabase/functions/platform-device-operation/index.ts`: protected dispatcher
  permits only Conference, Reservations and Warehouse; P2A adds no route.

## Exact storage contract

`platform.people` is the sole new canonical Person table.

| Column | Contract |
| --- | --- |
| id | UUID primary key, `extensions.gen_random_uuid()` default; independent of login User |
| full_name | Required text, 1–240 characters, nonblank after whitespace normalization |
| phone | Optional text, 1–40 characters when supplied, must contain a digit; nonunique |
| gender | Optional `male` or `female` |
| date_of_birth | Optional date, supplied explicitly; never derived from age |
| church | Optional nonblank text, at most 200 characters |
| name_search | Stored generated normalized name |
| phone_search | Stored generated normalized phone; empty for absent phone |
| revision | Positive bigint, default 1; future canonical mutation must increment it |
| created_at / updated_at | Required timestamptz, default statement timestamp; existing Platform update trigger maintains updated_at |
| created_by / updated_by | Nullable UUID actor references to `platform.profiles(user_id)`, ON DELETE RESTRICT |

Actor references record the operator; they do not require the represented Person
to have a login. NULL actors are reserved for explicitly system-controlled storage
creation/import/bootstrap/reconciliation, not interactive operations. The Platform
foundation already permits nullable actors (for example role_permissions.created_by
and audit_events.actor_user_id); no dedicated canonical system profile was found.
No fake profile is created. Present actor IDs retain their foreign keys and
ON DELETE RESTRICT behavior. With no exposed API and no client/service-role DML
privileges, only trusted database administration can perform actorless writes now.
This is a privileged storage contract, not a per-row system-origin attestation.
Every future exposed mutation MUST assign the authenticated/trusted actor from
validated execution context, reject client-selected actor IDs, and preserve the
original creator on updates. An interactive update of a system-created Person
sets updated_by while created_by may remain NULL.

Church is included because both Conference Person records and
Reservations participants reuse it. Governorate and city/village are excluded:
the reviewed Conference Person contract does not establish shared reuse.

Excluded: organization, workspace, age, children/guardians, participation and
reservation statuses, booking number/type, attendance, payments, accommodation,
rooms, transport, restaurant, accounts, cards, notes, service sectors, generic
JSON metadata. No automatic legacy copy or inferred date of birth.

## Search and duplicates

`platform_private.person_name_key(text)` collapses whitespace, trims, and lowers
case. It preserves Arabic letters, diacritics and other distinctions; no fuzzy
matching or destructive equivalence. `person_phone_key(text)` maps Arabic and
Eastern Arabic digits to ASCII and removes formatting/non-digits. It does not
infer country codes. Original business values are preserved.

`platform_private.search_people(text,text,integer)` is an internal SECURITY
INVOKER function with empty search_path. It supports literal prefix lookup on
normalized name and an optional exact canonical gender filter. Phone matching is
additionally enabled only when the query contains at least one digit and consists
entirely of ASCII/Arabic/Eastern Arabic digits, whitespace, plus, parentheses,
periods or hyphens. These phone-formatted queries also retain literal name-prefix
matching. Ordinary names and mixed/alphanumeric queries are name-only: `Person
0123` cannot match a different person's phone beginning with 0123. Prefixes such
as `0123abc` or `phone:0123` are likewise name-only; they are not phone parsers.
LIKE
metacharacters are escaped. Blank query gives a bounded ordered listing; absent
phones do not match nonempty phone queries. Results order by name_search under
C collation, then UUID. Limit defaults to 20 and is clamped to 1–50, including
NULL, zero, negative and oversized requests. Invalid gender raises
`PLATFORM_PERSON_GENDER_INVALID`.

Nonunique B-tree text_pattern_ops indexes support name/phone prefixes (phone
index partial on present phones); a name_search C-collation + id index supports
ordering. No extension for fuzzy search or additional search service.

Duplicate names and shared phone numbers are valid. Search only returns
candidates; it never creates, merges or updates a Person. Explicit future
creation establishes a new UUID. Neither name nor phone is an identity key.

## Security, audit and adoption gate

No client read or mutation API is implemented in this round. No permissions,
roles, module registration or grants are added: there is no consumer operation
to authorize yet. Conceptual people.view/create/update/delete are not inserted
as invalid or speculative catalog keys.

The new table enables and forces RLS, with no client policies. ALL table
privileges and ALL execution privileges on the three helpers are revoked from
PUBLIC, anon, authenticated and service_role. SECURITY INVOKER search cannot
elevate privilege. Existing schema grants do not grant access to these objects.
Database owners/superusers remain trusted administrators, as elsewhere.

A future adoption change must compose with the existing authenticated-user,
approved-profile/device/session boundary and platform-device-operation
allowlist, canonical catalog/grant permission resolver, operation replay/intent
checks, and atomic audit conventions. It must not expose these helpers directly
or create an alternative authentication/permission system. The current
`platform.audit_events` storage is the audit foundation; module mutation flows
show atomic operation-ledger, revision and audit handling. P2A adds neither a
second ledger nor a fake audit/idempotency implementation. There is no exposed
mutation to replay or audit here. Nullable actor metadata and the existing
`platform_private.set_updated_at()` trigger are reused now. Revision checks,
operation IDs, trusted actor assignment and audit insertion must accompany any
future mutation API before it receives privileges.

## Deletion and references

No Person deletion API or cross-module lifecycle is implemented. Client DELETE
and TRUNCATE are denied. Future activity/participation references must use
restrictive foreign keys to `platform.people(id)` (ON DELETE RESTRICT/NO ACTION),
so a referenced Person cannot be physically removed. Deleting participation or
a Booking must not delete its reusable Person. No speculative foreign keys or
cascades into current module tables are added. A test-only restrictive reference
proves that contract; it is not a claim that module integration exists today.

## Objects and validation

New objects: one table, three private functions, three nonunique indexes, one
update trigger, primary/check/actor foreign-key constraints. Existing Platform
schemas, UUID provider, profile references and timestamp function are reused.
No existing runtime object is replaced.

The focused test executes the actual migration and existing profile DDL/timestamp
function in a uniquely named disposable PostgreSQL database on an explicit local
socket. Only auth.users is a minimal upstream fixture. It checks minimum creation,
duplicate identities/phones, gender, Arabic and phone search, name-versus-phone
query classification, mixed input, literal patterns, system-null and valid/invalid actors,
bounds/order/read-only search, exact columns/indexes, invalid values, actor FKs,
timestamp behavior, privileges and denied statements for all client roles, and
future restrictive-reference behavior. It drops the database in finally. These
are storage/internal-search tests, not claimed end-to-end dispatcher tests.

No Development/Production database, browser, UI test, legacy person import,
frontend/Edge/Warehouse change, commit or push is part of P2A. Pending U2B files
are separate and preserved.
