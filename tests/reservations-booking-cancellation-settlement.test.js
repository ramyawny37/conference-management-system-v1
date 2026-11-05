'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261105134026_reservations_booking_cancellation_financial_settlement.sql'),'utf8');
const creditCorrection=fs.readFileSync(path.join(root,'supabase/migrations/20261105135209_reservations_credit_redemption_source_allocation.sql'),'utf8');
const runtime=fs.readFileSync(path.join(root,'modules/reservations/reservations-module.js'),'utf8');

test('booking apology owns one lifecycle and preserves immutable payments',()=>{
  assert.match(migration,/lifecycle_status text not null default 'active'/);
  assert.match(migration,/lifecycle_status in \('active','apologized'\)/);
  assert.match(migration,/create table reservations\.booking_cancellation_settlements/);
  assert.doesNotMatch(migration,/delete from reservations\.payments|update reservations\.payments/);
  assert.match(migration,/RESERVATIONS_BOOKING_ALREADY_APOLOGIZED/);
  assert.match(migration,/RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE/);
});

test('settlement allocation is exact, non-negative and distinguishes actual from pending refunds',()=>{
  assert.match(migration,/non_refundable_amount\+refunded_amount\+credit_amount\+pending_refund_amount=collected_amount/);
  for(const column of ['collected_amount','non_refundable_amount','refunded_amount','credit_amount','pending_refund_amount'])
    assert.match(migration,new RegExp(`${column} numeric\\(18,2\\)[^,]*check \\(${column}>=0\\)`));
  assert.match(migration,/actualRefunds/);
  assert.match(migration,/pendingRefunds/);
  assert.match(migration,/netCash/);
});

test('credit ledger is person-scoped, revision-safe and cannot be spent twice',()=>{
  assert.match(migration,/primary key \(scope_partition_id,person_id\)/);
  assert.match(migration,/entry_kind in \('issue','redeem'\)/);
  assert.match(migration,/operation_id uuid not null unique/);
  assert.match(migration,/account\.revision<>\(p_args->>'p_expected_revision'\)::bigint/);
  assert.match(migration,/RESERVATIONS_CREDIT_BALANCE_EXCEEDED/);
  assert.match(creditCorrection,/p_settlement_id/);
  assert.match(creditCorrection,/RESERVATIONS_CREDIT_SOURCE_EXCEEDED/);
  assert.match(creditCorrection,/credit_booking\.event_id=v_event_id/);
});

test('conference apology reuses canonical family, accommodation and transport lifecycle',()=>{
  assert.match(migration,/public\.set_conference_participation_status/);
  assert.match(migration,/changedParticipationIds/);
  assert.match(migration,/RESERVATIONS_CHILD_BOOKING_SETTLEMENT_REQUIRED/);
  assert.doesNotMatch(migration,/cleanup_conference_accommodation_for_participation|cleanup_conference_transport_for_participation/);
});

