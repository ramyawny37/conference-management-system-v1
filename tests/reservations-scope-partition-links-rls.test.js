'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration=fs.readFileSync(
  path.join(root,'supabase/migrations/20261010130000_reservations_scope_partition_links_rls.sql'),
  'utf8'
);

test('scope partition link ledger is RLS protected and remains non-public',()=>{
  assert.match(migration,/alter table reservations\.scope_partition_links enable row level security;/i);
  assert.match(migration,/revoke all on table reservations\.scope_partition_links\s+from public, anon, authenticated, service_role;/i);
  assert.doesNotMatch(migration,/create\s+policy/i);
  assert.doesNotMatch(migration,/grant\s+/i);
});
