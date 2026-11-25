'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const migration=fs.readFileSync('supabase/migrations/20261125180000_reservations_event_guardian_child_relationship.sql','utf8');
const genderCorrection=fs.readFileSync('supabase/migrations/20261125183000_public_registration_child_gender_canonicalization.sql','utf8');
const family=fs.readFileSync('supabase/migrations/20261125172000_public_registration_family_standalone_scope.sql','utf8');
const page=fs.readFileSync('public-registration.js','utf8');
const argumentContract=fs.readFileSync('supabase/migrations/20261125164000_public_registration_family_booking_argument_contract.sql','utf8');
const canonicalArgs=fs.readFileSync('supabase/migrations/20261125170000_public_registration_canonical_booking_args.sql','utf8');

test('guardian-child ownership is event scoped and never stored on the global person',()=>{
  assert.match(migration,/create table reservations\.event_guardian_children/);
  assert.match(migration,/foreign key\(scope_partition_id,event_id\)[\s\S]*reservations\.events\(scope_partition_id,id\)/);
  assert.match(migration,/unique\(event_id,child_person_id\)/);
  assert.doesNotMatch(migration,/alter table reservations\.participants add column.*guardian/is);
});

test('paid and dependent children retain distinct financial contracts',()=>{
  assert.match(migration,/child_role in \('child_paid','child_dependent'\)/);
  assert.match(migration,/child_role='child_paid' and child_booking_id is not null/);
  assert.match(migration,/child_role='child_dependent' and child_booking_id is null/);
  assert.doesNotMatch(migration,/insert into reservations\.bookings/i);
});

test('dependent identity uses the canonical audited helper and requires DOB',()=>{
  assert.match(migration,/platform_private\.create_reservations_dependent_person/);
  assert.match(migration,/platform\.person\.created/);
  assert.match(migration,/dateOfBirth/);
  assert.match(migration,/PUBLIC_REGISTRATION_DEPENDENT_IDENTITY_INVALID/);
  assert.match(migration,/PUBLIC_REGISTRATION_DEPENDENT_PERSON_WRITER_DRIFT/);
  assert.match(family,/insert into platform\.people/);
  assert.match(migration,/execute replace\(d,old_text,new_text\)/);
  assert.match(genderCorrection,/p_profile->>'gender' not in\('male','female'\)/);
  assert.match(genderCorrection,/p_profile->>'gender',\s*\(p_profile->>'dateOfBirth'\)::date/);
  assert.doesNotMatch(page,/m\.gender='child'/);
  assert.match(page,/!\['male','female'\]\.includes\(m\.gender\)/);
});

test('family approval captures both child roles without weakening Conference projection',()=>{
  assert.match(migration,/new\.role in\('child_paid','child_dependent'\)/);
  assert.match(migration,/PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT/);
  assert.match(family,/if e\.conference_id is not null/);
  assert.match(family,/guardian_participation_id/);
});

test('relationship survives booking lifecycle changes and supports same-event rebooking',()=>{
  assert.match(migration,/references reservations\.bookings\(scope_partition_id,id\) on delete restrict/);
  assert.doesNotMatch(migration,/on delete cascade/);
  assert.doesNotMatch(migration,/lifecycle_status='active'/);
  assert.doesNotMatch(migration,/create trigger .*reservations\.bookings/is);
});


test('family approval preserves required booking keys and canonical dependent gender',()=>{
  assert.match(argumentContract,/args:=jsonb_build_object\('p_operation_id'/);
  assert.doesNotMatch(argumentContract,/new_args text := \$\$args:=jsonb_strip_nulls/);
  assert.match(argumentContract,/'p_service_sector_other',m\.service_sector_other,'p_notes',m\.notes/);
  assert.match(argumentContract,/'gender',m\.gender/);
  assert.doesNotMatch(argumentContract,/new_gender text := \$\$jsonb_build_object\([^$]*'gender','child'/);
});


test('public registration has one canonical booking argument owner',()=>{
  assert.match(canonicalArgs,/create or replace function reservations_private\.public_registration_booking_args/);
  assert.match(canonicalArgs,/decide_public_registration_request/);
  assert.match(canonicalArgs,/decide_public_registration_family_request/);
  assert.match(canonicalArgs,/v_booking_args:=reservations_private\.public_registration_booking_args/);
  assert.match(canonicalArgs,/args:=reservations_private\.public_registration_booking_args/);
  assert.doesNotMatch(canonicalArgs,/new_single text := \$\$v_booking_args:=jsonb_strip_nulls/);
});
