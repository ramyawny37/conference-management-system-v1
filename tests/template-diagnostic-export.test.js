'use strict';
const assert=require('assert');
const fs=require('fs');
const vm=require('vm');

const source=fs.readFileSync('js/sync/template-diagnostic-export.js','utf8');
const sandbox={window:null,Promise,JSON,Object,Array,String,Number,Date,Error};
sandbox.window=sandbox;
vm.runInNewContext(source,sandbox,{filename:'template-diagnostic-export.js'});

(async function(){
  const bundle=await sandbox.TemplateDiagnosticExport.createBundle({
    appData:{
      conferences:[{id:'private'}],peopleDb:{people:['private']},
      houseTemplates:[{
        id:'house-1',name:'Smoke House',revision:4,
        createdAt:'2026-08-01T00:00:00.000Z',
        updatedAt:'2026-08-10T00:00:00.000Z',
        floors:[{rooms:[{guests:['private-person']}]}],secret:'hidden'
      }]
    },
    auth:{getState(){return {user:{id:'user-1',email:'private@example.com'}};}},
    deviceIdentity:{getCurrent(){return {id:'device-1',secret:'device-secret'};}}
  });

  assert.strictEqual(bundle.context.currentUserId,'user-1');
  assert.strictEqual(bundle.context.currentDeviceId,'device-1');
  assert.ok(bundle.context.timestamp);
  assert.deepStrictEqual(Object.keys(bundle.houseTemplates[0]),[
    'id','name','revision','createdAt','updatedAt'
  ]);
  assert.deepStrictEqual(Object.keys(bundle),['context','houseTemplates']);
  const serialized=JSON.stringify(bundle);
  ['private@example.com','private-person','device-secret','peopleDb','conferences','floors','secret'].forEach(function(value){
    assert.strictEqual(serialized.includes(value),false,'leaked '+value);
  });
  assert.doesNotMatch(source,/OrganizationTemplateSync|organizationMemberships|organizationId|accessibleOrganizationIds|cloudSyncStatus|cloudRevision|cloudUpdatedAt|operationStores/);
  assert.doesNotMatch(source,/saveAppData|setItem|putRecord|deleteRecord|\.rpc\s*\(|retry|repair/i);
  console.log('local House Template diagnostic export tests: passed');
})().catch(function(error){console.error(error);process.exitCode=1;});
