'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');
const integrationSource=fs.readFileSync('js/platform-integration.js','utf8');
const scriptSource=fs.readFileSync('script.js','utf8');
const peopleSource=fs.readFileSync('people.js','utf8');
const permissionSource=fs.readFileSync('js/sync/conference-permission-contract.js','utf8');

function environment(){
  const calls=[];
  let failure='';
  const remote='50000000-0000-4000-8000-000000000001';
  const person={personId:'60000000-0000-4000-8000-000000000001',fullName:'Canonical Person',phone:'0100',gender:'female',dateOfBirth:'1990-01-02',church:'Canonical Church'};
  const participation={participationId:'70000000-0000-4000-8000-000000000001',conferenceId:remote,personId:person.personId,status:'active',revision:3,createdAt:'created',updatedAt:'updated',createdBy:'actor',updatedBy:'actor',person};
  const legacyPerson={id:'legacy-person',fullName:'Legacy Person'};
  const sandbox={window:null,console,Promise,JSON,Object,String,Array,Date,RegExp,Error,Uint8Array,Math,setTimeout,clearTimeout,navigator:{onLine:true},crypto:{randomUUID:()=>`80000000-0000-4000-8000-00000000000${calls.length}`},document:{addEventListener(){},getElementById(){return null;},querySelector(){return null;}},addEventListener(){},dispatchEvent(){},CustomEvent:function(){},appData:{currentConferenceId:'local',conferences:[{id:'local',peopleDb:{people:[legacyPerson]}}]},ConferenceLinkStore:{get(id){return id==='local'?{linkStatus:'linked',remoteConferenceId:remote}:null;}},PlatformDeviceSession:{invokeModuleProtected(module,operation,args){calls.push({module,operation,args:JSON.parse(JSON.stringify(args))});if(failure)return Promise.reject({code:failure});if(operation==='list_conference_participations')return Promise.resolve({conferenceId:remote,totalCount:1,activeCount:1,apologizedCount:0,items:[participation]});if(operation==='create_conference_participation_with_person'){const createdPerson={personId:'60000000-0000-4000-8000-000000000002',fullName:args.p_full_name,phone:args.p_phone,gender:args.p_gender,dateOfBirth:args.p_date_of_birth,church:args.p_church};return Promise.resolve({participationId:'70000000-0000-4000-8000-000000000002',conferenceId:remote,personId:createdPerson.personId,status:'active',revision:1,createdAt:'created-2',updatedAt:'updated-2',createdBy:'actor',updatedBy:'actor',person:createdPerson});}if(operation==='set_conference_participation_status')return Promise.resolve({participationId:participation.participationId,conferenceId:remote,personId:person.personId,status:args.p_status,revision:args.p_expected_revision+1,updatedAt:'updated-2',updatedBy:'actor'});if(operation==='delete_conference_participation')return Promise.resolve({participationId:participation.participationId,conferenceId:remote,personId:person.personId,deleted:true});throw new Error('unexpected operation');}}};
  sandbox.window=sandbox;
  vm.runInNewContext(integrationSource,sandbox);
  return {sandbox,calls,remote,legacyPerson,fail(value){failure=value;}};
}

test('linked hydration and mutations use only canonical protected operations',async()=>{
  const env=environment(),api=env.sandbox.PlatformIntegration;
  await api.hydrateConferenceParticipations('local',env.remote);
  assert.deepEqual(env.calls[0],{module:'conference',operation:'list_conference_participations',args:{p_conference_id:env.remote}});
  assert.equal(api.getConferenceParticipationState('local').items[0].person.fullName,'Canonical Person');
  const legacyBefore=JSON.stringify(env.sandbox.appData.conferences[0].peopleDb);
  await api.createConferenceParticipationWithPerson('local',{fullName:'New Person',phone:'011',gender:'male',dateOfBirth:null,church:'Church'});
  assert.equal(env.calls[1].operation,'create_conference_participation_with_person');
  assert.deepEqual(env.calls[1].args,{p_operation_id:'80000000-0000-4000-8000-000000000001',p_conference_id:env.remote,p_full_name:'New Person',p_phone:'011',p_gender:'male',p_date_of_birth:null,p_church:'Church'});
  await api.setConferenceParticipationStatus('local','70000000-0000-4000-8000-000000000001','apologized');
  assert.equal(env.calls[2].operation,'set_conference_participation_status');
  assert.equal(env.calls[2].args.p_participation_id,'70000000-0000-4000-8000-000000000001');
  assert.equal(env.calls[2].args.p_expected_revision,3);
  assert.equal(api.getConferenceParticipationState('local').items[0].status,'apologized');
  await api.setConferenceParticipationStatus('local','70000000-0000-4000-8000-000000000001','active');
  assert.equal(env.calls[3].args.p_expected_revision,4);
  assert.equal(api.getConferenceParticipationState('local').items[0].status,'active');
  await api.deleteConferenceParticipation('local','70000000-0000-4000-8000-000000000001');
  assert.equal(env.calls[4].operation,'delete_conference_participation');
  assert.equal(env.calls[4].args.p_expected_revision,5);
  assert.equal(api.getConferenceParticipationState('local').items.some(item=>item.personId===env.legacyPerson.id),false);
  assert.equal(JSON.stringify(env.sandbox.appData.conferences[0].peopleDb),legacyBefore);
});

