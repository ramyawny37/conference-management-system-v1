'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');

const activationSource=fs.readFileSync('js/sync/conference-activation-authorization.js','utf8');
const schedulerSource=fs.readFileSync('js/sync/sync-scheduler-state.js','utf8');
const orchestratorSource=fs.readFileSync('js/sync/automatic-sync-orchestrator.js','utf8');
const scriptSource=fs.readFileSync('script.js','utf8');
const userId='10000000-0000-4000-8000-000000000001';
const remoteId='20000000-0000-4000-8000-000000000001';

function delay(ms){return new Promise(resolve=>setTimeout(resolve,ms));}
function environment(){
  const sandbox={window:null,Promise,Date,JSON,Object,String,Number,Math,
    structuredClone:global.structuredClone,navigator:{onLine:true},
    setTimeout,clearTimeout,addEventListener(){},removeEventListener(){},
    SupabaseAuth:{getState(){return {authenticated:true,user:{id:userId}};}},
    SupabaseClientLayer:{getState(){return {configured:true,available:true};},getClient(){return {};}}};
  sandbox.window=sandbox;
  vm.runInNewContext(activationSource,sandbox);
  vm.runInNewContext(schedulerSource,sandbox);
  vm.runInNewContext(orchestratorSource,sandbox);
  return sandbox;
}
function options(gate,run){return {
  debounceMs:0,activationAuthorization:gate,
  getCurrentConference(){return {id:'local-a'};},
  preferences:{get(){return {cloudSyncEnabled:true,automaticSyncEnabled:true};}},
  serviceCheck(){return Promise.resolve({available:true});},
  stateResolver:{resolve(){return Promise.resolve({ok:true,status:'linked',data:{link:{localConferenceId:'local-a',remoteConferenceId:remoteId,knownRevision:1,linkStatus:'linked'},remoteConferenceId:remoteId}});}},
  integration:{getConferenceSyncState(){return {context:{localConferenceId:'local-a',conferenceId:remoteId,baseRevision:1}};}},
  queueRunner:{run}
};}

test('canonical sync permission keeps the actual automatic-sync orchestrator eligible',async()=>{
  const env=environment(),gate=env.ConferenceActivationAuthorization;
  const decision=gate.authorizeCloud({localConferenceId:'local-a',remoteConferenceId:remoteId,authenticatedUserId:userId,canonicalAccess:true,capabilities:{edit:true,sync:true}});
  assert.equal(decision.role,null);assert.equal(decision.authority,'canonical');
  assert.equal(gate.activate('local-a'),true);
  let runs=0;
  env.AutomaticSyncOrchestrator.start(options(gate,()=>{runs++;return Promise.resolve({ok:true,status:'empty'});}));
  await delay(20);env.AutomaticSyncOrchestrator.stop();
  assert.equal(runs,1);
});

test('conference access view alone does not grant edit or sync and remains ineligible',async()=>{
  const env=environment(),gate=env.ConferenceActivationAuthorization;
  gate.authorizeCloud({localConferenceId:'local-a',remoteConferenceId:remoteId,authenticatedUserId:userId,canonicalAccess:true,capabilities:{edit:false,sync:false}});
  gate.activate('local-a');
  let runs=0,resolutions=0;
  const deniedOptions=options(gate,()=>{runs++;return Promise.resolve({ok:true,status:'empty'});});
  deniedOptions.stateResolver={resolve(){resolutions++;return Promise.resolve({ok:true,status:'linked'});}};
  env.AutomaticSyncOrchestrator.start(deniedOptions);
  await delay(20);env.AutomaticSyncOrchestrator.stop();
  assert.equal(resolutions,0);assert.equal(gate.canEdit('local-a'),false);assert.equal(gate.canSync('local-a'),false);
});

test('the shared edit gate remains for Accommodation while linked Transport uses its exact manage capability',()=>{
  const body=scriptSource.slice(scriptSource.indexOf('function canEditCurrentConferenceData'),scriptSource.indexOf('function beginAccommodationEditing'));
  assert.match(body,/authorization\.canEdit\(current\.id\)/);
  assert.equal((scriptSource.match(/canEditCurrentConferenceData\(\)/g)||[]).length,3);
  assert.match(scriptSource,/function canEditCurrentConferenceAccommodation\(\)[\s\S]*?canEditCurrentConferenceData\(\)/);
  assert.match(scriptSource,/var canEditTransport=canonicalTransport\?!!canonicalState\.canManage:canEditCurrentConferenceData\(\)/);
});
