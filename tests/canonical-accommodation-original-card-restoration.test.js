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
  for(const action of ['moveCanonicalAccommodation','removeCanonicalAccommodation'])assert.match(details,new RegExp(action));
  assert.match(details,/arrivalDay/);
  assert.match(details,/person\.phone/);
});

test('restored density uses the original compact width and shared design tokens',()=>{
  assert.match(css,/grid-template-columns:repeat\(auto-fill,minmax\(230px,262px\)\)/);
  assert.match(css,/accommodation-compact-person/);
  assert.match(css,/var\(--app-surface-soft\)/);
  assert.match(css,/canonical-room-child/);
});

test('room grid keeps the historical RTL layout through tablet width and calculates dense columns',()=>{
  const owner=(css.match(/#tab0 \.accommodation-floor-rooms\{[^}]+\}/g)||[]).filter(rule=>rule.includes('display:grid'));
  assert.equal(owner.length,1,'the original scoped grid must have one owner');
  assert.match(owner[0],/direction:rtl/);
  assert.match(owner[0],/justify-content:start/);
  assert.match(owner[0],/gap:8px/);
  assert.doesNotMatch(css,/@media\(max-width:680px\)\{[^}]*rooms-grid/);
  const columns=width=>Math.max(1,Math.floor((width+8)/(230+8)));
  assert.deepEqual([262,500,760,1020].map(columns),[1,2,3,4]);
});

test('compact room restores arrival and key tools while room closure uses the canonical revisioned mutation',async()=>{
  const html=context.renderCanonicalAccommodationCompactOccupants([{occupancyId:'o1',participationId:'p1',bedType:'base',arrivedAt:null,person:{fullName:'نزيل'}}],null,true);
  assert.match(html,/setCanonicalAccommodationArrival\('o1',true\)/);
  let mutation;
  Object.assign(context,{
    currentConferenceSectionCapability:()=>true,
    getCurrentConference:()=>({id:'conference',operationalDay:4}),
    findCanonicalAccommodationEntity:()=>({roomId:'room',revision:7,roomNumber:'12',baseCapacity:2,extraBedCapacity:1,notes:'n',position:3,isClosed:false}),
    confirm:()=>true,
    getConferenceOperationalDay:()=>4,
    showToast:()=>{},formatCanonicalAccommodationAssignmentFailure:()=>'',
    window:{PlatformIntegration:{mutateConferenceAccommodationStructure:(id,operation,payload)=>{mutation={id,operation,payload};return Promise.resolve(true);}}},
    canonicalAccommodationMutation:value=>value
  });
  await context.setCanonicalAccommodationRoomClosed('room',true);
  assert.equal(mutation.id,'conference');
  assert.equal(mutation.operation,'update_accommodation_room');
  assert.equal(mutation.payload.p_expected_revision,7);
  assert.equal(mutation.payload.p_is_closed,true);
  assert.equal(mutation.payload.p_closed_day,4);
});

test('canonical room detail viewport keeps the historic width, two visible footer actions and bounded scrolling',()=>{
  assert.match(css,/#roomModal \.room-editor-modal\{width:min\(880px,calc\(100vw - 32px\)\);max-width:880px\}/);
  assert.match(css,/#roomModal\.canonical-room-readonly \.room-editor-modal\{max-height:calc\(100dvh - 24px\);min-height:0\}/);
  assert.match(css,/#roomModal\.canonical-room-readonly \.mbody\{min-height:0;overflow-y:auto;overscroll-behavior:contain\}/);
  assert.match(css,/#roomModal\.canonical-room-readonly \.room-modal-footer\{grid-template-columns:repeat\(2,minmax\(120px,160px\)\);justify-content:center\}/);
});
