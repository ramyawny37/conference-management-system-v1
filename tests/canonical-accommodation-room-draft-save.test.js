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
  assert.match(save,/if\(!structureChanged&&!assignments\.length&&!updates\.length\)\{closeRM\(\);return true;\}/);
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

test('room draft save verifies its lease asynchronously through the canonical server-backed lease API',()=>{
  const submit=script.slice(script.indexOf('function submitCanonicalAccommodationRoomDraft('),script.indexOf('\nfunction saveCanonicalAccommodationRoomData('));
  assert.match(submit,/getResourceLease\('conference','accommodation_room',draft\.roomId,\{conferenceId:remoteId,scope:'edit'\}\)\.then/);
  assert.doesNotMatch(submit,/getOwnedResourceLease\(/);
  assert.match(submit,/acquireResourceLease\('conference','accommodation_room',draft\.roomId/);
  assert.match(submit,/releaseResourceLease\('conference','accommodation_room',draft\.roomId/);
});

test('room transfer capacity counts beds, not children sharing a bed',()=>{
  const move=script.slice(script.indexOf('function confirmCanonicalAccommodationMoveDay('),script.indexOf('\nfunction ',script.indexOf('function confirmCanonicalAccommodationMoveDay(')+10));
  assert.match(move,/var bedOccupants=occupants\.filter\(function\(item\)\{return item\.bedType!=='shared';\}\)/);
  assert.match(move,/bedOccupants\.length>=capacity/);
  assert.doesNotMatch(move,/return occupants\.length>=capacity/);
});

const latestRoomDraft=fs.readFileSync('supabase/migrations/20261026143000_room_draft_atomic_occupant_replacement.sql','utf8');
const guardianReplacement=fs.readFileSync('supabase/migrations/20261026170000_guardian_replacement_removes_housed_children.sql','utf8');

test('latest canonical room draft retains atomic replacement, revisions, idempotency and device authority',()=>{
  assert.match(latestRoomDraft,/p_replacements jsonb/);
  assert.match(latestRoomDraft,/require_conference_accommodation_context\(p_device,p_conference,'conference\.accommodation\.manage',true\)/);
  assert.match(latestRoomDraft,/validated_phase1c_device_authorization/);
  assert.match(latestRoomDraft,/room_assignment\.revision<>p_expected_assignment_revision/);
  assert.match(latestRoomDraft,/room\.revision<>p_expected_revision/);
  assert.match(latestRoomDraft,/operation_id=p_operation_id[\s\S]*status','duplicate'/);
  assert.match(latestRoomDraft,/public\.replace_conference_accommodation\(/);
  assert.match(latestRoomDraft,/p_room_lease_tokens/);
});

test('guardian replacement retires only housed linked children in the same transaction',()=>{
  assert.match(guardianReplacement,/Replacing a guardian removes only the children currently housed/);
  assert.match(guardianReplacement,/guardian_participation_id/);
  assert.match(guardianReplacement,/conference_accommodation_occupancies/);
});

const dispatchMigration=fs.readFileSync('supabase/migrations/20261026143000_room_draft_atomic_occupant_replacement.sql','utf8');
test('room draft dispatch requires a room-scoped lease before invoking the atomic save',()=>{
  assert.match(dispatchMigration,/new_signature:='array\[[^\n]*p_room_lease_tokens/);
  assert.match(dispatchMigration,/new_call:='return public\.save_conference_accommodation_room_draft/);
  assert.match(dispatchMigration,/revoke all on function public\.save_conference_accommodation_room_draft/);
  assert.match(dispatchMigration,/grant execute on function public\.save_conference_accommodation_room_draft[^\n]*to service_role/);
});
test('guardian replacement keeps participation links and only retires overlapping housed child stays',()=>{
  assert.match(guardianReplacement,/cp\.guardian_participation_id=old_stay\.participation_id/);
  assert.match(guardianReplacement,/o\.room_id=old_stay\.room_id/);
  assert.match(guardianReplacement,/o\.arrival_day<=p_effective_day/);
  assert.match(guardianReplacement,/p_effective_day<coalesce\(o\.leave_day,days\+1\)/);
  assert.match(guardianReplacement,/Their central participation and[\s\S]*guardian relationship remain intact/);
});
