const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const sql=fs.readFileSync('supabase/migrations/20261031210000_conference_operational_lifecycle_unification.sql','utf8');

test('accommodation removal atomically cleans transport and returns removed assignment ids',()=>{
  assert.match(sql,/create or replace function public\.remove_conference_accommodation/);
  assert.match(sql,/cleanup_conference_transport_for_participation\([\s\S]*?'accommodation_removed'/);
  assert.match(sql,/'removedTransportAssignmentIds',removed_transport_ids/);
});

test('apology cleans guardian transport and only children that lost accommodation eligibility',()=>{
  const body=sql.slice(sql.indexOf('create or replace function public.set_conference_participation_status'),sql.indexOf('create or replace function public.delete_conference_participation'));
  assert.match(body,/cleanup_conference_accommodation_for_participation/);
  assert.match(body,/not exists\(select 1 from public\.conference_accommodation_occupancies stay where stay\.participation_id=v_child\.id\)/);
  assert.match(body,/cleanup_conference_transport_for_participation\(v_child\.id/);
});

test('guardian participation deletion preserves and explicitly unlinks every child participation',()=>{
  const body=sql.slice(sql.indexOf('create or replace function public.delete_conference_participation'));
  assert.match(body,/update public\.conference_participations set guardian_participation_id=null/);
  assert.match(body,/'unlinkedChildParticipationIds',v_unlinked_child_ids/);
  assert.doesNotMatch(body,/delete from public\.conference_participations where guardian_participation_id/);
  assert.match(body,/'deletedParticipationIds',jsonb_build_array\(p_participation_id\)/);
});

test('independent child accommodation and transport survive guardian deletion',()=>{
  const body=sql.slice(sql.indexOf('create or replace function public.delete_conference_participation'));
  assert.match(body,/if not exists\(select 1 from public\.conference_accommodation_occupancies stay where stay\.participation_id=v_child\.id\) then/);
  assert.match(body,/cleanup_conference_transport_for_participation\(v_child\.id[\s\S]*?guardian_participation_deleted/);
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
