'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const script=fs.readFileSync('script.js','utf8');
const css=fs.readFileSync('style.css','utf8');
const helperStart=script.indexOf('function isCanonicalAccommodationChild(');
const helperEnd=script.indexOf('\nfunction openCanonicalAccommodationRoomDetails(',helperStart);
const helpers=script.slice(helperStart,helperEnd);
const context={esc:value=>String(value).replace(/[&<>"']/g,'_')};
vm.runInNewContext(helpers,context);

test('children group under an exact guardian participation once and unresolved links stay explicit',()=>{
  const adult={occupancyId:'oa',participationId:'adult',bedType:'base',person:{fullName:'ولي الأمر'}};
  const shared={occupancyId:'os',participationId:'shared',guardianParticipationId:'adult',bedType:'shared',person:{fullName:'طفل مشترك'}};
  const extra={occupancyId:'oe',participationId:'extra',guardianParticipationId:'adult',bedType:'extra',extraBedPersonType:'child',person:{fullName:'طفل إضافي'}};
  const base={occupancyId:'ob',participationId:'base',guardianParticipationId:'adult',bedType:'base',person:{fullName:'طفل أساسي'}};
  const orphan={occupancyId:'oo',participationId:'orphan',guardianParticipationId:'missing',bedType:'shared',person:{fullName:'طفل غير مرتبط'}};
  const grouped=context.groupCanonicalAccommodationOccupancies([shared,adult,orphan,extra,base]);
  assert.equal(grouped.rows.length,1);
  assert.deepEqual(Array.from(grouped.rows[0].children,item=>item.occupancyId),['os','oe','ob']);
  assert.deepEqual(Array.from(grouped.unlinkedChildren,item=>item.occupancyId),['oo']);
  assert.equal(grouped.childCount,4);
  const html=context.renderCanonicalAccommodationCompactOccupants([shared,adult,orphan,extra,base],null);
  assert.equal(html.split('>ولي الأمر</span>').length-1,1,'guardian');
  for(const name of ['طفل مشترك','طفل إضافي','طفل أساسي','طفل غير مرتبط'])assert.equal(html.split(name).length-1,1,name);
  assert.ok(html.indexOf('ولي الأمر')<html.indexOf('طفل مشترك'));
  assert.match(html,/ربط ولي الأمر مفقود/);
});

test('child labels and bed capacity follow bedType rather than age or display position',()=>{
  assert.equal(context.canonicalAccommodationChildBedLabel({bedType:'shared'}),'طفل مرافق — بدون سرير');
  assert.equal(context.canonicalAccommodationChildBedLabel({bedType:'base',guardianParticipationId:'adult'}),'طفل — سرير أساسي');
  assert.equal(context.canonicalAccommodationChildBedLabel({bedType:'extra',extraBedPersonType:'child'}),'طفل — سرير إضافي');
  const occupancies=[{bedType:'shared'},{bedType:'base',guardianParticipationId:'adult'},{bedType:'extra',extraBedPersonType:'child'}];
  assert.equal(occupancies.filter(item=>item.bedType!=='shared').length,2);
});

test('compact card excludes full person metadata and keeps full actions in room details',()=>{
  const renderStart=script.indexOf('function renderCanonicalAccommodation(state){');
  const renderEnd=script.indexOf('\nfunction renderAccommodation()',renderStart);
  const renderer=script.slice(renderStart,renderEnd);
  const cardStart=renderer.indexOf('<article class="rcard room-card accommodation-room-card');
  const cardEnd=renderer.indexOf("+'</div></div></article>';",cardStart);
  const card=renderer.slice(cardStart,cardEnd);
  assert.match(card,/renderCanonicalAccommodationCompactOccupants/);
  assert.doesNotMatch(card,/person\.phone|person\.church|arrivalDay|leaveDay|editCanonicalAccommodation|moveCanonicalAccommodation|removeCanonicalAccommodation/);
  const details=script.slice(script.indexOf('function renderCanonicalAccommodationDetailOccupant('),renderStart);
  for(const action of ['editCanonicalAccommodation','moveCanonicalAccommodation','removeCanonicalAccommodation'])assert.match(details,new RegExp(action));
  assert.match(details,/arrivalDay/);
  assert.match(details,/person\.phone/);
});

test('restored density uses the original compact width and shared design tokens',()=>{
  assert.match(css,/grid-template-columns:repeat\(auto-fill,minmax\(230px,262px\)\)/);
  assert.match(css,/accommodation-compact-person/);
  assert.match(css,/var\(--app-surface-soft\)/);
  assert.match(css,/canonical-room-child/);
});
