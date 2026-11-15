# Conference canonical cutover plan

This plan starts from Platform `83237d82058a255efe1c8662dffe40ac03573868`. Every group is independently reversible. No group may alter `main`, Production, Production data, approved Arabic text, public globals, or generated Reservations files.

## Group 0 — ownership guard (implemented)

1. Preserve all active runtime files.
2. Assert each major Conference presentation/service entry is loaded exactly once.
3. Reject direct table mutation writers in active browser domains.
4. Assert canonical mutations use protected dispatch and authoritative refresh.
5. Assert the Reservations rejection policy remains active.

Acceptance: syntax, ownership tests, existing Development suite, duplicate/undefined/dependency scans. Rollback: revert the single guard/docs commit; runtime is unchanged.

## Group 1 — instrumented consumer proof

Before deleting or moving any global function:

1. Build a test-only global/callsite manifest covering inline HTML handlers, dynamically generated `onclick` strings, module registration, timers, events, Service Worker assets, and release tools.
2. Capture an authorized Development browser trace for desktop and mobile across every module.
3. Classify only zero-consumer entries as deletion candidates.
4. Add a failing contract test for each candidate before removal.

Blocked now: browser execution is forbidden by repository instructions.

## Group 2 — linked/local path decision

The linked canonical and local/unlinked persistence paths are currently compatibility behavior, not proven duplication. Product owners must decide whether local/unlinked Conferences remain supported. If retirement is approved:

1. inventory local records and templates;
2. provide an explicit migration/export path;
3. move every consumer to the canonical facade;
4. verify offline/error behavior;
5. remove the local writer only after data migration and visual/functional gates.

Rollback: retain exported data and revert the atomic consumer+writer commit.

## Group 3 — domain-by-domain consolidation

Execute separately in this order:

1. Conference core and participation;
2. guardian/child and accommodation/leases;
3. transport and cards;
4. finance, payments, meals, A/C and reports;
5. Warehouse and administration.

For each domain: prove competing writer, add behavior tests, choose the existing canonical facade, move all consumers, verify authoritative readback/event isolation, then delete only the proven unused implementation. Never keep a fallback beside the replacement.

## Group 4 — CSS convergence

1. Capture approved DOM/screenshots at desktop, tablet and mobile for every specialized page.
2. Produce selector coverage and computed-style diffs.
3. Move only shared semantic values into `shared-design-tokens.css`.
4. Retain specialized layout in its domain stylesheet.
5. Remove a selector only with zero coverage and zero computed-style change.

No override stylesheet is permitted. Rollback is the domain CSS commit plus redeployment of the prior Preview SHA.

## Group 5 — live Development acceptance

Using Development-only accounts/devices/data:

- create/edit/switch events and verify isolation;
- person/participation create, edit, apology, delete and rebook;
- payment, partial/later refund, credit and settlement;
- guardian-child shared/separate rooms, replacement, move, delete propagation and extra beds;
- transport assignments, cards, accounts and reports;
- permissions, denial, idempotency and concurrent room leases;
- immediate UI readback without refresh;
- desktop/mobile RTL screenshot parity.

Hosted database checks must be read-only unless a separately authorized Development migration is required.

## Current gate matrix

| Gate | Status | Evidence / blocker |
|---|---|---|
| Exact `develop` baseline | PASS | local and `origin/develop` initially `83237d8` |
| Single protected canonical writer boundary | PASS (static) | ownership test + Edge dispatcher evidence |
| Active load singularity | PASS | ownership test |
| Reservations c56 rejection | PASS | artifact policy test |
| Development Platform suite | PASS | 647/647; Preview validation 647/647 |
| Focused Conference/domain suite | PASS | 102/102 including ownership, accommodation, identity, locks and permissions |
| Syntax/duplicate/undefined/dependency scans | PASS | completed after edits |
| Production dependency audit | PASS | zero vulnerabilities in Platform dependencies |
| Local PostgreSQL contracts | PASS for repository/CI-compatible contracts | does not prove hosted Development state |
| Hosted Development DB state | BLOCKED | no read-only connection/identity supplied |
| Interactive operational flows | BLOCKED | no approved identity/device and browser forbidden |
| Desktop/mobile visual parity | BLOCKED | browser forbidden and no committed screenshot baseline |
| File/function deletion | NOT PERFORMED | no `PROVEN-DEAD` candidate |
| Production | OUT OF SCOPE | must remain untouched |

## Priority backlog

1. **High:** obtain authorized visual baseline and Development identities; otherwise runtime cleanup cannot safely pass acceptance.
2. **High:** decide whether local/unlinked Conference operation is a supported product mode.
3. **Medium:** add test-only dynamic global coverage; static name matching is insufficient for generated inline handlers.
4. **Medium:** audit selector coverage after visual tooling is explicitly permitted.
5. **Low:** split large presentation files only when ownership boundaries are behavior-tested; file size alone is not a defect.
