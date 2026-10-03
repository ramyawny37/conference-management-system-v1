'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');

const read=file=>fs.readFileSync(file,'utf8');
const integrationSource=read('js/platform-integration.js');
const scriptSource=read('script.js');
const repositorySource=read('js/storage/storage-repository.js');
const backupSource=read('js/storage/full-backup.js');
const stateSource=read('state.js');
const snapshotSources=[
  'js/sync/discovered-conference-open-service.js',
  'js/sync/local-snapshot-application.js',
  'js/sync/wrong-remote-binding-repair-service.js',
  'js/sync/automatic-conference-linking.js',
  'js/sync/conflict-resolution-ui.js',
  'js/sync/conference-operational-ui.js'
].map(read);

function environment(){
  const calls=[];
  let fail=null;
  const remote='50000000-0000-4000-8000-000000000001';
  const canonical={conferenceId:remote,organizationId:'organization',name:'Canonical',place:'Canonical place',startDate:'2026-10-01',endDate:'2026-10-03',status:'active',completedAt:null,revision:4,createdAt:'created',updatedAt:'updated',updatedBy:'actor',days:3,nights:2,schedule:['2026-10-01','2026-10-02','2026-10-03']};
  const sandbox={window:null,console,Promise,JSON,Object,String,Array,Date,RegExp,Error,Uint8Array,Math,setTimeout,clearTimeout,crypto:{randomUUID:()=> '50000000-0000-4000-8000-000000000099'},navigator:{onLine:true},document:{addEventListener(){},getElementById(){return null;},querySelector(){return null;}},addEventListener(){},dispatchEvent(){},CustomEvent:function(){},appData:{currentConferenceId:'local',conferences:[{id:'local',organizationId:'legacy-organization',name:'Legacy',startDate:'old-start',endDate:'old-end',status:'active',revision:2,createdAt:'legacy-created',updatedAt:'legacy-updated',updatedBy:'legacy-actor',days:2,nights:1,schedule:['old-start'],conf:{name:'Legacy',startDate:'old-start',endDate:'old-end',days:2,nights:1,schedule:['old-start'],place:'Legacy place'},peopleDb:{people:[{id:'person-old'}]},houses:[{id:'house-old'}]}]},ConferenceLinkStore:{get(id){return id==='local'?{linkStatus:'linked',remoteConferenceId:remote}:null;}},PlatformDeviceSession:{invokeModuleProtected(module,operation,args){calls.push({module,operation,args:JSON.parse(JSON.stringify(args))});if(fail)return Promise.reject({code:fail});if(operation==='get_conference_core')return Promise.resolve(JSON.parse(JSON.stringify(canonical)));if(operation==='mutate_conference_core')return Promise.resolve(Object.assign({},canonical,{name:args.p_name,place:args.p_place,startDate:args.p_start_date,endDate:args.p_end_date,status:args.p_status,revision:5,updatedAt:'updated-2'}));throw new Error('unexpected operation');}}};
  sandbox.window=sandbox;
  vm.runInNewContext(integrationSource,sandbox);
  return {sandbox,calls,remote,canonical,fail:value=>{fail=value;}};
}

test('online hydration and mutation use the one protected Platform boundary',async()=>{
  const env=environment();
  const api=env.sandbox.PlatformIntegration;
  await api.hydrateConferenceCore('local',env.remote);
  const conference=env.sandbox.appData.conferences[0];
  assert.equal(env.calls[0].module,'conference');
  assert.equal(env.calls[0].operation,'get_conference_core');
  assert.deepEqual(env.calls[0].args,{p_conference_id:env.remote});
  assert.equal(conference.name,'Legacy');
  assert.equal(conference.conf.name,'Legacy');
  assert.equal(api.getConferenceCoreState('local').core.name,'Canonical');
  assert.equal(conference.peopleDb.people[0].id,'person-old');
  assert.equal(conference.houses[0].id,'house-old');
  await api.mutateConferenceCore('local',{name:'Edited',place:'Edited place',startDate:'2026-10-02',endDate:'2026-10-04',status:'active'});
  assert.equal(env.calls[1].operation,'mutate_conference_core');
  assert.equal(env.calls[1].args.p_expected_revision,4);
  assert.equal(env.calls[1].args.p_place,'Edited place');
  assert.equal(env.calls[1].args.p_operation_id,'50000000-0000-4000-8000-000000000099');
  assert.equal(conference.name,'Legacy');
  assert.equal(api.getConferenceCoreState('local').core.revision,5);
});

test('canonical core remains separate from the legacy document',async()=>{
  const env=environment();
  const api=env.sandbox.PlatformIntegration;
  await api.hydrateConferenceCore('local',env.remote);
  const incoming={currentConferenceId:'local',conferences:[{id:'local',name:'Snapshot name',startDate:'snapshot-start',endDate:'snapshot-end',status:'completed',revision:99,conf:{name:'Snapshot name'},peopleDb:{people:[{id:'person-new'}]},houses:[{id:'house-new'}]}]};
  const preserved=api.preserveCanonicalConferenceCores(incoming);
  assert.equal(preserved.conferences[0].name,'Snapshot name');
  assert.equal(api.getConferenceCoreState('local').core.name,'Canonical');
  assert.equal(preserved.conferences[0].peopleDb.people[0].id,'person-new');
  assert.equal(preserved.conferences[0].houses[0].id,'house-new');
});

