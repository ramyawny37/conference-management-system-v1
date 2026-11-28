'use strict';const assert=require('node:assert/strict'),fs=require('node:fs'),test=require('node:test');const ref=fs.readFileSync('js/platform-reference-data.js','utf8'),reservations=fs.readFileSync('modules/reservations/reservations-module.js','utf8'),publicForm=fs.readFileSync('public-registration.js','utf8');
test('profile reference data has one browser authority',()=>{assert.match(ref,/PlatformReferenceData/);assert.match(reservations,/window\.PlatformReferenceData\.governorates/);assert.match(reservations,/window\.PlatformReferenceData\.serviceSectors/);assert.doesNotMatch(reservations,/is=\["القاهرة","الجيزة"/);assert.match(publicForm,/reference\.governorates/);assert.match(publicForm,/reference\.serviceSectors/)});
test('family public form consumes canonical reference data and other-sector rule',()=>{assert.match(publicForm,/data-f="governorate"/);assert.match(publicForm,/data-f="serviceSector"/);assert.match(publicForm,/m\.serviceSector==='other'/);assert.match(publicForm,/serviceSectorOther/);assert.match(publicForm,/submit_family/);assert.match(publicForm,/child_dependent/);assert.match(publicForm,/guardianMemberKey/)});

test('every child requires guardian and date of birth in the canonical family form',()=>{assert.match(publicForm,/m\.role\.indexOf\('child_'\)===0&&!m\.guardianMemberKey/);assert.match(publicForm,/data-f="dateOfBirth" type="date" required/);assert.match(publicForm,/guardians=members\.slice\(0,i\)/)});

test('canonical service-sector labels and new sector stay in the single platform reference catalog',()=>{
 assert.match(ref,/value:'widows',label:'أرملة صرفه'/);
 assert.match(ref,/value:'widows-daughters',label:'البنات'/);
 assert.match(ref,/value:'house-of-prayer',label:'بيت الصلاة'/);
 assert.doesNotMatch(ref,/label:'أرامل'|label:'بنات الأرامل'/);
});
