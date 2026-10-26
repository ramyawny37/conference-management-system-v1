const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const sql=fs.readFileSync('supabase/migrations/20261025223000_atomic_accommodation_room_draft_save.sql','utf8');
const script=fs.readFileSync('script.js','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');
const session=fs.readFileSync('js/supabase/device-session.js','utf8');
const scopedExtra=fs.readFileSync('supabase/migrations/20261025224500_conference_scoped_extra_bed_capacity.sql','utf8');

test('room draft save is permission checked, leased, revision checked, idempotent and audited',()=>{
  assert.match(sql,/require_conference_accommodation_context\(p_device,p_conference,'conference\.accommodation\.manage',true\)/);
  assert.match(sql,/validated_phase1c_device_authorization/);
  assert.match(sql,/require_accommodation_operation_leases/);
  assert.match(sql,/room\.revision<>p_expected_revision/);
  assert.match(sql,/operation_id=p_operation_id[\s\S]*status','duplicate'/);
  assert.match(sql,/conference\.accommodation\.room_draft_saved/);
  assert.match(edge,/conference\.add\('save_conference_accommodation_room_draft'\)/);
});

test('structure and assignments execute inside the same database transaction',()=>{
  assert.match(sql,/^begin;/m);
  assert.match(sql,/mutate_conference_accommodation_structure\(p_device,'update_room'/);
  assert.match(sql,/public\.assign_conference_accommodation\(/);
  assert.match(sql,/^commit;/m);
  assert.ok(sql.indexOf('mutate_conference_accommodation_structure')<sql.indexOf('public.assign_conference_accommodation'));
});

test('single editor Save submits selected slots and omits unchanged room structure',()=>{
  const save=script.slice(script.indexOf('function saveCanonicalAccommodationRoomData('),script.indexOf('\nfunction renderCanonicalAccommodation('));
  assert.match(save,/structureChanged=Object\.keys\(draft\.original\)/);
  assert.match(save,/assignments\.push\(\{participationId:slot\.selectedParticipationId/);
  assert.match(save,/structureChanged\?structure:null/);
  assert.match(script,/operationId:crypto\.randomUUID\(\)/);
  assert.match(script,/p_operation_id:draft\.operationId/);
  assert.match(save,/if\(!structureChanged&&!assignments\.length\)\{closeRM\(\);return true;\}/);
  assert.doesNotMatch(save,/update_accommodation_room|assignConferenceAccommodation/);
});

test('cancel remains draft-only and protected errors preserve safe request diagnostics',()=>{
  assert.match(script,/function closeRM\(\)\{[\s\S]*resetCanonicalAccommodationRoomDetails\(\)/);
  assert.match(session,/\['module','operation','stage','sqlstate','applicationCode','requestId','timestamp'\]/);
  assert.match(session,/result\.diagnostic=diagnostic/);
});

test('extra beds are Conference assignment state and never rewrite permanent room capacity',()=>{
  assert.match(scopedExtra,/alter table public\.conference_room_assignments add column if not exists extra_bed_capacity/);
  assert.match(scopedExtra,/'extraBedCapacity'',ra\.extra_bed_capacity/);
  assert.match(scopedExtra,/assignment\.extra_bed_capacity/);
  assert.match(scopedExtra,/update public\.conference_room_assignments set extra_bed_capacity=extra_capacity/);
  assert.match(scopedExtra,/'p_extra_bed_capacity',room\.extra_bed_capacity/);
});

test('draft lock ordering, room assignment revision and operation replay are explicit',()=>{
  assert.match(scopedExtra,/conference_participations[\s\S]*order by id for update/);
  assert.match(scopedExtra,/room_assignment\.revision<>p_expected_assignment_revision/);
  assert.match(scopedExtra,/operation_id=p_operation_id[\s\S]*status','duplicate'/);
});
