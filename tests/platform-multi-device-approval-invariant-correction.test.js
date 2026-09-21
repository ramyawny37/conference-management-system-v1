'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migration = fs.readFileSync(
  'supabase/migrations/20260921100500_platform_multi_device_approval_invariant_correction.sql',
  'utf8'
);

const canonical = fs.readFileSync(
  'supabase/migrations/20260920221928_canonical_platform_device_authority_reconciliation.sql',
  'utf8'
);

const staleSingleDeviceGuard = /if p_action='approve' and exists\(select 1 from platform\.user_device_authorizations approved[\s\S]*?raise exception 'DEVICE_APPROVAL_PRECONDITION_INVALID' using errcode='42501';\s*end if;/;

function functionBody(sql) {
  const marker = 'create or replace function platform_private.apply_member_device_authorization(';
  const start = sql.toLowerCase().indexOf(marker);
  assert.notEqual(start, -1, 'canonical member-device authorization function must exist');
  const tail = sql.slice(start);
  const end = tail.indexOf('end; $$;');
  assert.notEqual(end, -1, 'member-device authorization function must terminate');
  return tail.slice(0, end + 'end; $$;'.length);
}

test('multi-device correction removes only the stale existing-approved-device approval guard', () => {
  const oldBody = functionBody(canonical);
  const newBody = functionBody(migration);
  assert.match(oldBody, staleSingleDeviceGuard);
  assert.doesNotMatch(newBody, staleSingleDeviceGuard);

  const expected = oldBody.replace(staleSingleDeviceGuard, '').replace(/\n{3,}/g, '\n\n').trim();
  const actual = newBody.replace(/\n{3,}/g, '\n\n').trim();
  assert.equal(actual, expected);
});

test('approval still requires pending target, approved account, and active cryptographic binding', () => {
  const body = functionBody(migration);
  assert.match(body, /p_action in \('approve','reject'\).*target\.status<>'pending'.*target\.revoked_at is not null/s);
  assert.match(body, /profile\.user_id=p_target_user_id and profile\.account_status='approved'/);
  assert.match(body, /binding\.device_authorization_id=target\.id/);
  assert.match(body, /binding\.lifecycle_status='active' and binding\.revoked_at is null/);
  assert.match(body, /binding\.retired_at is null/);
});

test('revoke, replace, idempotency, audit, and operation ledger guards remain canonical', () => {
  const body = functionBody(migration);
  assert.match(body, /DEVICE_REVOCATION_REPLACEMENT_REQUIRED/);
  assert.match(body, /DEVICE_REPLACEMENT_PRECONDITION_INVALID/);
  assert.match(body, /existing\.action=operation_name then return existing\.stored_result/);
  assert.match(body, /insert into public\.device_authorization_audit_log/);
  assert.match(body, /insert into public\.device_authorization_admin_operations/);
  assert.match(body, /public\.require_device_authorization_manager/);
});

test('correction does not introduce legacy authorization authority or a parallel approval path', () => {
  assert.doesNotMatch(migration, /public\.user_device_authorizations/);
  assert.doesNotMatch(migration, /register_or_refresh_current_device|request_current_device_authorization/);
  assert.equal((migration.match(/create or replace function platform_private\.apply_member_device_authorization/g) || []).length, 1);
  assert.equal((migration.match(/create or replace function/g) || []).length, 1);
});
