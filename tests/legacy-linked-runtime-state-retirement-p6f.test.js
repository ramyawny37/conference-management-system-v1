'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');

const core=fs.readFileSync('core.js','utf8');
const people=fs.readFileSync('people.js','utf8');
const script=fs.readFileSync('script.js','utf8');
const integration=fs.readFileSync('js/platform-integration.js','utf8');
const permission=fs.readFileSync('js/sync/conference-permission-contract.js','utf8');
const index=fs.readFileSync('index.html','utf8');
const serviceWorker=fs.readFileSync('service-worker.js','utf8');

function functionSource(source,name){
  const start=source.indexOf(`function ${name}(`);
  assert.notEqual(start,-1,`${name} exists`);
  const body=source.indexOf('{',start);let depth=0,quote='',escaped=false;
  for(let cursor=body;cursor<source.length;cursor++){
    const char=source[cursor];
    if(quote){if(escaped)escaped=false;else if(char==='\\')escaped=true;else if(char===quote)quote='';continue;}
    if(char==='"'||char==="'"||char==='`'){quote=char;continue;}
    if(char==='{')depth++;else if(char==='}'&&--depth===0)return source.slice(start,cursor+1);
  }
  throw new Error(`${name} is incomplete`);
}

test('linked People helpers reject legacy reads, writes and normalization',()=>{
  const names=['requireLocalOnlyPeopleConference','getPeopleDb','getPeopleList','getPersonById','findExistingPerson','upsertPerson','normalizeConferencePeopleReferences','linkRoomPeopleToDatabase'];
  const sandbox={getCurrentConference:()=>({id:'linked',peopleDb:{people:[{id:'legacy'}]},houses:[]}),getCanonicalConferenceCoreLink:()=>({remoteConferenceId:'remote'}),Date,Error,String,Object,Array,console};
  names.forEach(name=>vm.runInNewContext(functionSource(people,name),sandbox));
  assert.throws(()=>sandbox.getPeopleList(),/LINKED_CONFERENCE_LEGACY_PEOPLE_FORBIDDEN/);
  assert.throws(()=>sandbox.upsertPerson({fullName:'Forbidden'},true),/LINKED_CONFERENCE_LEGACY_PEOPLE_FORBIDDEN/);
  assert.throws(()=>sandbox.normalizeConferencePeopleReferences({id:'linked',peopleDb:{people:[]}}),/LINKED_CONFERENCE_LEGACY_PEOPLE_NORMALIZATION_FORBIDDEN/);
  assert.throws(()=>sandbox.linkRoomPeopleToDatabase({id:'linked',houses:[]}),/LINKED_CONFERENCE_LEGACY_PEOPLE_LINK_FORBIDDEN/);
});

