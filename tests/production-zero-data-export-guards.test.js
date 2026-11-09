'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const script = path.resolve(__dirname, '../tools/production-release/export-development-schema-only.cjs');
const dev = 'postgresql://postgres:dummy-password@db.gppwltrifgfxrkzvvxoe.supabase.co:5432/postgres';
const prod = 'postgresql://postgres:dummy-password@db.mpezfbvcdfxpgflehuot.supabase.co:5432/postgres';
const run = (url, overrides={}) => spawnSync(process.execPath, [script], {
  encoding: 'utf8',
  env: { ...process.env, DEVELOPMENT_DATABASE_URL: url, ...overrides },
});
test('rejects Production connection before launching pg_dump', () => {
  const r = run(prod);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /Only the explicit Development project is allowed/);
  assert.doesNotMatch(r.stderr, /dummy-password/);
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

test('mock pg_dump writes schema-only artifact without leaking credentials to argv', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'canonical-schema-'));
  const executable = path.join(dir, 'pg_dump');
  const marker = path.join(dir, 'invocation.json');
  const sql = '-- PostgreSQL database dump\\n' +
    'CREATE SCHEMA "platform";\\n' +
    'CREATE TABLE "platform"."example" ("id" integer);\\n' +
    '-- schema only\\n'.repeat(45);
  fs.writeFileSync(executable, '#!/usr/bin/env node\\n' +
    'const fs=require("node:fs");\\n' +
    'if(process.argv.includes("--version")) { console.log("pg_dump (PostgreSQL) 17"); process.exit(0); }\\n' +
    'fs.writeFileSync(process.env.TEST_DUMP_MARKER, JSON.stringify({args:process.argv.slice(2),host:process.env.PGHOST,hasPassword:!!process.env.PGPASSWORD}));\\n' +
    'process.stdout.write(' + JSON.stringify(sql) + ');\\n',
    { mode: 0o700 });
  try {
    const r = run(dev, { PG_DUMP_BIN: executable, TEST_DUMP_MARKER: marker });
    assert.equal(r.status, 0, r.stderr);
    const invocation = JSON.parse(fs.readFileSync(marker, 'utf8'));
    assert.equal(invocation.host, 'db.gppwltrifgfxrkzvvxoe.supabase.co');
    assert.equal(invocation.hasPassword, true);
    assert.ok(invocation.args.includes('--schema-only'));
    assert.ok(invocation.args.includes('--no-privileges'));
    assert.ok(!invocation.args.some(arg => arg.includes('dummy-password')));
    assert.equal(JSON.parse(r.stdout).dataIncluded, false);
    const artifact = path.resolve(__dirname, '../.release-local/development-application-schema-only.sql');
    assert.equal(fs.readFileSync(artifact, 'utf8'), sql);
    fs.unlinkSync(artifact);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
