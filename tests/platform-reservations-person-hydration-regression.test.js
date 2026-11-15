const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('modules/reservations/reservations-module.js', 'utf8');

test('existing-person selection preserves canonical identity and revision', () => {
  assert.match(source, /personId:ge\([A-Za-z_$][\w$]*,"personId"\)/);
  assert.match(source, /revision:nt\([A-Za-z_$][\w$]*,"revision"\)/);
  assert.match(source, /p_person_update_revision:[A-Za-z_$][\w$]*\.revision/);
});

test('selected person hydration retains the canonical shared fields exposed by search', () => {
  assert.match(source, /fullName:ge\([A-Za-z_$][\w$]*,"fullName"\)/);
  assert.match(source, /phone:[A-Za-z_$][\w$]*\.phone==null\?null:ge\([A-Za-z_$][\w$]*,"phone"\)/);
  assert.match(source, /church:[A-Za-z_$][\w$]*\.church==null\?null:ge\([A-Za-z_$][\w$]*,"church"\)/);
});

test('booking age remains an integer in the accepted domain', () => {
  assert.match(source, /\.transform\([A-Za-z_$][\w$]*=>Number\([A-Za-z_$][\w$]*\)\)\.pipe\(/);
  assert.match(source, /\.int\(/);
  assert.match(source, /\.max\(120,/);
});

test('booking creation preserves the canonical age mutation payload', () => {
  assert.match(source, /p_age:[A-Za-z_$][\w$]*\.age/);
});

test('service sector remains a fixed reference list in the booking form', () => {
  assert.ok(source.includes('Bi.map(Z=>'));
});

test('canonical booking payload includes address and service',()=>{
  for(const key of ['p_governorate','p_city_or_village','p_service_sector','p_service_sector_other']){
    assert.match(source,new RegExp(key+':[A-Za-z_$][\\w$]*\\.'));
  }
});
