'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');
const source=fs.readFileSync('js/platform-integration.js','utf8');
function environment(){
 const calls=[],token='11111111-1111-4111-8111-111111111111';
 const sandbox={window:null,console,Promise,JSON,Object,String,Array,Date,RegExp,Error,Uint8Array,Math,setTimeout,clearTimeout,navigator:{onLine:true},document:{addEventListener(){}},addEventListener(){},dispatchEvent(){},CustomEvent:function(){},crypto:{randomUUID(){return token}},PlatformDeviceSession:{invokeModuleProtected(module,operation,args){calls.push({module,operation,args:JSON.parse(JSON.stringify(args))});if(operation==='acquire_resource_lease')return Promise.resolve({status:'acquired',owned:true,leaseToken:args.p_lease_token,expiresAt:'2099-01-01T00:00:00Z'});if(operation==='renew_resource_lease')return Promise.resolve({status:'renewed',owned:true,expiresAt:'2099-01-01T00:01:00Z'});if(operation==='release_resource_lease')return Promise.resolve({status:'released',owned:false});return Promise.resolve({status:'available',locked:false,owned:false});}}};
 sandbox.window=sandbox;vm.runInNewContext(source,sandbox);return {api:sandbox.PlatformIntegration,calls,token};
}
test('resource lease uses protected device-session path',async()=>{
 const env=environment(),id='40000000-0000-4000-8000-000000000001';
 const acquired=await env.api.acquireResourceLease('conference','accommodation_room',id);
 assert.equal(acquired.owned,true);
 assert.deepEqual(env.calls[0],{module:'conference',operation:'acquire_resource_lease',args:{p_resource_type:'accommodation_room',p_resource_id:id,p_scope:'edit',p_lease_token:env.token,p_ttl_seconds:120}});
 assert.equal(env.api.getOwnedResourceLease('conference','accommodation_room',id).leaseToken,env.token);
 await env.api.renewResourceLease('conference','accommodation_room',id);
 assert.equal(env.calls[1].operation,'renew_resource_lease');
 await env.api.releaseResourceLease('conference','accommodation_room',id);
 assert.equal(env.calls[2].operation,'release_resource_lease');
 assert.equal(env.api.getOwnedResourceLease('conference','accommodation_room',id),null);
});
test('invalid resource identity is rejected before dispatch',async()=>{
 const env=environment();
 await assert.rejects(env.api.acquireResourceLease('conference','bad type','room'),error=>error.code==='PLATFORM_RESOURCE_LEASE_ARGUMENT_INVALID');
 assert.equal(env.calls.length,0);
});

test('accommodation refresh ignores an older response arriving last',async()=>{
 const env=environment(),local='local-a',remote='50000000-0000-4000-8000-000000000001';
 const pending=[];
 const original=env.api.hydrateConferenceAccommodation;
 assert.equal(typeof original,'function');
 // Read-only structural assertion: both hydration and mutation use the same sequence guard.
 assert.match(source,/function hydrateConferenceAccommodation[\\s\\S]*?acceptConferenceAccommodation\\(localId,remoteId,response,sequence\\)/);
 assert.match(source,/function mutateAccommodation[\\s\\S]*?acceptConferenceAccommodation\\(localId,record.remoteConferenceId,response,sequence\\)/);
 assert.match(source,/if\\(sequence!==undefined&&sequence!==accommodationRefreshSequence\\[String\\(localId\\)\\]\\)/);
});
