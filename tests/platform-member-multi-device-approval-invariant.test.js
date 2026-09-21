'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync(
  'supabase/migrations/20260921121500_member_multi_device_approval_invariant_correction.sql',
  'utf8'
);
const fn=migration.match(/create or replace function platform_private\.apply_member_device_authorization[\s\S]*?end; \$\$;/i)?.[0]||'';

test('member approval is additive and does not reject an existing approved device',()=>{
  assert.ok(fn);
  assert.doesNotMatch(fn,/p_action='approve'\s+and\s+exists\s*\(select 1 from platform\.user_device_authorizations approved/i);
  assert.match(fn,/p_action='approve'[\s\S]*?profile\.account_status='approved'/i);
  assert.match(fn,/binding\.device_authorization_id=target\.id/i);
  assert.match(fn,/binding\.lifecycle_status='active'/i);
  assert.match(fn,/binding\.revoked_at is null/i);
  assert.match(fn,/binding\.retired_at is null/i);
});

test('pending target, active canonical device and account guards remain fail closed',()=>{
  assert.match(fn,/device\.lifecycle_status='active' and device\.retired_at is null[\s\S]*?device\.compromised_at is null/i);
  assert.match(fn,/target\.status<>'pending' or target\.revoked_at is not null/i);
  assert.match(fn,/PENDING_UNREVOKED_DEVICE_REQUIRED/i);
  assert.match(fn,/DEVICE_APPROVAL_PRECONDITION_INVALID/i);
  assert.doesNotMatch(fn,/public\.user_device_authorizations/i);
});

test('revoke sole-device protection and explicit replacement semantics are preserved',()=>{
  assert.match(fn,/DEVICE_REVOCATION_REPLACEMENT_REQUIRED/i);
  assert.match(fn,/p_action='replace'[\s\S]*?replacement\.status is distinct from 'pending'/i);
  assert.match(fn,/DEVICE_REPLACEMENT_PRECONDITION_INVALID/i);
  assert.match(fn,/count\(\*\)[\s\S]*?approved\.status='approved'[\s\S]*?<>1/i);
});

test('operation idempotency, audit and canonical operation ledger remain intact',()=>{
  assert.match(fn,/where operation\.operation_id=p_operation_id/i);
  assert.match(fn,/return existing\.stored_result/i);
  assert.match(fn,/DEVICE_ADMINISTRATION_OPERATION_MISMATCH/i);
  assert.match(fn,/insert into public\.device_authorization_audit_log/i);
  assert.match(fn,/insert into public\.device_authorization_admin_operations/i);
});

test('migration does not mutate rows outside the canonical function definition',()=>{
  const outside=migration.replace(fn,'');
  assert.doesNotMatch(outside,/\b(?:insert|update|delete)\s+(?:into\s+|from\s+)?platform\.(?:user_device_authorizations|devices|device_key_bindings)/i);
  assert.match(outside,/revoke all on function platform_private\.apply_member_device_authorization/i);
});
