const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const script=fs.readFileSync('script.js','utf8');
const css=fs.readFileSync('style.css','utf8');
const sql=fs.readFileSync('supabase/migrations/20261026120000_unified_accommodation_room_stay_draft.sql','utf8');

test('existing current stays are editable in the unified room editor',()=>{
  const renderer=script.slice(script.indexOf('function renderCanonicalAccommodationDetailOccupant('),script.indexOf('\nfunction canonicalAccommodationRoomEmptySlotHtml('));
  for(const field of ['canonicalRoomStayArrival_','canonicalRoomStayLeave_','canonicalRoomStayBed_','canonicalRoomStayExtraType_']) assert.match(renderer,new RegExp(field));
  assert.doesNotMatch(renderer,/editCanonicalAccommodation/);
  assert.match(renderer,/setCanonicalAccommodationArrivalFromRoomEditor/);
  assert.match(script,/roomKeyButton\.addEventListener\('click',function\(\)\{setCanonicalAccommodationRoomKey\(room\.roomId\)/);
  assert.match(renderer,/moveCanonicalAccommodation/);
  assert.match(renderer,/removeCanonicalAccommodation/);
  assert.match(css,/canonical-room-stay-bed/);
});

test('draft includes original stay revisions and submits changed stays only',()=>{
  const open=script.slice(script.indexOf('function openCanonicalAccommodationRoomDetails('),script.indexOf('\nfunction submitCanonicalAccommodationRoomDraft('));
  const save=script.slice(script.indexOf('function saveCanonicalAccommodationRoomData('),script.indexOf('\nfunction renderCanonicalAccommodation('));
  assert.match(open,/stays:\{\}/);
  assert.match(open,/expectedRevision:Number\(occupancy\.revision\)/);
  assert.match(save,/var changed=/);
  assert.match(save,/updates\.push\(\{occupancyId:occupancyId,expectedRevision:original\.expectedRevision/);
  assert.match(save,/!structureChanged&&!assignments\.length&&!updates\.length/);
  const submit=script.slice(script.indexOf('function submitCanonicalAccommodationRoomDraft('),script.indexOf('\nfunction saveCanonicalAccommodationRoomData('));
  assert.match(submit,/operation:'move',sourceRoomId:draft\.roomId,targetRoomId:draft\.roomId/);
  assert.match(submit,/saveConferenceFamilyAccommodationDraft/);
});

test('central draft validates and locks every changed entity in deterministic order',()=>{
  assert.match(sql,/jsonb_typeof\(p_updates\)<>'array'/);
  assert.match(sql,/conference_participations[\s\S]*order by p\.id for update/);
  assert.match(sql,/conference_room_assignments[\s\S]*for update/);
  assert.match(sql,/conference_accommodation_rooms[\s\S]*for update/);
  assert.match(sql,/conference_accommodation_occupancies[\s\S]*order by o\.id for update/);
  assert.match(sql,/room_assignment\.revision<>p_expected_assignment_revision/);
  assert.match(sql,/room\.revision<>p_expected_revision/);
  assert.match(sql,/move_conference_accommodation\(p_device,p_conference,\(item->>'occupancyId'\)::uuid,\(item->>'expectedRevision'\)::bigint,p_room/);
});

test('one protected transaction preserves move rules, assignment rules, audit and idempotency',()=>{
  assert.match(sql,/^begin;/m);
  assert.match(sql,/public\.move_conference_accommodation/);
  assert.match(sql,/public\.assign_conference_accommodation/);
  assert.match(sql,/operation_id=p_operation_id[\s\S]*status','duplicate'/);
  assert.match(sql,/conference\.accommodation\.room_draft_saved/);
  assert.match(sql,/^commit;/m);
  assert.match(sql,/p_updates'',''p_room_lease_tokens/);
});

test('historical room stays remain display-only and outside the editable draft',()=>{
  const open=script.slice(script.indexOf('function openCanonicalAccommodationRoomDetails('),script.indexOf('\nfunction submitCanonicalAccommodationRoomDraft('));
  assert.match(open,/otherRoomStays=.*filter/);
  assert.match(open,/canonical-room-stay-history/);
  assert.ok(open.indexOf('registerStay(occupancy)')<open.indexOf("if(otherRoomStays.length)"));
  const history=open.slice(open.indexOf("if(otherRoomStays.length)"));
  assert.doesNotMatch(history,/registerStay/);
});
