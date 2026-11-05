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

test.todo('unified runtime dialog awaits reconciliation of the canonical platform bundle with its source repository');