test('financial tables remain private and mutations retain permission, replay and audit boundaries',()=>{
  assert.match(migration,/reservations\.booking\.cancel/);
  assert.match(migration,/reservations\.payment\.settle/);
  assert.match(migration,/reservations\.credit\.redeem/);
  assert.match(migration,/begin_operation\(operation_id,context,'cancel_booking'/);
  assert.match(migration,/complete_operation\(operation_id,context,'cancel_booking'/);
  assert.match(migration,/reservations_private\.audit/);
  assert.match(migration,/force row level security/g);
  assert.match(migration,/revoke all on reservations\.booking_cancellation_settlements,[\s\S]*from public,anon,authenticated,service_role/);
});

test('active capacity and dashboard values exclude apologized bookings while history remains listable',()=>{
  assert.match(migration,/count\(\*\) into v_count[\s\S]*lifecycle_status=''active''/);
  assert.match(migration,/b\.lifecycle_status=''active''/);
  assert.doesNotMatch(migration,/list_bookings[^;]+lifecycle_status=''active''/);
});

test('outstanding credit report is source-allocated and event-scoped, not account-wide',()=>{
  const corrected=creditCorrection.match(/'''outstandingCredits''',[^\n]+/g)||[];
  assert.ok(corrected.length>=2,'migration must match and replace the old account-wide calculation');
  const replacement=corrected[corrected.length-1];
  assert.match(replacement,/s\.credit_amount-coalesce\(redeemed\.amount,0\)/);
  assert.match(replacement,/entry\.settlement_id=s\.id/);
  assert.match(replacement,/entry\.entry_kind=''redeem''/);
  assert.match(replacement,/credit_booking\.event_id=v_event_id/);
  assert.doesNotMatch(replacement,/sum\(a\.balance\)/);
});

test.todo('unified runtime dialog awaits reconciliation of the canonical platform bundle with its source repository');

const gatewayCreditCutover=fs.readFileSync(path.join(root,'supabase/migrations/20261105210000_reservations_credit_gateway_source_contract.sql'),'utf8');
const childGuardCutover=fs.readFileSync(path.join(root,'supabase/migrations/20261105211000_reservations_guard_all_linked_child_bookings.sql'),'utf8');

test('canonical device dispatcher accepts the credit source required by the scoped writer',()=>{
  assert.match(gatewayCreditCutover,/p_settlement_id/);
  assert.match(gatewayCreditCutover,/CREDIT_GATEWAY_CONTRACT_DRIFT/);
  assert.match(gatewayCreditCutover,/platform\.execute_device_operation/);
  assert.match(creditCorrection,/p_settlement_id/);
});

test('guardian cancellation protects unpaid as well as paid linked child bookings',()=>{
  assert.match(childGuardCutover,/reservations_private\.cancel_booking_scoped/);
  assert.match(childGuardCutover,/join reservations\.payments child_payment/);
  assert.match(childGuardCutover,/CHILD_SETTLEMENT_GUARD_DRIFT/);
  assert.match(migration,/RESERVATIONS_CHILD_BOOKING_SETTLEMENT_REQUIRED/);
});

test('credit redemption is source allocated, but is not yet booked as a payment against another booking',()=>{
  assert.match(creditCorrection,/settlement\.id/);
  assert.doesNotMatch(creditCorrection,/insert into reservations\.payments/);
});

test('apologized booking details cannot offer edits or new payments',()=>{
  assert.match(runtime,/onClick:qe,disabled:xe\|\|m\.lifecycleStatus==="apologized"/);
  assert.match(runtime,/m\.lifecycleStatus!=="apologized"&&l\.jsxs\(Se,\{onClick:\(\)=>\$\(!0\)/);
  assert.match(runtime,/action:m\.lifecycleStatus!=="apologized"\?/);
  assert.match(runtime,/V&&m\.lifecycleStatus!=="apologized"&&l\.jsx\(Jo/);
});

const voidGuardCutover=fs.readFileSync(path.join(root,'supabase/migrations/20261105213000_reservations_apologized_payment_void_guard.sql'),'utf8');
test('post-apology payment history cannot be voided through the canonical SQL writer',()=>{
  assert.match(voidGuardCutover,/resolve_payment_scope/);
  assert.match(voidGuardCutover,/guard_booking\.lifecycle_status<>''active''/);
  assert.match(voidGuardCutover,/RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE/);
  assert.match(runtime,/disabled:m\.lifecycleStatus==="apologized",children:\[l\.jsx\(Gj/);
  assert.match(runtime,/q&&m\.lifecycleStatus!=="apologized"&&l\.jsx\(mb/);
});

const recordPaymentGuardCutover=fs.readFileSync(path.join(root,'supabase/migrations/20261105214000_reservations_payment_record_scope_guard.sql'),'utf8');
test('record-payment immutability check runs after canonical scope authorization',()=>{
  assert.match(recordPaymentGuardCutover,/resolve_booking_scope/);
  assert.match(recordPaymentGuardCutover,/reservations\.payment\.record/);
  assert.match(recordPaymentGuardCutover,/RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE/);
  assert.match(recordPaymentGuardCutover,/RECORD_PAYMENT_GUARD_DRIFT/);
});

// Cancellation lifecycle: booking updates must be rejected after apology at the canonical writer.

const immutableUpdateMigration=fs.readFileSync(path.join(root,'supabase/migrations/20261105215000_reservations_apologized_booking_update_guard.sql'),'utf8');
test('canonical booking update refuses apologized bookings before person changes',()=>{
  assert.match(immutableUpdateMigration,/v_booking\.lifecycle_status/);
  assert.match(immutableUpdateMigration,/RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE/);
  assert.match(immutableUpdateMigration,/BOOKING_UPDATE_CONTRACT_DRIFT/);
});
