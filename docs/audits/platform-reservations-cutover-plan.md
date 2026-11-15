# Platform and Reservations cutover plan

This plan preserves Platform `14102f906a3646487903c8d2459788b56f209497` as the approved runtime and treats Reservations `c56a8fdd2ccde4405a3c73f3580b27b08b1cf5c9` as a rejected candidate. Each change set is atomic and must finish all gates before the next begins.

## Change set 0 — freeze and guard (implemented)

1. Record the approved runtime JS/CSS fingerprints and cache revision.
2. Record reverted artifact fingerprints and source commit as rejected.
3. Keep `approvedIntegrations` empty.
4. Make the existing integrator reject known-reverted and all unapproved artifacts before writing tracked files.
5. Validate current runtime drift before any future replacement.

Rollback: revert only the policy/tool/test/workflow commit. Runtime files are unchanged.

Acceptance: policy tests, syntax, duplicate function scan, undefined reference scan, dependency verification, existing Platform and Reservations integration tests.

## Change set 1 — source-to-artifact provenance

Owner: Reservations source repository.

1. Keep UI changes in `src/**`; never edit Platform generated JS/CSS.
2. Extend the existing source build (not a second build path) to emit a manifest containing exact source SHA, Node/npm/Vite versions, JS/CSS hashes, and artifact schema version.
3. Pin the build toolchain where it affects deterministic output.
4. Upload the manifest with `reservations-platform-module` from the existing CI workflow.
5. Do not mark the manifest approved; it is provenance, not acceptance.

Rollback: revert the source build/CI commit; no Platform runtime changes.

## Change set 2 — design convergence in source

Owner split: Platform owns semantic tokens/shell; Reservations owns module page composition.

1. Diff source selectors against Platform tokens and primitives.
2. For each overlap, classify it as module layout, shared semantic primitive, compatibility-in-use, or dead.
3. Move only proven shared semantics to Platform tokens; update the source consumer in the same change.
4. Do not add an override stylesheet and do not modify generated files.
5. Preserve specialized page grids, reports, tables, dialogs and responsive behavior.

Required visual gate: approved screenshots/DOM at desktop, tablet and mobile for dashboard, event, booking, participant detail, payments, cancellation/refund, attendance, operations and reports, with RTL and focus/overflow evidence.

Rollback: source commit revert. No artifact approval until the baseline is restored.

## Change set 3 — functional parity

Run in the Reservations source and Platform contract suites:

- canonical person identity, DOB/profile fields and duplicate resolution;
- event-isolated booking types, pricing, people, accounts and reports;
- create/edit/delete/rebook, payments, void, apology, settlement and partial/full refund;
- attendance and operational review;
- mutation invalidation/readback without manual refresh;
- permission denial and stale revision/idempotency cases.

Run Platform suites for login, device sessions, users/roles/grants, Conference, accommodation/guardian/child, transport, cards, reports, Warehouse and administration. Hosted Development checks must be read-only unless a separate authorized migration task exists.

## Change set 4 — explicit approval

Only after change sets 1-3 provide evidence:

1. Add exactly one entry to `approvedIntegrations` with source commit, cache revision and JS/CSS hashes.
2. Require source CI success for that exact SHA.
3. Require visual baseline approval and functional matrix completion in the review record.
4. Run the existing integrator once from a clean Platform `develop` tree.
5. Review the atomic diff: exactly both generated files, `index.html`, and `service-worker.js`, plus policy baseline advancement where required.

Rollback: revert the Platform integration commit and redeploy the prior Development Preview. Never promote to `main` or Production in this plan.

## Change set 5 — deletion pass

Deletion is last. A candidate is `PROVEN-DEAD` only when:

1. it is not loaded by HTML, service worker, imports, dynamic registry, tests, release tools, or database transport;
2. runtime instrumentation or an equivalent deterministic test shows no consumer;
3. an approved replacement owns every read/write path;
4. full functional and visual gates pass without it;
5. rollback is a single commit revert.

`UNKNOWN` and `COMPATIBILITY-IN-USE` items are not deletion candidates.

## Verification matrix

| Gate | Current result | Required before artifact integration |
|---|---|---|
| Platform baseline/tree | PASS | exact `14102f9` baseline |
| Reverted artifact rejection | PASS | automated policy test |
| Single integration utility | PASS | existing tool only |
| Source unit/type/contract tests | PASS: typecheck, 301/301 tests, build | PASS on candidate SHA; does not approve rejected UI |
| Platform Development Preview suite | PASS: 647/647 | PASS |
| Platform broad suite | PARTIAL: 652/657; five Production-promotion tests require files absent from baseline | Development suite PASS; Production remains out of scope |
| Local PostgreSQL contract tests | covered by Development CI suite; exact hosted state still unproven | PASS |
| Production dependency audit | Platform PASS; Reservations source FAIL (1 critical, 3 high) | source remediation and full requalification |
| Hosted Development database audit | BLOCKED without read-only credentials | PASS or explicit BLOCKED acceptance |
| Desktop/tablet/mobile screenshot parity | BLOCKED by no-browser rule/baseline absence | explicit human or authorized visual evidence |
| Integrated operational smoke flows | BLOCKED without test identity/device | PASS before approval |
| Development Preview publication | not needed for guard-only change until CI passes | exact SHA, provenance and live hash verification |
| Production | OUT OF SCOPE | must remain untouched |
