'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261103094152_reservations_person_lifecycle_snapshots.sql'),'utf8');
const runtime=fs.readFileSync(path.join(root,'modules/reservations/reservations-module.js'),'utf8');

test('reservation snapshots own historical gender and birth date without deriving birth date from age',()=>{
  assert.match(migration,/add column if not exists gender_snapshot text/);
  assert.match(migration,/add column if not exists date_of_birth_snapshot date/);
  assert.match(migration,/gender_snapshot=person\.gender/);
  assert.match(migration,/date_of_birth_snapshot=person\.date_of_birth/);
  assert.doesNotMatch(migration,/(?:to_date|make_date|make_interval)\s*\([^)]*age/i);
  assert.match(migration,/nullif\(p_args->>''p_gender''/);
  assert.match(migration,/nullif\(p_args->>''p_date_of_birth''/);
});

test('booking read exposes independent historical and canonical nine-field profiles',()=>{
  assert.match(migration,/participant\.gender_snapshot gender/);
  assert.match(migration,/participant\.date_of_birth_snapshot date_of_birth/);
  for(const column of ['canonical_full_name','canonical_phone','canonical_gender','canonical_date_of_birth','canonical_church','canonical_governorate','canonical_city_or_village','canonical_service_sector','canonical_service_sector_other']){
    assert.match(migration,new RegExp(column));
    assert.match(runtime,new RegExp(column));
  }
  assert.match(runtime,/canonicalPerson/);
});

test('booking-only edit is distinct from explicit revision-guarded canonical update',()=>{
  assert.match(runtime,/save-local/);
  assert.match(runtime,/update-canonical/);
  assert.match(runtime,/personUpdateRevision/);
  assert.match(runtime,/PERSON_REVISION_CONFLICT|تغير السجل منذ فتحه/);
  assert.match(runtime,/sb\([^)]*canonicalPerson/);
  assert.doesNotMatch(runtime,/window\.prompt/);
});

test('historical commercial and demographic state is not rewritten implicitly',()=>{
  assert.match(migration,/booking_type_id=v_type\.id,booking_type_name_snapshot=v_type\.name,notes=/);
  assert.doesNotMatch(migration,/new_text:='booking_type_id=v_type\.id,booking_type_name_snapshot=v_type\.name,price_snapshot=/);
  assert.match(runtime,/يظل السعر التاريخي للحجز محفوظًا عند تغيير النوع/);
  assert.match(runtime,/min:\s*"0"/);
});

test('partial source notifications merge loaded fields instead of erasing them',()=>{
  assert.match(runtime,/Object\.hasOwn\([^,]+,\s*Le\)/);
  assert.match(runtime,/\{\.\.\.s,\.\.\.qe\.person\}/);
});

test('view and mutation remain unavailable to browser roles',()=>{
  assert.match(migration,/security_invoker=true/);
  assert.match(migration,/revoke all on reservations\.participants_canonical from public,anon,authenticated,service_role/);
  assert.match(migration,/revoke all on function reservations_private\.mutate_scoped\(uuid,text,jsonb\) from public,anon,authenticated/);
  assert.equal((migration.match(/update_canonical_person/g)||[]).length,0,'the lifecycle migration must not add a second canonical writer');
});

test('editing selected person retains explicit central/local choice and identity switching is deliberate',()=>{
  assert.match(runtime,/onChange:Z=>\{V\("fullName",Z,\{shouldValidate:!0\}\)\},onClear:/);
  assert.match(runtime,/children:"تغيير الشخص المختار"/);
  assert.match(runtime,/chooseScope/);
  assert.match(runtime,/await r\(!!\(s&&sb\(s,Z\)\)\)/);
  assert.match(runtime,/\.\.\.s\?\{p_person_id:s\.personId/);
});

test('batch booking also requires explicit person switch without retaining inherited fields',()=>{
  assert.match(runtime,/onClear:\(\)=>fe\(P\.id,\{fullName:"",personId:null,selectedPerson:null,personUpdateMode:"",phone:"",gender:"",dateOfBirth:"",age:"",churchOverride:null\}\)/);
  assert.match(runtime,/p_gender:H\.data\.gender/);
  assert.match(runtime,/p_date_of_birth:H\.data\.dateOfBirth/);
});

test('clearing selected name releases inherited identity and renaming requires explicit confirmation',()=>{
  assert.match(runtime,/c&&h&&!b\.target\.value\.trim\(\)\?h\(\):a\(b\.target\.value\)/);
  assert.match(runtime,/Z\.fullName\.trim\(\)!==String\(s\.fullName\|\|""\)\.trim\(\)/);
  assert.match(runtime,/window\.confirm\("تم تغيير الاسم/);
  assert.match(runtime,/إلغاء: ارجع واضغط «تغيير الشخص المختار»/);
});

test('editing an existing central person requires an explicit persistence scope',()=>{
  assert.ok(runtime.includes('تحديد نطاق حفظ بيانات الشخص'));
  assert.ok(runtime.includes('حفظ التعديلات في الحجز الحالي فقط'));
  assert.ok(runtime.includes('تحديث بيانات الشخص في الدليل المركزي'));
  assert.ok(runtime.includes('إلغاء والعودة للنموذج'));
  assert.doesNotMatch(runtime,/children:"اختر نطاق الحفظ"/);
  assert.ok(runtime.includes('الشخص المختار من البنك المركزي: '));
});

test('duplicate booking guard is part of the canonical writer',()=>{
  const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261103163000_reservations_reject_duplicate_event_person.sql'),'utf8');
  assert.ok(migration.includes('RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT'));
  assert.ok(migration.includes('existing_booking.event_id=v_event.id'));
  assert.ok(migration.includes('existing_participant.person_id=v_person_id'));
  assert.ok(runtime.includes('الشخص مسجل بالفعل في هذه الفعالية'));
});

test('single, batch and booking edit require explicit scope when canonical profile changes',()=>{
  assert.equal((runtime.match(/=useReservationScopeDialog\(\)/g)||[]).length,4);
  assert.equal((runtime.match(/function useReservationScopeDialog\(\)/g)||[]).length,1);
  assert.equal((runtime.match(/function hb\(t,a,i\)/g)||[]).length,1);
  assert.doesNotMatch(runtime,/function hb\(\)/);
  assert.match(runtime,/const O=await X\(/);
  assert.match(runtime,/const Ge=await r\(/);
  assert.match(runtime,/const Le=await r\(/);
  assert.match(runtime,/Ge==="update-canonical"/);
  assert.match(runtime,/Le==="update-canonical"/);
});

test('duplicate and successful registration use outcome modals with real booking navigation',()=>{
  assert.match(runtime,/RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT/);
  assert.match(runtime,/existingBookingForPerson/);
  assert.match(runtime,/الشخص مسجل بالفعل في هذه الفعالية/);
  assert.match(runtime,/تم تسجيل الحجز بنجاح/);
  assert.match(runtime,/عرض الحجز الحالي/);
  assert.match(runtime,/عرض المشتركين/);
  assert.match(runtime,/تسجيل شخص جديد/);
});

test('single booking submits the complete validated profile to the one canonical writer',()=>{
  const start=runtime.indexOf('function Lw({defaultEventId:');
  const end=runtime.indexOf('function ',start+15);
  const single=runtime.slice(start,end>start?end:undefined);
  assert.ok(single.includes('resolver:rv(lb)'), 'single registration must validate the complete schema');
  assert.ok(single.includes('onSubmit:w(N)'), 'the form must submit validated values');
  assert.ok(single.includes('const Re=await r(!!(s&&sb(s,Z)))'), 'scope choice must compare the submitted profile');
  for(const [field,arg] of Object.entries({
    fullName:'p_full_name',phone:'p_phone',gender:'p_gender',
    church:'p_church',governorate:'p_governorate',cityOrVillage:'p_city_or_village',
    serviceSector:'p_service_sector',serviceSectorOther:'p_service_sector_other'
  })){
    assert.ok(single.includes(arg+':Z.'+field),arg+' must use submitted '+field);
  }
  assert.ok(single.includes('p_date_of_birth:Z.dateOfBirth'), 'birth date must use submitted dateOfBirth');
  for(const field of ['church','cityOrVillage']){
    assert.ok(single.includes('...S("'+field+'")'),field+' must be registered in the form');
    assert.ok(single.includes('V("'+field+'",Z.'+field+'??""'),field+' must hydrate from the chosen person');
  }
});
