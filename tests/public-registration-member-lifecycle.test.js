'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const migration=fs.readFileSync('supabase/migrations/20261128122000_public_registration_member_lifecycle_cutover.sql','utf8');
const edge=fs.readFileSync('supabase/functions/public-registration/index.ts','utf8');
const replayCutover=fs.readFileSync('supabase/migrations/20261128133000_public_registration_family_decision_replay_cutover.sql','utf8');
test('family additions extend canonical request members without parallel tables',()=>{
 assert.match(migration,/alter table reservations\.public_registration_request_members/);
 assert.match(migration,/review_state text/);
 assert.match(migration,/public_registration_add_family_member/);
 assert.match(migration,/approve_public_registration_member/);
 assert.match(migration,/decide_public_registration_added_member/);
 assert.match(migration,/public_registration_booking_args/);
 assert.doesNotMatch(migration,/create table reservations\..*family.*add/i);
});
test('accepted request stays accepted while added member owns review state',()=>{
 assert.match(migration,/if r\.state<>'approved'/);
 assert.match(migration,/review_state='pending'/);
 assert.match(migration,/review_state='approved'/);
 assert.match(migration,/where request_id=r\.id and member_key=p_member_key/);
 assert.doesNotMatch(migration,/set state='submitted'/);
});
test('public edge exposes one exact-shape member addition operation',()=>{
 assert.match(edge,/add_family_member/);
 assert.match(edge,/trackingSecretDigest/);
 assert.match(edge,/PUBLIC_REGISTRATION_MEMBER_SHAPE_INVALID/);
 assert.match(edge,/const keys=\['bookingTypeId','church','cityOrVillage','dateOfBirth','fullName','gender','governorate','guardianMemberKey','memberKey','notes','phone','role','serviceSector','serviceSectorOther'\]/);
});
test('member notifications reuse canonical notification infrastructure',()=>{
 assert.match(migration,/stage_public_registration_member_added_notification/);
 assert.match(migration,/platform\.notification_outbox/);
 assert.match(migration,/stage_public_registration_member_decision_notification/);
 assert.match(migration,/platform\.notification_applicant_push_subscriptions/);
 assert.match(migration,/public_registration\.decision/);
});

test('member decisions are exact-intent idempotent without re-notifying on replay',()=>{
 assert.match(migration,/m\.decision_operation_id=p_operation_id/);
 assert.match(migration,/m\.decision_intent_digest is distinct from intent/);
 assert.match(migration,/PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT/);
 const replay=migration.indexOf("if m.decision_operation_id=p_operation_id");
 const notify=migration.indexOf("stage_public_registration_member_decision_notification",replay);
 assert.ok(replay>=0&&notify>replay);
});


test('guardian lookup qualifies role against PL/pgSQL variable',()=>{
  assert.match(migration,/from reservations\.public_registration_request_members x where x\.request_id=r\.id and x\.member_key=guardian and x\.role in\('primary','adult'\)and x\.review_state='approved'/);
  assert.doesNotMatch(migration,/member_key=guardian and role in\('primary','adult'\)/);
});

test('original family approval uses deterministic member operations and one canonical member approval path',()=>{
 assert.match(migration,/decide_public_registration_family_request/);
 assert.match(replayCutover,/child_operation:=extensions\.uuid_generate_v5\(p_operation_id,m\.member_key::text\)/);
 assert.match(replayCutover,/approve_public_registration_member\(p_device_id,child_operation,r\.id,m\.member_key,choice,pid,p_reason\)/);
 assert.doesNotMatch(replayCutover,/child_operation:=extensions\.gen_random_uuid\(\)/);
});
