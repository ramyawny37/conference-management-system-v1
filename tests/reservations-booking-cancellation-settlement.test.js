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

test('legacy credit writer is retired and cannot reopen an account-wide financial path',()=>{
  const retirement=fs.readFileSync(path.join(root,'supabase/migrations/20261106040000_reservations_retire_unused_credit_writer.sql'),'utf8');
  assert.match(retirement,/LEGACY_CREDIT_RETIREMENT_HAS_DATA/);
  assert.match(retirement,/insert into reservations\.person_credit_accounts/);
  assert.match(retirement,/execute left\(definition,start_at-1\)\|\|substr\(definition,end_at\)/);
  assert.doesNotMatch(runtime,/outstandingCredits|person_credit_accounts|person_credit_entries/);
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

const paymentLockMigration=fs.readFileSync(path.join(root,'supabase/migrations/20261105220000_reservations_payment_booking_lock.sql'),'utf8');
test('payment recording locks booking before testing apology state',()=>{
  assert.match(paymentLockMigration,/for update; if not found/);
  assert.match(paymentLockMigration,/v_booking\.lifecycle_status/);
  assert.match(paymentLockMigration,/PAYMENT_BOOKING_LOCK_CONTRACT_DRIFT/);
});

const voidPaymentLockMigration=fs.readFileSync(path.join(root,'supabase/migrations/20261105221000_reservations_payment_void_booking_lock.sql'),'utf8');
test('payment void locks booking before mutating payment history',()=>{
  assert.match(voidPaymentLockMigration,/for update/);
  assert.match(voidPaymentLockMigration,/v_booking\.lifecycle_status/);
  assert.match(voidPaymentLockMigration,/VOID_PAYMENT_LOCK_CONTRACT_DRIFT/);
});

const creditDestinationGuard=fs.readFileSync(path.join(root,'supabase/migrations/20261106000000_reservations_credit_destination_fail_closed.sql'),'utf8');
test('credit redemption cannot debit a balance without a destination payment',()=>{
  assert.match(creditDestinationGuard,/RESERVATIONS_CREDIT_DESTINATION_REQUIRED/);
  assert.match(creditDestinationGuard,/CREDIT_REDEMPTION_CONTRACT_DRIFT/);
});

const eventCreditGuard=fs.readFileSync(path.join(root,'supabase/migrations/20261106010000_reservations_event_credit_issuance_guard.sql'),'utf8');
test('cancellation cannot pool credit across events using partition-only accounts',()=>{
  assert.match(eventCreditGuard,/RESERVATIONS_EVENT_CREDIT_ISOLATION_REQUIRED/);
  assert.match(eventCreditGuard,/CANCELLATION_CREDIT_ALLOCATION_CONTRACT_DRIFT/);
});

const eventCreditSchema=fs.readFileSync(path.join(root,'supabase/migrations/20261106020000_reservations_event_scoped_credit_accounts.sql'),'utf8');
test('credit account identity and ledger entries are event-scoped',()=>{
  assert.match(eventCreditSchema,/primary key\(scope_partition_id,event_id,person_id\)/);
  assert.match(eventCreditSchema,/foreign key\(scope_partition_id,event_id,person_id\)/);
  assert.match(eventCreditSchema,/EVENT_CREDIT_MIGRATION_REQUIRES_RECONCILIATION/);
});

const refundDisbursementGuard=fs.readFileSync(path.join(root,'supabase/migrations/20261106030000_reservations_refund_disbursement_guard.sql'),'utf8');
test('actual refund requires a recorded disbursement instead of apology-only allocation',()=>{
  assert.match(refundDisbursementGuard,/RESERVATIONS_REFUND_DISBURSEMENT_REQUIRED/);
  assert.match(refundDisbursementGuard,/CANCELLATION_CONTRACT_DRIFT/);
});

const legacyCreditRetirement=fs.readFileSync(path.join(root,'supabase/migrations/20261106040000_reservations_retire_unused_credit_writer.sql'),'utf8');
test('canonical cancellation retires the unused credit wallet writer only when no credit data exists',()=>{
  assert.match(legacyCreditRetirement,/LEGACY_CREDIT_RETIREMENT_HAS_DATA/);
  assert.match(legacyCreditRetirement,/insert into reservations\.person_credit_accounts/);
  assert.match(legacyCreditRetirement,/LEGACY_CREDIT_WRITER_BOUNDARY_DRIFT/);
});

const settlementEventJoin=fs.readFileSync(path.join(root,'supabase/migrations/20261106050000_reservations_settlement_credit_event_join.sql'),'utf8');
test('booking settlement lookup cannot use credit account from another event',()=>{
  assert.match(settlementEventJoin,/a\.event_id=credit_booking\.event_id/);
  assert.match(settlementEventJoin,/BOOKING_SETTLEMENT_EVENT_JOIN_DRIFT/);
});

const refundLedger=fs.readFileSync(path.join(root,'supabase/migrations/20261106060000_reservations_refund_disbursement_ledger.sql'),'utf8');
const refundLedgerIntegrity=fs.readFileSync(path.join(root,'supabase/migrations/20261106061000_reservations_refund_settlement_booking_integrity.sql'),'utf8');
test('refund disbursement is dated, event-bound and cannot reference another booking settlement',()=>{
  assert.match(refundLedger,/disbursed_on date not null/);
  assert.match(refundLedger,/refund_disbursements_event_booking_fk/);
  assert.match(refundLedger,/enable row level security/);
  assert.match(refundLedgerIntegrity,/refund_disbursements_settlement_booking_fk/);
  assert.match(refundLedgerIntegrity,/foreign key\(scope_partition_id,booking_id,settlement_id\)/);
});
