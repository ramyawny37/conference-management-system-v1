'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const read = path => fs.readFileSync(path, 'utf8');
const contract = read('docs/canonical-family-accommodation-cutover-contract.md');
const migrations = [
  'supabase/migrations/20261026111500_reject_direct_linked_child_stay_moves.sql',
  'supabase/migrations/20261026162000_guardian_move_cascades_children.sql',
  'supabase/migrations/20261026170000_guardian_replacement_removes_housed_children.sql',
  'supabase/migrations/20261027150000_atomic_guardian_child_accommodation.sql'
];

test('family accommodation contract requires independently bedded child stays', () => {
  assert.match(contract, /independently bedded child may occupy any eligible room/);
  assert.match(contract, /shared-bed child consumes no bed/);
  assert.match(contract, /lease for \*\*every\*\* affected room/);
});

test('historical migrations remain immutable; cutover uses a new forward-only migration', () => {
  for (const file of migrations) assert.ok(fs.existsSync(file), file);
  const files = fs.readdirSync('supabase/migrations');
  const candidates = files.filter(name => /^\d+_.*family.*(cutover|lifecycle).*\.sql$/.test(name));
  assert.ok(candidates.length > 0, 'RED: no forward-only family lifecycle cutover migration yet');
});

test('new migration replaces legacy child inheritance and guardian cascade triggers', () => {
  const files = fs.readdirSync('supabase/migrations')
    .filter(name => /^\d+_.*family.*(cutover|lifecycle).*\.sql$/.test(name));
  const sql = files.map(name => read('supabase/migrations/' + name)).join('\n');
  assert.match(sql, /conference_accommodation_linked_child_guardian/);
  assert.match(sql, /conference_accommodation_sync_guardian_linked_children/);
  assert.match(sql, /move_conference_accommodation/);
  assert.match(sql, /replace_conference_accommodation/);
  assert.match(sql, /remove_conference_accommodation/);
});

test('family draft cutover has explicit multi-room lease and idempotency contract', () => {
  const files = fs.readdirSync('supabase/migrations')
    .filter(name => /^\d+_.*family.*(cutover|lifecycle).*\.sql$/.test(name));
  const sql = files.map(name => read('supabase/migrations/' + name)).join('\n');
  assert.match(sql, /operation_id|p_operation_id/i);
  assert.match(sql, /lease|lock/i);
  assert.match(sql, /room_id|p_room/i);
});
