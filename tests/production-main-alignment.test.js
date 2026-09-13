'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const read = (path) => fs.readFileSync(path, 'utf8');

const operation = read('supabase/functions/platform-device-operation/index.ts');
const phase1c = read('supabase/migrations/20260909120555_production_validated_phase1c_variable_disambiguation.sql');
const warehouseHierarchy = read('supabase/migrations/20260909210000_warehouse_item_unit_hierarchy.sql');
const sessionRetention = read('supabase/migrations/20260909220000_device_session_finalization_audit_retention.sql');
const backmerge = read('.github/workflows/backmerge-main-to-develop.yml');

test('production operation diagnostics are represented in source', () => {
  assert.match(operation, /const requestId=crypto\.randomUUID\(\)/);
  assert.match(operation, /stage='origin_validation'/);
  assert.match(operation, /stage='authentication'/);
  assert.match(operation, /stage='request_validation'/);
  assert.match(operation, /stage='session_validation'/);
  assert.match(operation, /stage='operation_dispatch'/);
  assert.match(operation, /diagnostic=\{module:requestedModule\|\|null,operation:requestedOperation\|\|null,stage,sqlstate,applicationCode,requestId,timestamp:/);
  assert.match(operation, /return json\(safe\.status,\{ok:false,error:\{code:safe\.code\},diagnostic\}\)/);
  assert.doesNotMatch(operation, /module!=='conference'&&module!=='warehouse'&&module!=='reservations'/);
});

test('live Phase1C variable-disambiguation migration is preserved as source', () => {
  assert.match(phase1c, /create or replace function platform_private\.validated_phase1c_device_authorization/);
  assert.match(phase1c, /PLATFORM_DEVICE_SESSION_DISPATCH/);
  assert.match(phase1c, /join platform\.device_key_bindings binding/);
  assert.match(phase1c, /join platform\.user_device_authorizations uda/);
  assert.match(phase1c, /profile\.account_status='approved'/);
});

test('latest production warehouse and device-session migrations remain represented', () => {
  assert.match(warehouseHierarchy, /validate_and_derive_item_unit_graph/);
  assert.match(warehouseHierarchy, /reference_unit_id uuid/);
  assert.match(warehouseHierarchy, /warehouse\.upsert_item_units/);
  assert.match(sessionRetention, /create or replace function platform\.complete_device_session/);
  assert.match(sessionRetention, /insert into platform_private\.device_session_audit/);
  assert.match(sessionRetention, /'PLATFORM_DEVICE_SESSION_ESTABLISH'/);
});

test('main backmerge is PR-only and never auto-merges', () => {
  assert.match(backmerge, /branches:\s*\[main\]/);
  assert.match(backmerge, /base=develop/);
  assert.match(backmerge, /head=main/);
  assert.match(backmerge, /gh pr create/);
  assert.doesNotMatch(backmerge, /gh pr merge|auto-merge|merge --/i);
});
