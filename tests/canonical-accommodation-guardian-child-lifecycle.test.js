'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const script=fs.readFileSync('script.js','utf8');
const css=fs.readFileSync('style.css','utf8');
const migration=fs.readFileSync('supabase/migrations/20261026104500_canonical_guardian_child_accommodation_lifecycle.sql','utf8');
const moveMigration=fs.readFileSync('supabase/migrations/20261026111500_reject_direct_linked_child_stay_moves.sql','utf8');
const rendererSource=script.slice(script.indexOf('function isCanonicalAccommodationChild('),script.indexOf('\nfunction setCanonicalAccommodationRoomClosed('));
const context={esc:value=>String(value)};
vm.runInNewContext(rendererSource,context);

test('linked child row is the compact unified-editor path with bed editing and removal only',()=>{
  const child={occupancyId:'child-stay',participationId:'child',guardianParticipationId:'guardian',bedType:'shared',arrivalDay:1,leaveDay:4,arrivedAt:'now',person:{fullName:'الطفل',phone:'010',church:'الكنيسة'}};
  const html=context.renderCanonicalAccommodationDetailOccupant(child,{occupancyId:'child-stay'},true,true,false,null);
  assert.match(html,/↳ الطفل/);
  assert.match(html,/canonicalRoomStayBed_child-stay/);
  assert.match(html,/>بدون سرير</);
  assert.match(html,/الوصول والمفتاح تابعان للوالد/);
  assert.match(html,/removeCanonicalAccommodation/);
  for(const forbidden of ['canonicalRoomStayArrival_','canonicalRoomStayLeave_','canonicalRoomStayExtraType_','setCanonicalAccommodationArrival','closeRM\(\);moveCanonicalAccommodation','010','الكنيسة','accommodation-arrival-badge','accommodation-key-holder-badge'])assert.doesNotMatch(html,new RegExp(forbidden));
  assert.match(css,/canonical-room-child\{display:grid;grid-template-columns:minmax\(180px,1fr\) minmax\(150px,220px\)/);
});

test('compact child row omits independent arrival and key controls',()=>{
  const child={occupancyId:'child-stay',participationId:'child',guardianParticipationId:'guardian',bedType:'shared',arrivedAt:'now',person:{fullName:'الطفل'}};
  const html=context.renderCanonicalAccommodationCompactOccupants([child],child,true);
  assert.match(html,/↳ الطفل/);
  assert.match(html,/طفل مرافق — بدون سرير/);
  assert.match(html,/الوصول والمفتاح تابعان للوالد/);
  for(const forbidden of ['accommodation-compact-key','accommodation-arrival','setCanonicalAccommodationArrival'])assert.doesNotMatch(html,new RegExp(forbidden));
});

test('arrival and key-recipient paths defensively reject children',()=>{
  const arrival=script.slice(script.indexOf('function setCanonicalAccommodationArrival('),script.indexOf('\nfunction setCanonicalAccommodationRoomKey('));
  const key=script.slice(script.indexOf('function setCanonicalAccommodationRoomKey('),script.indexOf('\nfunction canonicalAccommodationActiveKeyHolder('));
  assert.match(arrival,/isCanonicalAccommodationChild\(occupancy\)/);
  assert.match(arrival,/الوصول تابع للوالد ولا يُسجل للطفل بشكل مستقل\./);
  assert.match(key,/\.filter\(function\(item\)\{return !isCanonicalAccommodationChild\(item\);\}\)/);
  assert.match(key,/holder&&isCanonicalAccommodationChild\(holder\)/);
});

test('all linked child bed modes render under the guardian and consume only their own capacity',()=>{
  const open=script.slice(script.indexOf('function openCanonicalAccommodationRoomDetails('),script.indexOf('\nfunction submitCanonicalAccommodationRoomDraft('));
  assert.match(open,/occupancyGroups\.rows\.find/);
  assert.match(open,/\.children\.map\(function\(child\)/);
  assert.match(open,/baseIndex=baseOccupancies\.length/);
  assert.match(open,/extraIndex=extraOccupancies\.length/);
  assert.doesNotMatch(open,/sharedByGuardian\[String\(occupancy\.participationId\)\]/);
});

test('room draft sends child bed changes with immutable original inherited dates',()=>{
  const save=script.slice(script.indexOf('function saveCanonicalAccommodationRoomData('),script.indexOf('\nfunction renderCanonicalAccommodation('));
  assert.match(save,/if\(original\.isChild\)/);
  assert.match(save,/arrivalDay:original\.arrivalDay,leaveDay:original\.leaveDay/);
  assert.match(save,/extraBedPersonType:bedType==='extra'\?'child':null/);
});

test('database centrally rejects independent child stay and arrival mutations',()=>{
  assert.match(migration,/ACCOMMODATION_CHILD_STAY_INHERITED/);
  assert.match(migration,/ACCOMMODATION_CHILD_ARRIVAL_INHERITED/);
  assert.match(migration,/before insert or update of[\s\S]*arrival_day,leave_day[\s\S]*arrived_at,arrived_by/);
  assert.match(migration,/guardian\.arrival_day=new\.arrival_day/);
  assert.match(migration,/guardian\.leave_day is not distinct from new\.leave_day/);
  assert.match(moveMigration,/participation\.guardian_participation_id is not null/);
  assert.match(moveMigration,/p_arrival is distinct from guardian_stay\.arrival_day/);
  assert.match(moveMigration,/raise exception 'ACCOMMODATION_CHILD_STAY_INHERITED'/);
});

test('guardian synchronization covers move, stay dates, arrival, cancellation and historical split',()=>{
  assert.match(migration,/after insert or delete or update of room_id,arrival_day,leave_day,arrived_at,arrived_by/);
  assert.match(migration,/set room_id=new\.room_id,arrival_day=new\.arrival_day,leave_day=new\.leave_day/);
  assert.match(migration,/delete from public\.conference_accommodation_occupancies child_stay/);
  assert.match(migration,/prior\.leave_day=new\.arrival_day/);
  assert.match(migration,/insert into public\.conference_accommodation_occupancies/);
  assert.match(migration,/conference_room_has_capacity\(new\.conference_id,new\.room_id,linked\.bed_type/);
});

test('child bed update precedes guardian update in one locked atomic draft',()=>{
  assert.match(migration,/order by \(part\.guardian_participation_id is null\),u\.value->>'occupancyId'/);
  assert.match(migration,/select child\.guardian_participation_id[\s\S]*order by p\.id for update/);
  assert.match(migration,/order by o\.id for update/);
  assert.match(migration,/^begin;/m);
  assert.match(migration,/^commit;/m);
});

test('synchronization does not mutate restaurant or transport state',()=>{
  const sync=migration.slice(migration.indexOf('create or replace function platform_private.sync_guardian_linked_child_stays'),migration.indexOf('drop trigger if exists conference_accommodation_sync_guardian_children'));
  assert.doesNotMatch(sync,/conference_transport_assignments|conference_restaurant/);
  assert.match(migration,/drop function if exists platform_private\.sync_guardian_shared_child_stays/);
  assert.match(migration,/revoke all on function platform_private\.sync_guardian_linked_child_stays\(\) from public,anon,authenticated,service_role/);
});
