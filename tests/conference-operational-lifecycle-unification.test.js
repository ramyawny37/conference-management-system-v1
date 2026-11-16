const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const sql=fs.readFileSync('supabase/migrations/20261101213650_canonical_family_lifecycle_final_cutover.sql','utf8');
const operationalSql=fs.readFileSync('supabase/migrations/20261031190103_conference_operational_lifecycle_unification.sql','utf8');

test('accommodation removal atomically cleans transport and returns removed assignment ids',()=>{
  assert.match(operationalSql,/create or replace function public\.remove_conference_accommodation/);
  assert.match(operationalSql,/cleanup_conference_transport_for_participation\([\s\S]*?'accommodation_removed'/);
  assert.match(operationalSql,/'removedTransportAssignmentIds',removed_transport_ids/);
});

test('guardian apology applies to the whole linked family and clears each member accommodation and transport',()=>{
  const body=sql.slice(sql.indexOf('set_conference_participation_status('),sql.indexOf('create or replace function public.delete_conference_participation'));
  assert.match(body,/guardian_participation_id=current\.id/);
  assert.match(body,/conference_id=current\.conference_id/);
  assert.match(body,/for member in select \* from public\.conference_participations where id=any\(family_ids\)/);
  assert.match(body,/cleanup_conference_accommodation_for_participation/);
  assert.match(body,/cleanup_conference_transport_for_participation/);
  assert.match(body,/'changedParticipationIds',changed_ids/);
});

test('guardian deletion removes linked children rather than unlinking them',()=>{
  const body=sql.slice(sql.indexOf('create or replace function public.delete_conference_participation'));
  assert.match(body,/guardian_participation_id=current\.id/);
  assert.match(body,/delete from public\.conference_participations where id=any\(family_ids\) and id<>current\.id/);
  assert.match(body,/'deletedParticipationIds',to_jsonb\(family_ids\)/);
  assert.doesNotMatch(body,/update public\.conference_participations set guardian_participation_id=null/);
});

test('linked children cannot reactivate while their guardian is apologized',()=>{
  const body=sql.slice(sql.indexOf('set_conference_participation_status('),sql.indexOf('create or replace function public.delete_conference_participation'));
  assert.match(body,/p_status='active' and current\.guardian_participation_id is not null/);
  assert.match(body,/ACTIVE_CHILD_GUARDIAN_REQUIRED/);
});

test('people and financial ledgers are outside lifecycle deletion targets',()=>{
  assert.doesNotMatch(sql,/delete from platform\.people/i);
  assert.doesNotMatch(sql,/delete from (public\.)?conference_finance/i);
  assert.doesNotMatch(sql,/delete from reservations\.payments/i);
});

test('security and idempotency contracts remain enforced',()=>{
  assert.match(sql,/APPROVED_DEVICE_SESSION_REQUIRED/);
  assert.match(sql,/CONFERENCE_PARTICIPATION_REVISION_CONFLICT/);
  assert.match(sql,/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
  assert.match(sql,/revoke all on function public\.delete_conference_participation/);
  assert.match(sql,/grant execute on function public\.delete_conference_participation[\s\S]*?to service_role/);
});
