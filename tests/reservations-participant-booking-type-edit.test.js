'use strict';

const assert=require('assert');
const fs=require('fs');
const path=require('path');

const root=path.join(__dirname,'..');
const migration=fs.readFileSync(path.join(
  root,'supabase/migrations/20260924223000_reservations_participant_booking_type_edit.sql'
),'utf8');

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
assert.doesNotMatch(migration,/update\s+reservations\.payments/i,
  'booking-type edits never rewrite payment records');
assert.match(migration,/reservations\.booking\.update/,
  'the existing booking-update permission remains authoritative');
assert.match(migration,/DEVICE_SESSION_INVALID/,
  'the device-session boundary is preserved');
assert.match(migration,
  /revoke all on function[\s\S]*platform\.execute_device_operation[\s\S]*from public,anon,authenticated/,
  'the protected dispatcher is not browser executable');

console.log('reservations participant booking-type edit tests passed');