test('canonical failures preserve canonical state and never fall back to peopleDb',async()=>{
  const env=environment(),api=env.sandbox.PlatformIntegration;
  env.fail('READ_FAILED');
  await assert.rejects(api.hydrateConferenceParticipations('local',env.remote),error=>error.code==='READ_FAILED');
  assert.equal(api.getConferenceParticipationState('local'),null);
  assert.equal(env.calls.length,1);
  env.fail('');
  await api.hydrateConferenceParticipations('local',env.remote);
  const before=JSON.stringify(api.getConferenceParticipationState('local'));
  env.fail('MUTATION_FAILED');
  await assert.rejects(api.setConferenceParticipationStatus('local','70000000-0000-4000-8000-000000000001','apologized'),error=>error.code==='MUTATION_FAILED');
  assert.equal(JSON.stringify(api.getConferenceParticipationState('local')),before);
  assert.equal(env.sandbox.appData.conferences[0].peopleDb.people[0].fullName,'Legacy Person');
});

test('linked rendering uses nested canonical Person projection, status and Participation IDs',()=>{
  const start=scriptSource.indexOf('function renderPeopleDatabaseSection()');
  const end=scriptSource.indexOf('function importPeopleExcelFile',start);
  const source=scriptSource.slice(start,end);
  let legacyReads=0;
  const state={items:[{participationId:'part-1',status:'apologized',person:{fullName:'Projected Name',phone:'0123',gender:'female',dateOfBirth:'1991-02-03',church:'Projected Church'}}]};
  const sandbox={getCurrentConference:()=>({id:'linked'}),getCanonicalConferenceCoreLink:()=>({remoteConferenceId:'remote'}),window:{PlatformIntegration:{getConferenceParticipationState:()=>state}},getPeopleList(){legacyReads++;return [{fullName:'Legacy Name'}];},esc:value=>String(value),personMetaText:()=>'',console};
  vm.runInNewContext(source,sandbox);
  const html=sandbox.renderPeopleDatabaseSection();
  assert.equal(legacyReads,0);
  assert.match(html,/Projected Name/); assert.match(html,/Projected Church/); assert.match(html,/0123/);
  assert.match(html,/female/); assert.match(html,/1991-02-03/); assert.match(html,/apologized/);
  assert.match(html,/setCanonicalParticipantStatus\('part-1','active'\)/);
  assert.match(html,/deletePersonFromDatabase\('part-1'\)/);
  assert.doesNotMatch(html,/Legacy Name|استيراد ملف إكسل|openPersonDialog\('part-1'/);
});

test('linked handlers retire legacy save, peopleDb mutation, import and permission authority',()=>{
  const save=scriptSource.slice(scriptSource.indexOf('function savePersonDialog()'),scriptSource.indexOf('function setCanonicalParticipantStatus'));
  const deletion=scriptSource.slice(scriptSource.indexOf('function deletePersonFromDatabase'),scriptSource.indexOf('function savePersonDialog'));
  const importing=scriptSource.slice(scriptSource.indexOf('function importPeopleExcelFile'),scriptSource.indexOf('function openPersonDialog'));
  assert.match(save,/createConferenceParticipationWithPerson/);
  assert.match(deletion,/deleteConferenceParticipation/);
  assert.match(importing,/getCanonicalConferenceCoreLink[\s\S]*return false;[\s\S]*ConferencePermissionShadowGate/);
  const linkedSave=save.slice(0,save.indexOf("if(window.ConferencePermissionShadowGate"));
  const linkedDelete=deletion.slice(0,deletion.indexOf("if(window.ConferencePermissionShadowGate"));
  for(const branch of [linkedSave,linkedDelete])assert.doesNotMatch(branch,/\bsave\s*\(|upsertPerson|getPeopleDb|peopleDb/);
  assert.match(scriptSource,/ge\('person_age'\)\.disabled=linked/);
  assert.match(scriptSource,/person_date_of_birth'\)\.value\|\|null/);
  assert.match(scriptSource,/person_age_field'\)\.style\.display=linked\?'none'/);
  assert.match(scriptSource,/person_notes_field'\)\.style\.display=linked\?'none'/);
  const participationIntegration=integrationSource.slice(integrationSource.indexOf('function operationId'),integrationSource.indexOf('function moduleIdFromRoute'));
  assert.doesNotMatch(participationIntegration,/supabase|\.rpc\(|conference_snapshots|peopleDb|localStorage|indexedDB/i);
  assert.doesNotMatch(peopleSource,/PlatformIntegration|create_conference_participation/);
  assert.match(permissionSource,/mutation\('savePersonDialog'[\s\S]*mutation\('deletePersonFromDatabase'[\s\S]*mutation\('importPeopleExcelFile'/);
});

test('local-only legacy participant behavior remains intentionally available',()=>{
  assert.match(scriptSource,/if\(window\.ConferencePermissionShadowGate[^\n]+savePersonDialog/);
  assert.match(scriptSource,/var person = upsertPerson\(personData, true\)/);
  assert.match(scriptSource,/if\(!save\(\)\)return false;/);
  assert.match(scriptSource,/peopleDb\.people = newPeople/);
  assert.match(scriptSource,/XLSX\.utils\.sheet_to_json/);
});
