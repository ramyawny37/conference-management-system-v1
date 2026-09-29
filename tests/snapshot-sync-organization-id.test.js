'use strict';

var assert=require('assert');
var fs=require('fs');
var path=require('path');
var vm=require('vm');
var source=fs.readFileSync(path.join(__dirname,'../js/supabase/canonical-conference-discovery.js'),'utf8');
var calls={writes:0,rpc:0,operation:''};
var rows=[
  {role:'owner',conference:{id:'11111111-1111-4111-8111-111111111111',name:'نفس الاسم',owner_id:'22222222-2222-4222-8222-222222222222',organization_id:'33333333-3333-4333-8333-333333333333',created_at:'a',updated_at:'b',deleted_at:null}},
  {role:'manager',conference:{id:'44444444-4444-4444-8444-444444444444',name:'نفس الاسم',owner_id:'22222222-2222-4222-8222-222222222222',organization_id:null,created_at:'c',updated_at:'d',deleted_at:null}}
];
var sandbox={window:null,Promise:Promise,JSON:JSON,Object:Object,String:String,Array:Array,Date:Date,structuredClone:function(v){return JSON.parse(JSON.stringify(v));},SupabaseAuth:{getSession:function(){return {user:{id:'55555555-5555-4555-8555-555555555555'}};}},SupabaseClientLayer:{getClient:function(){return {};}},PlatformDeviceSession:{invokeModuleProtected:function(module,operation){assert.strictEqual(module,'conference');calls.operation=operation;return Promise.resolve({conferences:rows.map(function(row){return {conferenceId:row.conference.id,name:row.conference.name,organizationId:row.conference.organization_id,status:'active',revision:1,createdAt:row.conference.created_at,updatedAt:row.conference.updated_at};})});}}};
sandbox.window=sandbox;
vm.runInNewContext(source,sandbox,{filename:'snapshot-sync.js'});
(async function(){
  var result=await sandbox.CanonicalConferenceDiscovery.listAccessibleConferences();
  assert.strictEqual(result.ok,true);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(result.data.conferences)),[
    {id:rows[0].conference.id,organizationId:rows[0].conference.organization_id,name:'نفس الاسم',startDate:null,endDate:null,status:'active',completedAt:null,revision:1,createdAt:'a',updatedAt:'b',capabilities:{edit:false,sync:false,transportManage:false}},
    {id:rows[1].conference.id,organizationId:null,name:'نفس الاسم',startDate:null,endDate:null,status:'active',completedAt:null,revision:1,createdAt:'c',updatedAt:'d',capabilities:{edit:false,sync:false,transportManage:false}}
  ]);
  assert.strictEqual(calls.operation,'list_accessible_conferences');
  assert.strictEqual(calls.writes,0);
  assert.strictEqual(calls.rpc,0);
  ['js/sync/sync-settings-ui.js','js/sync/member-runtime-diagnostics.js','js/sync/debug-binding-report-ui.js'].forEach(function(file){assert.strictEqual(fs.readFileSync(path.join(__dirname,'..',file),'utf8').includes('organizationId'),false,file+' must not expose organizationId');});
  console.log('snapshot sync organization id tests: passed');
})().catch(function(error){console.error(error);process.exitCode=1;});
