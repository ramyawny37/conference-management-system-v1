'use strict';

const assert=require('assert');
const fs=require('fs');
const path=require('path');

const root=path.join(__dirname,'..');
const migration=fs.readFileSync(path.join(
  root,'supabase/migrations/20260924223000_reservations_participant_booking_type_edit.sql'
),'utf8');
const bookingEditStart=migration.lastIndexOf("if p_operation='update_participant_booking'");
const bookingEditEnd=migration.indexOf("if p_operation='delete_booking'",bookingEditStart);
const bookingEditBranch=migration.slice(bookingEditStart,bookingEditEnd);

assert.match(migration,
  /'p_expected_revision','p_booking_type_id'/,
  'the protected mutation contract requires the selected booking type');
assert.match(migration,
  /v_booking\.revision<>\(p_args->>'p_expected_revision'\)::bigint/,
  'the booking revision remains an optimistic concurrency boundary');
assert.match(migration,
  /id=\(p_args->>'p_booking_type_id'\)::uuid[\s\S]*event_id=v_booking\.event_id[\s\S]*scope_partition_id=v_booking\.scope_partition_id/,
  'booking type selection is scoped to the booking event and partition');
assert.match(migration,
  /v_type\.id<>v_booking\.booking_type_id and not v_type\.active/,
  'only the current historical inactive type may be retained');
assert.match(migration,
  /booking_type_name_snapshot=v_type\.name,[\s\S]*price_snapshot=v_type\.price/,
  'commercial snapshots come from the authoritative booking type');
assert.doesNotMatch(bookingEditBranch,/update\s+reservations\.payments/i,
  'booking-type edits never rewrite payment records');
assert.match(migration,/reservations\.booking\.update/,
  'the existing booking-update permission remains authoritative');
assert.match(migration,/DEVICE_SESSION_INVALID/,
  'the device-session boundary is preserved');
assert.match(migration,
  /revoke all on function[\s\S]*platform\.execute_device_operation[\s\S]*from public,anon,authenticated/,
  'the protected dispatcher is not browser executable');
assert.match(migration,
  /platform\.execute_device_operation_pre_generic_permission_resource_administration/,
  'the canonical dispatcher retains the latest pre-feature operation chain');
assert.doesNotMatch(migration,/before_participant_booking_type_edit|pg_get_functiondef|execute\s+replace/i,
  'the unapplied migration defines canonical functions directly without wrapper or textual replacement');
assert.equal((migration.match(/create or replace function platform\.execute_device_operation/g)||[]).length,1,
  'the canonical Platform dispatcher has one final definition');
assert.equal((migration.match(/create or replace function reservations_private\.mutate_scoped/g)||[]).length,1,
  'the canonical Reservations mutation has one complete final definition');

console.log('reservations participant booking-type edit tests passed');
