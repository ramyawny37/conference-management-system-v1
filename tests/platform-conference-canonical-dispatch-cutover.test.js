'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const sql=fs.readFileSync(
  path.join(root,'supabase/migrations/20261010140000_platform_conference_canonical_dispatch_cutover.sql'),
  'utf8'
);

test('unified platform dispatcher cuts Conference directly to canonical dispatcher',()=>{
  assert.match(sql,/if p_module=\\'conference\\' then/i);
  assert.match(sql,/return platform\.execute_conference_device_operation\(/i);
  assert.match(sql,/PLATFORM_DEVICE_OPERATION_CUTOVER_PREDECESSOR_MISMATCH/);
  assert.doesNotMatch(sql,/execute_conference_device_operation_phase1c_core\(/i);
  assert.doesNotMatch(sql,/drop\s+function/i);
});

test('cutover does not rewrite Warehouse or Reservations routing in this migration',()=>{
  assert.doesNotMatch(sql,/p_module=\\'warehouse\\' then/i);
  assert.match(sql,/if p_module=\\'reservations\\'/i);
});
