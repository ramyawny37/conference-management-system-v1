'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const sql=fs.readFileSync('supabase/migrations/20261125224500_public_registration_phone_identity_duplicate_guard.sql','utf8');

test('public family duplicate identity is event plus canonical phone, not mutable DOB',()=>{
  assert.match(sql,/public-registration-identity:'\|\|v_event\.id::text\|\|':'\|\|platform_private\.person_phone_key\(v_primary->>'phone'\)/);
  assert.doesNotMatch(sql,/public-registration-identity:[^\n]*dateOfBirth/);
  assert.match(sql,/platform_private\.person_phone_key\(r\.submitted_phone\)=platform_private\.person_phone_key\(v_primary->>'phone'\)/);
  assert.doesNotMatch(sql,/r\.submitted_date_of_birth=\(v_primary->>'dateOfBirth'\)::date/);
});

test('same phone blocks unresolved and active same-event registration but preserves rebooking after inactive approval',()=>{
  assert.match(sql,/r\.state in\('submitted','under_review','waitlisted'\)/);
  assert.match(sql,/r\.state='approved' and b\.lifecycle_status='active'/);
  assert.doesNotMatch(sql,/r\.state in\([^\n]*'rejected'/);
  assert.doesNotMatch(sql,/b\.lifecycle_status<>'active'/);
});

test('idempotent submit replay is resolved before duplicate identity rejection',()=>{
  const replay=sql.indexOf("public-registration-submit:");
  const duplicate=sql.indexOf("public-registration-identity:");
  assert.ok(replay>=0 && duplicate>replay);
  assert.match(sql,/where channel_id=v_channel\.id and submit_operation_id=p_submit_operation_id/);
  assert.match(sql,/PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT/);
  assert.match(sql,/return jsonb_build_object\('reference',v_existing\.request_reference/);
});

test('writer remains one canonical function with fail-closed browser ACL',()=>{
  assert.match(sql,/CREATE OR REPLACE FUNCTION reservations\.public_registration_submit_family/);
  assert.match(sql,/revoke all on function reservations\.public_registration_submit_family\(uuid,uuid,bytea,bytea,jsonb\) from public,anon,authenticated/);
  assert.match(sql,/grant execute on function reservations\.public_registration_submit_family\(uuid,uuid,bytea,bytea,jsonb\) to service_role/);
  assert.doesNotMatch(sql,/create table/i);
});

test('public registration validates booking age before persistence',()=>{const sql=fs.readFileSync('supabase/migrations/20261126053000_public_registration_canonical_age_validation.sql','utf8');assert.match(sql,/require_public_registration_member_age/);assert.match(sql,/PUBLIC_REGISTRATION_AGE_INVALID/);assert.ok(sql.includes("p_role<>'child_dependent' and (v_age<1 or v_age>120)"));assert.match(sql,/perform reservations_private\.require_public_registration_member_age\(v_event\.start_date,v_dob,v_role\)/);});
