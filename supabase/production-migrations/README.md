# Dedicated Production migration stream

`supabase/migrations/` is the immutable canonical/Development/provenance
stream. It is not executable against Production because its historical file
versions do not match Production migration history and some extracted versions
collide.

`supabase/production-migrations/` is the only approved Production forward
stream. Every entry is identified and hashed in `manifest.json`. Production
operations must use `scripts/production-migration-runner.js`, explicitly select
one next version, pass the exact Production project ref, and stop after that
single migration.

The following commands are prohibited against Production:

- `supabase db push`, with or without `--include-all`
- `supabase migration up`, with or without `--include-all`
- direct execution of `supabase/migrations/`
- `supabase migration repair`

The runner requires `PRODUCTION_DB_URL`, `--project-ref
mpezfbvcdfxpgflehuot`, and either `--dry-run` or `--apply`. Apply mode also
requires `PRODUCTION_MIGRATION_AUTHORIZATION` to equal the one requested
version. The Development ref `gppwltrifgfxrkzvvxoe` is always rejected.

Both dry-run and apply fail closed until a controlled Production read-only
preflight has populated the manifest's `productionDatabaseIdentity` and
`migrationHistoryContractSha256`. Database identity is proved from the
connected PostgreSQL instance using `pg_control_system().system_identifier`,
`current_database()`, and the PostgreSQL major version; it is not inferred from
the supplied project ref or URL hostname. The history contract records the
actual column types, nullability, defaults, constraints, version/name and
`text[]` statements representation, plus existing content digests. Any missing
or divergent proof prevents mutation.

The repository command guard tokenizes repository-controlled invocations,
including `npx`, quoted executables, relative/absolute binaries, and global
flag ordering. It cannot prevent an operator who independently possesses shell
and database credentials from bypassing repository tooling. Production
credentials therefore must only be provisioned to the controlled runner
environment; CI and approved execution paths must invoke the guard.

If a transaction commits but its post-verifier fails, the runner terminates as
`COMMITTED_POST_VERIFICATION_FAILED`, reports the committed version/name, and
requires read-only diagnosis and separate recovery authorization. It never
rolls back an already committed migration, replays it, or advances the stream.

Before each step and after each verifier, the runner also captures the exact normalized
catalog contract defined by `audit/phase-2al/catalog-snapshot.sql`. It compares columns,
constraints, indexes, triggers, functions, security, and the combined identity against
the reviewed two-run constants in `catalog-contracts.json`. Function/relation owner and
ACL grantor must be the Production read-only-evidenced semantic role `postgres`; role
names are never replaced with cluster-local OIDs. Object-specific ACL and policy shapes
remain protected by the exact component hashes.

Canonical 6.20.0 is preserved unchanged. Its Production structural derivative
omits only feature activation, recorded as `PRODUCTION_ACTIVATION_DEFERRED`.
WebAuthn and device enforcement remain disabled through reconciliation and
grant hardening. Only the final manifest entry may enable WebAuthn; it never
enables device enforcement.

The untracked Phase 2AD bridge under `supabase/migrations/` is audit provenance,
not an executable canonical migration. Its corrected executable descendant is
the first entry of this Production stream.