test('participant handlers dispatch canonical and local-only ownership explicitly',()=>{
  const saveDispatcher=functionSource(script,'savePersonDialog');
  const canonicalSave=functionSource(script,'saveCanonicalConferenceParticipant');
  const localSave=functionSource(script,'saveLocalOnlyPersonDialog');
  const deleteDispatcher=functionSource(script,'deletePersonFromDatabase');
  const canonicalDelete=functionSource(script,'deleteCanonicalConferenceParticipation');
  const localDelete=functionSource(script,'deleteLocalOnlyPersonFromDatabase');
  const importDispatcher=functionSource(script,'importPeopleExcelFile');
  const localImport=functionSource(script,'importLocalOnlyPeopleExcelFile');
  assert.match(saveDispatcher,/getCanonicalConferenceCoreLink[\s\S]*saveCanonicalConferenceParticipant[\s\S]*saveLocalOnlyPersonDialog/);
  assert.match(deleteDispatcher,/getCanonicalConferenceCoreLink[\s\S]*deleteCanonicalConferenceParticipation[\s\S]*deleteLocalOnlyPersonFromDatabase/);
  for(const source of [canonicalSave,canonicalDelete]){
    assert.doesNotMatch(source,/peopleDb|getPeopleDb|getPeopleList|upsertPerson|\bsave\s*\(/);
  }
  assert.match(localSave,/upsertPerson[\s\S]*save\(\)/);
  assert.match(localDelete,/getPeopleList[\s\S]*getPeopleDb[\s\S]*save\(\)/);
  assert.match(importDispatcher,/getCanonicalConferenceCoreLink[\s\S]*return false[\s\S]*importLocalOnlyPeopleExcelFile/);
  assert.doesNotMatch(importDispatcher,/upsertPerson|\bsave\s*\(/);
  assert.match(localImport,/XLSX[\s\S]*upsertPerson[\s\S]*save\(\)/);
});

test('linked runtime normalization cannot hydrate or mirror legacy People and Accommodation',()=>{
  const appNormalizer=functionSource(core,'normalizeAppData_core');
  const conferenceNormalizer=functionSource(core,'normalizeConference');
  assert.match(appNormalizer,/linkedRuntime[\s\S]*!linkedRuntime\)linkRoomPeopleToDatabase/);
  assert.match(appNormalizer,/!linkedRuntime&&typeof normalizeConferencePeopleReferences/);
  assert.match(conferenceNormalizer,/linkedRuntime[\s\S]*if\(!linkedRuntime\)confObj\.houses/);
  assert.match(conferenceNormalizer,/if\(!linkedRuntime\)\{[\s\S]*confObj\.peopleDb/);
  assert.match(conferenceNormalizer,/if\(!linkedRuntime\)migrateToV3/);
});

test('legacy Accommodation mutation surface is explicitly local-only',()=>{
  const gate=functionSource(script,'requireLocalOnlyAccommodationMutation');
  assert.match(gate,/getCanonicalConferenceCoreLink[\s\S]*LINKED_CONFERENCE_LEGACY_ACCOMMODATION_FORBIDDEN[\s\S]*requireAccommodationMutation/);
  const handlers=['saveHouse','deleteHouse','setAccommodationPersonArrival','setAccommodationRoomKeyHolder','removeConferenceHouseFromAccommodation','addAvailableTemplateRoom','toggleActiveRoom','setAllActiveRoomsForFloor','setAllActiveRoomsForHouse','partialTransferConfirmSelection','saveRoomData','clearConferenceRoom','toggleConferenceRoomClosed','deleteConferenceRoom','applyConferenceHouseTemplate','importHouseFromTemplate'];
  handlers.forEach(name=>assert.match(functionSource(script,name),/requireLocalOnlyAccommodationMutation\(\)/,name));
  const canonical=script.slice(script.indexOf('function canonicalAccommodationMutation('),script.indexOf('function renderCanonicalAccommodation'));
  assert.doesNotMatch(canonical,/conference\.houses|room\.guests|room\.children|linkRoomPeopleToDatabase|\bsave\s*\(/);
  assert.match(canonical,/mutateConferenceAccommodationStructure|assignConferenceAccommodation|moveConferenceAccommodation|removeConferenceAccommodation/);
});

test('canonical downstream remains isolated and no replacement owner is introduced',()=>{
  const canonicalIntegration=integration.slice(integration.indexOf('function accommodationPerson'),integration.indexOf('function moduleIdFromRoute'));
  assert.doesNotMatch(canonicalIntegration,/peopleDb|conference_snapshots|localStorage|indexedDB|room\.guests|room\.children/i);
  assert.doesNotMatch(script,/mirrorCanonical|canonicalToLegacy|legacyParticipantService|legacyAccommodationService/);
  assert.match(permission,/Local-only legacy People permission/);
  assert.match(permission,/Local-only legacy Accommodation/);
});

test('dead duplicate and linked snapshot recovery runtime are absent while Reservations remain',()=>{
  assert.equal(fs.existsSync('tmp_script.js'),false);
  assert.doesNotMatch(index,/tmp_script/);
  assert.doesNotMatch(serviceWorker,/tmp_script/);
  assert.equal(fs.existsSync('js/recovery/recovery-preview-service.js'),false);
  assert.equal(fs.existsSync('modules/reservations'),true);
  assert.equal(fs.existsSync('supabase/migrations/20260909160000_reservations_conference_lifecycle_round1.sql'),true);
});
