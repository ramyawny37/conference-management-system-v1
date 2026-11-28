'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { buildApplicationBootstrap } = require('../tools/production-release/application-bootstrap-contract.cjs');

const script = path.resolve(__dirname, '../tools/production-release/export-development-schema-only.cjs');
const dev = 'postgresql://postgres:dummy-password@db.gppwltrifgfxrkzvvxoe.supabase.co:5432/postgres';
const prod = 'postgresql://postgres:dummy-password@db.mpezfbvcdfxpgflehuot.supabase.co:5432/postgres';
const run = (url, overrides={}) => spawnSync(process.execPath, [script], {
  encoding: 'utf8',
  env: { ...process.env, DEVELOPMENT_DATABASE_URL: url, ...overrides },
});
const dumpSection = (name, type, schema, body) =>
  `--\n-- Name: ${name}; Type: ${type}; Schema: ${schema}; Owner: -\n--\n\n${body}\n\n`;
const mockDump = (extra='') => '-- PostgreSQL database dump\n' +
  dumpSection('platform', 'SCHEMA', '-', 'CREATE SCHEMA "platform";') +
  dumpSection('public', 'SCHEMA', '-', 'CREATE SCHEMA "public";') +
  dumpSection('example', 'TABLE', 'platform', 'CREATE TABLE "platform"."example" ("id" integer);') +
  dumpSection('SCHEMA "platform"', 'ACL', '-', 'GRANT USAGE ON SCHEMA "platform" TO "authenticated";') +
  dumpSection('DEFAULT PRIVILEGES FOR FUNCTIONS', 'DEFAULT ACL', 'public',
    'ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";') +
  dumpSection('DEFAULT PRIVILEGES FOR FUNCTIONS', 'DEFAULT ACL', 'public',
    'ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";') +
  extra + '--\n-- PostgreSQL database dump complete\n--\n\n\\unrestrict mock-token\n' + '-- padding\n'.repeat(100);
test('rejects Production connection before launching pg_dump', () => {
  const r = run(prod);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /Only the explicit Development project direct connection or its session pooler is allowed/);
  assert.doesNotMatch(r.stderr, /dummy-password/);
});
test('rejects pooler identities not bound to Development and transaction pooler mode', () => {
  for (const url of [
    'postgresql://postgres.mpezfbvcdfxpgflehuot:dummy-password@aws-0-eu-central-1.pooler.supabase.com:5432/postgres',
    'postgresql://postgres.gppwltrifgfxrkzvvxoe:dummy-password@aws-0-eu-central-1.pooler.supabase.com:6543/postgres',
  ]) {
    const r = run(url);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Only the explicit Development project direct connection or its session pooler is allowed/);
    assert.doesNotMatch(r.stderr, /dummy-password/);
  }
});
test('rejects absent database credentials before launching pg_dump', () => {
  const r = run('postgresql://postgres@db.gppwltrifgfxrkzvvxoe.supabase.co/postgres');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /Database password required/);
});
test('rejects custom relative pg_dump executable', () => {
  const r = run(dev, { PG_DUMP_BIN: './fake-pg-dump' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /absolute executable path/);
});
test('fails closed if pg_dump executable is missing', () => {
  const r = run(dev, { PG_DUMP_BIN: path.join(os.tmpdir(), 'nonexistent-pg-dump-canonical') });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /pg_dump executable not available/);
  assert.doesNotMatch(r.stderr, /dummy-password/);
});
test('does not log secret on malformed database URL', () => {
  const r = run('postgresql://invalid:secret@db.gppwltrifgfxrkzvvxoe.supabase.co/');
  assert.equal(r.status, 1);
  assert.doesNotMatch(r.stderr, /secret/);
});

