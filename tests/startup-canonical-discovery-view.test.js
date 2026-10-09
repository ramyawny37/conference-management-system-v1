'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');
const script=fs.readFileSync('script.js','utf8');
const start=script.indexOf('function getStartupConferenceViewModel(){');
const end=script.indexOf('\nfunction showStartupConferenceList(){',start);
assert.ok(start>=0&&end>start,'canonical startup conference list function must exist');
const functionSource=script.slice(start,end);
test('startup renders canonical discovery rows directly and opens by canonical id',()=>{
  const sandbox={appData:{conferences:[]},window:{StartupConferenceDiscovery:{getRecords:()=>[{id:'cloud-1',name:'بابا',status:'active'}]}},structuredClone:value=>JSON.parse(JSON.stringify(value))};
  vm.runInNewContext(functionSource+'\nthis.getList=getStartupConferenceViewModel;',sandbox);
  const rows=sandbox.getList();
  assert.equal(rows.length,1);
  assert.equal(rows[0].name,'بابا');
  assert.equal(rows[0].__startupDiscoveredRemoteId,'cloud-1');
});

test('local-only startup open cannot bypass canonical discovery authorization',()=>{
  const begin=script.indexOf('function openConferenceFromStartup(id){');
  const end=script.indexOf('\nvar conferenceBrandingDraft=',begin);
  assert.ok(begin>=0&&end>begin);
  const source=script.slice(begin,end);
  let localActivations=0,toast='';
  const sandbox={window:{ConferenceLinkStore:{get:()=>null}},showToast:value=>{toast=value;},setCurrentConferenceById:()=>{localActivations++;return true;}};
  vm.runInNewContext(source+'\nthis.openLocal=openConferenceFromStartup;',sandbox);
  assert.equal(sandbox.openLocal('local-only'),false);
  assert.equal(localActivations,0);
  assert.match(toast,/السحابية/);
});
