'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const contractPath = path.join(root, 'modules/reservations/reservations-contract.json');
const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
const runtime = fs.readFileSync(path.join(root, 'modules/reservations/reservations-module.js'), 'utf8');
const policy = JSON.parse(fs.readFileSync(path.join(root, 'tools/reservations-artifact-policy.json'), 'utf8'));
const digest = (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const requireBehavior = (name) => assert.ok(contract.requiredBehaviors.includes(name), name);

test('Reservations artifact is source-owned and contract-bound', () => {
  assert.equal(contract.schemaVersion, 1);
  assert.equal(contract.ownership, 'reservation-management-system');
  assert.equal(contract.contractVersion, 'reservations-canonical-lifecycle-profile-v1');
  assert.equal(digest(contractPath), policy.currentRuntime.contract.sha256);
  assert.equal(policy.currentRuntime.contract.version, contract.contractVersion);
});

test('canonical identity and profile behavior is source-owned', () => {
  requireBehavior('canonical-person-profile');
  requireBehavior('manual-person-identity-resolution');
  requireBehavior('canonical-dob-gender');
  requireBehavior('newborn-age-zero');
  assert.ok(runtime.includes('p_date_of_birth'));
  assert.ok(runtime.includes('p_person_update_revision'));
  assert.ok(runtime.includes('save-local'));
  assert.ok(runtime.includes('update-canonical'));
  assert.doesNotMatch(runtime, /window\.prompt/);
});

test('lifecycle, apology, refund, and financial history are source-owned', () => {
  for (const name of ['active-apologized-deleted-lifecycle','apology-two-option-allocation','dated-partial-refund-disbursement','non-active-operational-readonly','active-only-operational-finance','historical-financial-reporting']) requireBehavior(name);
  assert.ok(runtime.includes('disburse_refund'));
  assert.ok(runtime.includes('لا يُرد حاليًا'));
  assert.ok(runtime.includes('محتفظ به حاليًا'));
  assert.ok(runtime.includes('عمليات الرد السابقة'));
  assert.ok(runtime.includes('مراجعة / رد المبلغ'));
});

test('shared invalidation and independent operational actions are source-owned', () => {
  requireBehavior('shared-runtime-invalidation');
  requireBehavior('independent-payment-and-review-actions');
  assert.ok(runtime.includes('إتمام المراجعة'));
  assert.ok(runtime.includes('تسجيل دفعة'));
});

test('Platform database keeps canonical cancellation and identity guards', () => {
  const cancellation = fs.readFileSync(path.join(root,'supabase/migrations/20261105134026_reservations_booking_cancellation_financial_settlement.sql'),'utf8');
  const refund = fs.readFileSync(path.join(root,'supabase/migrations/20261106070000_reservations_disburse_refund_writer.sql'),'utf8');
  const identity = fs.readFileSync(path.join(root,'supabase/migrations/20261104104306_reservations_manual_person_identity_resolution.sql'),'utf8');
  assert.match(cancellation, /lifecycle_status in \('active','apologized'\)/);
  assert.match(cancellation, /RESERVATIONS_BOOKING_ALREADY_APOLOGIZED/);
  assert.match(refund, /pending_refund_amount=greatest\(pending_refund_amount-amount,0\)/);
  assert.match(refund, /refunded_amount=refunded_amount\+amount/);
  assert.match(identity, /identity_resolution/i);
});
