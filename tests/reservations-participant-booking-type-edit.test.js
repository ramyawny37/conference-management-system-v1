'use strict';

const assert=require('assert');
const fs=require('fs');
const path=require('path');

const root=path.join(__dirname,'..');
const migration=fs.readFileSync(path.join(
  root,'supabase/migrations/20260924223000_reservations_participant_booking_type_edit.sql'
),'utf8');
const canonicalization=fs.readFileSync(path.join(
  root,'supabase/migrations/20260925120000_reservations_participant_booking_type_edit_canonicalization.sql'
),'utf8');
const finalDefinition=migration+'\n'+canonicalization;

assert.match(finalDefinition,
  /'p_expected_revision','p_booking_type_id'/,
  'the protected mutation contract requires the selected booking type');
assert.match(finalDefinition,
  /v_booking\.revision<>\(p_args->>'p_expected_revision'\)::bigint/,
  'the booking revision remains an optimistic concurrency boundary');
assert.match(finalDefinition,
  /id=\(p_args->>'p_booking_type_id'\)::uuid[\s\S]*event_id=v_booking\.event_id[\s\S]*scope_partition_id=v_booking\.scope_partition_id/,
  'booking type selection is scoped to the booking event and partition');
assert.match(finalDefinition,
  /v_type\.id<>v_booking\.booking_type_id and not v_type\.active/,
  'only the current historical inactive type may be retained');
assert.match(finalDefinition,
  /booking_type_name_snapshot=v_type\.name,[\s\S]*price_snapshot=v_type\.price/,
  'commercial snapshots come from the authoritative booking type');
assert.doesNotMatch(finalDefinition,/update\s+reservations\.payments/i,
  'booking-type edits never rewrite payment records');
assert.match(finalDefinition,/reservations\.booking\.update/,
  'the existing booking-update permission remains authoritative');
assert.match(finalDefinition,/DEVICE_SESSION_INVALID/,
  'the device-session boundary is preserved');
assert.match(finalDefinition,
  /revoke all on function[\s\S]*platform\.execute_device_operation[\s\S]*from public,anon,authenticated/,
  'the protected dispatcher is not browser executable');
assert.match(canonicalization,
  /platform\.execute_device_operation_pre_generic_permission_resource_administration/,
  'the canonical dispatcher retains the latest pre-feature operation chain');
assert.match(canonicalization,
  /drop function platform\.execute_device_operation[\s\S]*rename to execute_device_operation/,
  'the feature wrapper is replaced by the canonical dispatcher');
assert.match(canonicalization,
  /drop function reservations_private\.mutate_scoped[\s\S]*rename to mutate_scoped/,
  'the complete scoped mutation is restored as the canonical implementation');
assert.match(canonicalization,
  /RESERVATIONS_PARTICIPANT_BOOKING_TYPE_EDIT_WRAPPER_REMAINS/,
  'migration completion rejects obsolete feature-wrapper objects');

console.log('reservations participant booking-type edit tests passed');
