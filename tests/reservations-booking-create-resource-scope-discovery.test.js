'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync('supabase/migrations/20260922090000_reservations_booking_create_resource_scope_discovery_reconciliation.sql','utf8');

test('booking creation discovery authenticates device without demanding module-wide booking.create',()=>{
  assert.match(migration,/v_actor:=public\.require_current_approved_device\(p_device_id\)/);
  assert.doesNotMatch(migration,/require_effective_module_permission\([\s\S]{0,160}'reservations\.booking\.create',null,null/);
});

test('booking creation discovery filters every returned event by booking.create',()=>{
  assert.match(migration,/has_event_permission\(v_actor,'reservations\.booking\.create',e\.id\)/);
  assert.match(migration,/e\.status not in\('closed','full'\)/);
});

test('conference discovery retains active membership boundary',()=>{
  assert.match(migration,/join public\.organization_members om on om\.organization_id=c\.organization_id and om\.user_id=v_actor/);
  assert.match(migration,/c\.deleted_at is null/);
});