test('conflict and offline failures never become legacy mutations',async()=>{
  const env=environment();
  const api=env.sandbox.PlatformIntegration;
  await api.hydrateConferenceCore('local',env.remote);
  env.fail('CONFERENCE_CORE_REVISION_CONFLICT');
  await assert.rejects(api.mutateConferenceCore('local',{name:'Draft',startDate:'2026-10-01',endDate:'2026-10-03',status:'active'}),error=>error.code==='CONFERENCE_CORE_REVISION_CONFLICT');
  assert.equal(env.sandbox.appData.conferences[0].name,'Legacy');
  env.fail(null);
  env.sandbox.navigator.onLine=false;
  await assert.rejects(api.mutateConferenceCore('local',{name:'Offline draft'}),error=>error.code==='CANONICAL_CONFERENCE_CORE_OFFLINE');
  assert.equal(env.calls.filter(call=>call.operation==='mutate_conference_core').length,1);
});

test('same-page edit preserves its draft on conflict and does not invoke legacy save',()=>{
  const edit=scriptSource.slice(scriptSource.indexOf("if (conferenceDialogMode === 'edit')"),scriptSource.indexOf('var organizationId=',scriptSource.indexOf("if (conferenceDialogMode === 'edit')")));
  assert.match(edit,/integration\.mutateConferenceCore\(current\.id/);
  assert.match(edit,/name:name,place:place,startDate:startDate,endDate:endDate,status:canonicalState\.core\.status/);
  assert.match(edit,/CONFERENCE_CORE_REVISION_CONFLICT[\s\S]*hydrateCanonicalConferenceCore/);
  assert.doesNotMatch(edit,/\bsave\s*\(/);
  const failureStart=edit.indexOf('catch(function(error)');
  const failure=edit.slice(failureStart,
    edit.indexOf('      });',failureStart)+'      });'.length);
  assert.doesNotMatch(failure,/closeNewConferenceModal\(\)/);
  assert.match(scriptSource,/editCurrentConference[\s\S]*navigator\.onLine===false/);
});

test('snapshot, recovery and realtime application share the canonical core guard',()=>{
  for(const source of snapshotSources){
    assert.match(source,/preserveCanonicalConferenceCores/);
  }
  assert.equal((integrationSource.match(/function hydrateConferenceCore\(/g)||[]).length,1);
  assert.equal((integrationSource.match(/function mutateConferenceCore\(/g)||[]).length,1);
  assert.doesNotMatch(integrationSource,/localStorage|indexedDB|conference_snapshots|OfflineSyncQueue|WebSocket|channel\s*\(/i);
});

test('linked serialization removes all canonical-owned business roots',async()=>{
  const env=environment();
  const api=env.sandbox.PlatformIntegration;
  await api.hydrateConferenceCore('local',env.remote);
  await api.mutateConferenceCore('local',{name:'B',startDate:'2026-10-02',endDate:'2026-10-04',status:'active'});
  const live=env.sandbox.appData.conferences[0];
  live.peopleDb.people.push({id:'person-new'});
  live.houses.push({id:'house-new'});
  const serialized=api.prepareLegacyConferenceSerialization(env.sandbox.appData);
  const persisted=serialized.conferences[0];
  assert.equal(live.name,'Legacy');
  assert.equal(persisted.name,undefined);
  assert.equal(persisted.conf,undefined);
  assert.equal(persisted.peopleDb,undefined);
  assert.equal(persisted.houses,undefined);
});

test('one sanitizer protects repository queue, mirrors, backups and exports',()=>{
  assert.equal((integrationSource.match(/function prepareLegacyConferenceSerialization\(/g)||[]).length,1);
  assert.match(repositorySource,/persistenceInput=platform\.prepareLegacyConferenceSerialization/);
  assert.match(repositorySource,/var queuedSnapshot=cloneSnapshotData\(inspected\.snapshot\)/);
  assert.match(repositorySource,/saveAppSnapshot\(queuedSnapshot,metadata\)/);
  assert.match(repositorySource,/handleLocalSave\(queuedSnapshot\)/);
  assert.match(repositorySource,/JSON\.stringify\(queuedSnapshot\)/);
  assert.match(repositorySource,/createLocalBackup\(persistenceInput,reason\)/);
  assert.match(backupSource,/serializationInput=platform&&[\s\S]*platform\.prepareLegacyConferenceSerialization\(appData\)/);
  assert.match(scriptSource,/JSON\.stringify\(serializationInput,null,2\)/);
  assert.match(stateSource,/getConferenceCoreState\(current\.id\)\)return/);
  assert.doesNotMatch(repositorySource,/function prepareLegacyConferenceSerialization/);
  assert.doesNotMatch(backupSource,/function prepareLegacyConferenceSerialization/);
});
