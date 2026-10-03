'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');
const source=fs.readFileSync('js/sync/discovered-conference-open-service.js','utf8');
const remote='10000000-0000-4000-8000-000000000001';
function environment(failure){
  const calls=[];let data={conferences:[],currentConferenceId:null};const links={};
  const hydrate=name=>function(){calls.push(name);return name===failure?Promise.reject({code:'FAILED_'+name}):Promise.resolve({});};
  const sandbox={window:null,structuredClone:value=>JSON.parse(JSON.stringify(value)),appData:data,
    CanonicalConferenceDiscovery:{listAccessibleConferences:()=>Promise.resolve({ok:true,data:{conferences:[{id:remote,name:'Canonical',status:'active',capabilities:{edit:true}}]}})},
    ConferenceLinkStore:{findByRemoteId:id=>Object.values(links).find(x=>x.remoteConferenceId===id)||null,save:value=>{links[value.localConferenceId]=value;return {ok:true};}},
    PlatformIntegration:{hydrateConferenceCore:hydrate('core'),hydrateConferenceParticipations:hydrate('participation'),hydrateConferenceAccommodation:hydrate('accommodation'),hydrateConferenceAirConditioning:hydrate('air_conditioning')},
    CanonicalConferenceBranding:{hydrate:hydrate('branding')},CanonicalConferenceFinance:{hydrate:hydrate('finance')},CanonicalConferenceTransport:{hydrate:hydrate('transport')},CanonicalConferenceRestaurant:{hydrate:hydrate('restaurant')},
    activatePersistedConferenceById:()=>{calls.push('activate');return true;}};
  sandbox.window=sandbox;vm.runInNewContext(source,sandbox);
  return {sandbox,calls,links,getData:()=>sandbox.appData};
}
test('linked open hydrates every canonical owner without snapshot infrastructure',async()=>{
  const env=environment();const result=await env.sandbox.DiscoveredConferenceOpenService.open(remote);
  assert.equal(result.ok,true);assert.equal(result.status,'opened');
  assert.deepEqual(env.calls,['core','participation','accommodation','air_conditioning','branding','finance','transport','restaurant','activate']);
  assert.equal(env.links[remote].remoteConferenceId,remote);
  assert.equal(env.getData().conferences[0].name,'Canonical');
});
test('canonical hydration failure has no fallback and does not activate',async()=>{
  const env=environment('finance');const result=await env.sandbox.DiscoveredConferenceOpenService.open(remote);
  assert.equal(result.ok,false);assert.equal(result.status,'canonical_hydration_failed');assert.equal(env.calls.includes('activate'),false);
});
test('runtime contains no linked whole-document read, revision, queue, or recovery contract',()=>{
  assert.doesNotMatch(source,/conference_snapshots|SupabaseSnapshotSync|OfflineSyncQueue|snapshotRevision|baseRevision|needs_resolution|recovery|fallback/i);
});
