'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const sql=fs.readFileSync('supabase/migrations/20261125113000_public_registration_protected_decision.sql','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');
const publicEdge=fs.readFileSync('supabase/functions/public-registration/index.ts','utf8');

test('approved-device dispatcher exposes only canonical family and added-member decisions',()=>{
  assert.match(edge,/const reservations=new Set\(\[[^\]]*'decide_public_registration_family_request'/);
  assert.match(edge,/const reservations=new Set\(\[[^\]]*'decide_public_registration_added_member'/);
  assert.doesNotMatch(edge,/['"]decide_public_registration_request['"]/);
  assert.match(sql,/when \\'decide_public_registration_request\\' then/);
  assert.match(sql,/v_session\.device_id/);
  assert.match(sql,/resolve_event_scope\(p_device_id,r\.event_id,'reservations\.booking\.create'\)/);
  assert.doesNotMatch(publicEdge,/decide_public_registration_request|identityCandidates/);
});

test('approval delegates to the current canonical booking writer without direct canonical inserts',()=>{
  assert.match(sql,/reservations\.mutate\(p_device_id,'create_booking'/);
  assert.doesNotMatch(sql,/insert\s+into\s+reservations\.bookings/i);
  assert.doesNotMatch(sql,/insert\s+into\s+platform\.people/i);
  assert.doesNotMatch(sql,/p_person_update_revision/);
  assert.match(sql,/'p_person_id',case when p_decision='approve_existing' then p_person_id else null end/);
});

test('request lock revision state and event isolation precede every decision mutation',()=>{
  assert.match(sql,/where id=p_request_id for update/);
  assert.match(sql,/if r\.revision<>p_expected_revision/);
  assert.match(sql,/PUBLIC_REGISTRATION_STATE_CONFLICT/);
  assert.match(sql,/id=\(v_context->>'eventId'\)::uuid and scope_partition_id=\(v_context->>'scopePartitionId'\)::uuid/);
  assert.match(sql,/PUBLIC_REGISTRATION_EVENT_SCOPE_CONFLICT/);
});

test('stable operation replay is exact-intent and conflicting intent fails',()=>{
  assert.match(sql,/pg_advisory_xact_lock[\s\S]*public-registration-decision:/);
  assert.match(sql,/where decision_operation_id=p_operation_id/);
  assert.match(sql,/replay_request\.decision_intent_digest<>v_intent/);
  assert.match(sql,/PUBLIC_REGISTRATION_DECISION_IDEMPOTENCY_CONFLICT/);
  assert.match(sql,/return replay_request\.decision_result/);
});

test('existing identity is revalidated and explicit new identity delegates different decision to canonical challenge',()=>{
  assert.match(sql,/p_decision='approve_existing' and p_person_id is null/);
  assert.match(sql,/p_decision<>'approve_existing' and p_person_id is not null/);
  assert.match(sql,/reservations_person_identity_candidates\(r\.submitted_full_name,r\.submitted_phone,10\)/);
  assert.match(sql,/PUBLIC_REGISTRATION_PERSON_CANDIDATE_STALE/);
  assert.match(sql,/v_booking_result:=reservations\.mutate\(p_device_id,'create_booking',v_booking_args\)/);
  assert.match(sql,/v_booking_result->>'identityResolutionRequired'/);
  assert.match(sql,/'p_identity_resolution_token',v_booking_result->>'identityResolutionToken'/);
  assert.match(sql,/'p_identity_resolution_decision','different'/);
  assert.doesNotMatch(sql,/p_decision='approve_new' and jsonb_array_length\(v_candidates\)>0/);
});

test('age is derived from submitted DOB at event start and is booking snapshot input',()=>{
  assert.match(sql,/pg_catalog\.age\(v_event\.start_date,r\.submitted_date_of_birth\)/);
  assert.match(sql,/'p_age',v_age/);
  assert.match(sql,/'p_date_of_birth',r\.submitted_date_of_birth/);
  assert.doesNotMatch(sql,/current_date|statement_timestamp\(\)::date/);
});

test('canonical writer retains inactive type capacity duplicate and closed event guards',()=>{
  const currentWriter=fs.readFileSync('supabase/migrations/20261115001255_reservations_operational_review_active_booking_guard.sql','utf8');
  assert.match(currentWriter,/v_event\.status in\('closed','full'\)/);
  assert.match(currentWriter,/RESERVATIONS_EVENT_CAPACITY_REACHED/);
  assert.match(currentWriter,/RESERVATIONS_BOOKING_TYPE_INACTIVE/);
  assert.match(currentWriter,/RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT/);
});

test('reject and waitlist update only request state while approval links booking after writer success',()=>{
  assert.match(sql,/if p_decision in\('reject','waitlist'\) then/);
  assert.match(sql,/state=case when p_decision='reject' then 'rejected' else 'waitlisted' end/);
  assert.match(sql,/v_booking_id:=nullif\(v_booking_result->>'bookingId',''\)::uuid/);
  assert.match(sql,/set state='approved',resolved_person_id=v_person_id,booking_id=v_booking_id/);
});

test('private decision helper and request tables remain outside public execution',()=>{
  assert.match(sql,/revoke all on function reservations_private\.decide_public_registration_request[^;]+from public,anon,authenticated,service_role/);
  assert.doesNotMatch(publicEdge,/platform\.people|reservations\.bookings|identityCandidates/);
});
