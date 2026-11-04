'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261102161615_canonical_people_reservations_full_profile_cutover.sql'),'utf8');
const runtime=fs.readFileSync(path.join(root,'modules/reservations/reservations-module.js'),'utf8');

test('one guarded canonical writer owns all nine current profile fields',()=>{
  assert.match(migration,/create or replace function platform_private\.update_canonical_person/);
  for(const field of ['fullName','phone','church','gender','dateOfBirth','governorate','cityOrVillage','serviceSector','serviceSectorOther']){
    assert.match(migration,new RegExp(`'${field}'`));
  }
  assert.match(migration,/PERSON_REVISION_CONFLICT/);
  assert.match(migration,/validated_phase1c_device_authorization/);
  assert.match(migration,/reservations\.people\.manage/);
  assert.doesNotMatch(migration,/conference\.people\.manage'.*p_module='reservations'/);
  assert.match(migration,/revoke all on function platform_private\.update_canonical_person/);
});

test('booking creation and edit contracts preserve canonical choice and historical snapshots',()=>{
  assert.match(migration,/insert into platform\.people\(full_name,phone,church,gender,date_of_birth,governorate,city_or_village,service_sector,service_sector_other/);
  assert.match(migration,/p_gender''\s*,''p_date_of_birth''\s*,''p_person_update_revision/);
  assert.match(migration,/if p_args \? ''p_person_update_revision''/);
  assert.match(runtime,/p_date_of_birth:t\.dateOfBirth/);
  assert.match(runtime,/p_person_update_revision:t\.personUpdateRevision/);
  assert.match(runtime,/onClick:\(\)=>a\("save-local"\)/);
  assert.match(runtime,/onClick:\(\)=>a\("update-canonical"\)/);
  assert.match(runtime,/تحديد نطاق حفظ بيانات الشخص/);
  assert.doesNotMatch(runtime,/window\.prompt/);
});

test('canonical readback exposes revision while age zero remains valid',()=>{
  assert.match(migration,/person\.revision person_revision/);
  assert.match(runtime,/personRevision:t\.person_revision/);
  assert.match(runtime,/min:"0"/);
  assert.doesNotMatch(runtime,/\.age<1/);
});