test('schema-only guard allows DML inside function bodies but rejects dumped table data', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'canonical-schema-dml-'));
  const executable = path.join(dir, 'pg_dump');
  const functionSql = mockDump(dumpSection('writer()', 'FUNCTION', 'platform', 'CREATE FUNCTION "platform"."writer"() RETURNS void LANGUAGE plpgsql AS $fn$\nBEGIN\n  UPDATE "platform"."example" SET "id" = 1;\nEND;\n$fn$;'));
  fs.writeFileSync(executable, '#!/usr/bin/env node\nif(process.argv.includes("--version")) { console.log("pg_dump (PostgreSQL) 17"); process.exit(0); }\nprocess.stdout.write(' + JSON.stringify(functionSql) + ');\n', { mode: 0o700 });
  try {
    const ok = run(dev, { PG_DUMP_BIN: executable });
    assert.equal(ok.status, 0, ok.stderr);
    const artifact = path.resolve(__dirname, '../.release-local/development-application-schema-only.sql');
    if (fs.existsSync(artifact)) fs.unlinkSync(artifact);
    const dataSql = mockDump('-- Data for Name: example; Type: TABLE DATA; Schema: platform; Owner: postgres\nCOPY "platform"."example" ("id") FROM stdin;\n1\n\\.\n');
    fs.writeFileSync(executable, '#!/usr/bin/env node\nif(process.argv.includes("--version")) { console.log("pg_dump (PostgreSQL) 17"); process.exit(0); }\nprocess.stdout.write(' + JSON.stringify(dataSql) + ');\n', { mode: 0o700 });
    const blocked = run(dev, { PG_DUMP_BIN: executable });
    assert.equal(blocked.status, 1);
    assert.match(blocked.stderr, /Table data found in schema-only output/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('mock pg_dump writes schema-only artifact without leaking credentials to argv', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'canonical-schema-'));
  const executable = path.join(dir, 'pg_dump');
  const marker = path.join(dir, 'invocation.json');
  const sql = mockDump();
  fs.writeFileSync(executable, '#!/usr/bin/env node\n' +
    'const fs=require("node:fs");\n' +
    'if(process.argv.includes("--version")) { console.log("pg_dump (PostgreSQL) 17"); process.exit(0); }\n' +
    'fs.writeFileSync(process.env.TEST_DUMP_MARKER, JSON.stringify({args:process.argv.slice(2),host:process.env.PGHOST,hostaddr:process.env.PGHOSTADDR||null,service:process.env.PGSERVICE||null,serviceFile:process.env.PGSERVICEFILE||null,options:process.env.PGOPTIONS,hasPassword:!!process.env.PGPASSWORD}));\n' +
    'process.stdout.write(' + JSON.stringify(sql) + ');\n',
    { mode: 0o700 });
  try {
    const r = run(dev, { PG_DUMP_BIN: executable, TEST_DUMP_MARKER: marker, PGHOSTADDR: "203.0.113.8", PGSERVICE: "redirect", PGSERVICEFILE: "/tmp/untrusted-service", PGOPTIONS: "-c search_path=untrusted" });
    assert.equal(r.status, 0, r.stderr);
    const invocation = JSON.parse(fs.readFileSync(marker, 'utf8'));
    assert.equal(invocation.host, 'db.gppwltrifgfxrkzvvxoe.supabase.co');
    assert.equal(invocation.hasPassword, true);
    assert.equal(invocation.hostaddr, null);
    assert.equal(invocation.service, null);
    assert.equal(invocation.serviceFile, null);
    assert.equal(invocation.options, '-c default_transaction_read_only=on');
    assert.ok(invocation.args.includes('--schema-only'));
    assert.ok(!invocation.args.includes('--no-privileges'));
    assert.equal(JSON.parse(r.stdout).aclIncluded, true);
    assert.equal(JSON.parse(r.stdout).managedFoundationIncluded, false);
    assert.ok(!invocation.args.some(arg => arg.includes('dummy-password')));
    assert.equal(JSON.parse(r.stdout).dataIncluded, false);
    const artifact = path.resolve(__dirname, '../.release-local/development-application-schema-only.sql');
    const written = fs.readFileSync(artifact, 'utf8');
    assert.equal(written, buildApplicationBootstrap(sql));
    assert.doesNotMatch(written, /CREATE SCHEMA "public"/);
    assert.doesNotMatch(written, /FOR ROLE "supabase_admin"/);
    assert.match(written, /FOR ROLE "postgres"/);
    fs.unlinkSync(artifact);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('application bootstrap preserves application ACLs and excludes managed foundation sections', () => {
  const artifact = buildApplicationBootstrap(mockDump());
  assert.match(artifact, /CREATE SCHEMA "platform"/);
  assert.match(artifact, /GRANT USAGE ON SCHEMA "platform"/);
  assert.match(artifact, /FOR ROLE "postgres"/);
  assert.doesNotMatch(artifact, /CREATE SCHEMA "public"/);
  assert.doesNotMatch(artifact, /FOR ROLE "supabase_admin"/);
  assert.match(artifact, /^\\unrestrict mock-token/m);
});

test('cutover contract is one outer transaction with fail-closed guards', () => {
  const root = path.resolve(__dirname, '..');
  const seed = fs.readFileSync(path.join(root, 'tools/production-release/canonical-system-catalog-seed.sql'), 'utf8');
  const preparation = fs.readFileSync(path.join(root, 'tools/production-release/prepare-canonical-application-replacement.sql'), 'utf8');
  const authIntegration = fs.readFileSync(path.join(root, 'tools/production-release/restore-canonical-managed-auth-integration.sql'), 'utf8');
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/execute-zero-data-production-clean-cutover.yml'), 'utf8');
  assert.doesNotMatch(seed, /^\s*(?:BEGIN|COMMIT|ROLLBACK)\s*;/im);
  assert.match(preparation, /CUTOVER_OPERATIONAL_DATA_PRESENT/);
  assert.match(preparation, /destructive_replacement_scope constant text := 'ALL_APPLICATION_DATA'/);
  assert.match(preparation, /n\.nspname IN \('platform','platform_private'\)/);
  assert.match(preparation, /n\.nspname IN \('public','reservations','reservations_private'\)/);
  assert.match(preparation, /CUTOVER_REPLACEABLE_PLATFORM_STATE_AUTHORIZED/);
  assert.match(preparation, /CUTOVER_ALL_APPLICATION_DATA_DESTRUCTION_AUTHORIZED/);
  assert.match(preparation, /CUTOVER_MANAGED_DEPENDENCY_BLOCKED/);
  assert.match(preparation, /CUTOVER_CANONICAL_AUTH_INTEGRATION_BLOCKED/);
  assert.match(preparation, /trigger_definition\.tgtype<>5/);
  assert.ok(preparation.indexOf('CUTOVER_CANONICAL_AUTH_INTEGRATION_DETACHED') < preparation.indexOf('CUTOVER_MANAGED_DEPENDENCY_BLOCKED'));
  assert.match(authIntegration, /CREATE TRIGGER auth_users_create_profile/);
  assert.match(authIntegration, /CREATE TRIGGER platform_auth_user_provisioned/);
  assert.match(authIntegration, /CANONICAL_AUTH_INTEGRATION_PASS/);
  assert.match(authIntegration, /CANONICAL_AUTH_INTEGRATION_UNEXPECTED_TRIGGER/);
  assert.match(preparation, /SUPABASE_MANAGED_AUTH_USERS_INTEGRATION_PRIVILEGES_MISSING/);
  assert.match(preparation, /has_table_privilege\(current_user,'auth\.users','TRIGGER'\)/);
  assert.doesNotMatch(preparation, /^\s*(?:DELETE\s+FROM|TRUNCATE)\b/im);
  assert.match(preparation, /DROP %s IF EXISTS %I\.%I CASCADE/);
  assert.match(preparation, /ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public[\s\S]*REVOKE ALL ON FUNCTIONS FROM postgres,anon,authenticated,service_role/);
  assert.doesNotMatch(preparation, /ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin/);
  assert.doesNotMatch(preparation, /^\s*DROP\s+SCHEMA\s+(?:IF\s+EXISTS\s+)?"?(?:auth|storage|realtime|extensions)"?/im);
  assert.doesNotMatch(preparation, /^\s*DROP\s+SCHEMA\s+(?:IF\s+EXISTS\s+)?"?public"?/im);
  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /^\s*push\s*:/m);
  assert.match(workflow, /echo 'BEGIN;'/);
  assert.match(workflow, /echo 'COMMIT;'/);
  assert.ok(workflow.indexOf('restore-canonical-managed-auth-integration.sql') < workflow.indexOf('canonical-system-catalog-seed.sql'));
});

test('disposable rehearsal covers old platform state and operational business data', () => {
  const rehearsal = fs.readFileSync(path.resolve(__dirname, '../tools/production-release/rehearse-clean-bootstrap.sh'), 'utf8');
  assert.match(rehearsal, /CREATE TABLE platform\.audit_events/);
  assert.match(rehearsal, /CREATE TABLE platform\.roles/);
  assert.match(rehearsal, /CREATE TABLE platform\.permissions/);
  assert.match(rehearsal, /CREATE TABLE platform\.role_permissions/);
  assert.match(rehearsal, /CREATE TABLE public\.legacy_conference_operational_data/);
  assert.match(rehearsal, /legacy_conference_operational_data \(id bigint GENERATED ALWAYS AS IDENTITY/);
  assert.match(rehearsal, /ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS/);
  assert.match(rehearsal, /CREATE TABLE reservations\.legacy_bookings/);
  assert.match(rehearsal, /CREATE TRIGGER auth_users_create_profile AFTER INSERT ON auth\.users/);
  assert.match(rehearsal, /CREATE TRIGGER platform_auth_user_provisioned AFTER INSERT ON auth\.users/);
  assert.ok(rehearsal.indexOf('legacy_conference_operational_data') < rehearsal.indexOf('prepare-canonical-application-replacement.sql'));
});

test('zero-data structural parity is pinned to the canonical family booking read model', () => {
  const parity = fs.readFileSync(path.resolve(__dirname, '../tools/production-release/assert-canonical-structural-parity.sql'), 'utf8');
  const familyReadModel = fs.readFileSync(path.resolve(__dirname, '../supabase/migrations/20261128134453_canonical_family_booking_read_model.sql'), 'utf8');
  assert.match(parity, /\('functions',324::bigint,'86026bbc9feefb74c39aa90eecb61ef3'\)/);
  assert.match(familyReadModel, /reservations_private\.booking_family_context/);
  assert.match(familyReadModel, /child_paid/);
  assert.match(familyReadModel, /child_dependent/);
});

test('family booking read model and service-sector catalog migrations preserve production records', () => {
  const family = fs.readFileSync(path.resolve(__dirname, '../supabase/migrations/20261128134453_canonical_family_booking_read_model.sql'), 'utf8');
  const sectors = fs.readFileSync(path.resolve(__dirname, '../supabase/migrations/20261128161000_canonical_service_sector_catalog_update.sql'), 'utf8');
  assert.match(family, /booking_family_context/);
  assert.match(sectors, /house-of-prayer/);
  assert.doesNotMatch(sectors, /\\b(drop table|truncate|delete from|drop schema)\\b/i);
  assert.match(sectors, /alter table reservations\.public_registration_requests/);
  assert.match(sectors, /alter table reservations\.public_registration_request_members/);
});


test('family adult-phone cutover preserves existing Production request and member rows',()=>{
 const migration=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261128173500_public_registration_adult_phone_contract.sql'),'utf8');
 const initial=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261128174500_public_registration_initial_adult_phone_validation.sql'),'utf8');
 assert.match(migration,/add constraint public_registration_request_members_adult_phone_check[\s\S]*?not valid/);
 assert.match(migration,/PUBLIC_REGISTRATION_ADULT_PHONE_REQUIRED/);
 assert.match(migration,/PUBLIC_REGISTRATION_ADULT_PHONE_MUST_BE_INDEPENDENT/);
 assert.match(initial,/PUBLIC_REGISTRATION_ADULT_PHONE_REQUIRED/);
 assert.doesNotMatch(migration,/\\b(?:delete\\s+from|truncate\\s+(?:table\\s+)?)\\s+reservations\\.public_registration_request_members\\b/i);
 assert.doesNotMatch(initial,/\\b(?:delete\\s+from|truncate\\s+(?:table\\s+)?)\\s+reservations\\.public_registration_requests\\b/i);
});
