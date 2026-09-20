'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const vm=require('node:vm');

const root=path.resolve(__dirname,'..');
const uiSource=fs.readFileSync(path.join(root,'js/sync/device-authorization-administration-ui.js'),'utf8');
const serviceSource=fs.readFileSync(path.join(root,'js/supabase/device-authorization-administration-service.js'),'utf8');

function deferred(){let resolve;const promise=new Promise(done=>{resolve=done;});return {promise,resolve};}
function harness(){
  const element={style:{},innerHTML:''};
  const approvals=[];
  let devices=[
    {targetUserId:'11111111-1111-4111-8111-111111111111',deviceId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',displayName:'A'},
    {targetUserId:'22222222-2222-4222-8222-222222222222',deviceId:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',displayName:'B'}
  ];
  const service={
    listPlatformPendingDevices:()=>Promise.resolve({ok:true,status:'listed',data:{devices}}),
    approveSystemOwnerPendingDevice:input=>{const pending=deferred();approvals.push({input,pending});return pending.promise;}
  };
  const sandbox={window:null,Promise,Object,Array,String,JSON,console,document:{getElementById:()=>element},DeviceAuthorizationAdministrationService:service};
  sandbox.window=sandbox;
  vm.runInNewContext(uiSource,sandbox);
  return {api:sandbox.DeviceAuthorizationAdministrationUI,element,approvals,setDevices:value=>{devices=value;}};
}

test('Platform pending approval has one canonical System Owner UI owner',()=>{
  assert.ok(uiSource.includes("actPlatformPending(\\''+escapeHtml(request.targetUserId)"));
  assert.match(uiSource,/approveSystemOwnerPendingDevice\(\{targetUserId:targetUserId,deviceId:deviceId\}\)/);
  assert.doesNotMatch(uiSource+serviceSource,/approvePlatformPendingDevice/);
  assert.doesNotMatch(uiSource+serviceSource,/\.rpc\('approve_pending_device_authorization'/);
  assert.equal((uiSource.match(/function actPlatformPending\(/g)||[]).length,1);
});

test('successful Platform approval refreshes while failure and overlap preserve pending state',async()=>{
  const h=harness();
  await h.api.refreshPlatformPendingRequests();
  assert.match(h.element.innerHTML,/aaaaaaaa/);
  assert.match(h.element.innerHTML,/bbbbbbbb/);

  const first=h.api.actPlatformPending('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  const second=h.api.actPlatformPending('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  assert.equal(JSON.stringify(h.approvals.map(item=>item.input)),JSON.stringify([
    {targetUserId:'11111111-1111-4111-8111-111111111111',deviceId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
    {targetUserId:'22222222-2222-4222-8222-222222222222',deviceId:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'}
  ]));

  h.approvals[1].pending.resolve({ok:false,status:'unknown',error:{code:'AMBIGUOUS_RESULT'}});
  await second;
  assert.match(h.element.innerHTML,/bbbbbbbb/);
  assert.match(h.element.innerHTML,/result is unknown/);

  h.approvals[0].pending.resolve({ok:true,status:'applied'});
  await first;
  assert.match(h.element.innerHTML,/bbbbbbbb/);
  assert.match(h.element.innerHTML,/result is unknown/);

  h.setDevices([]);
  const third=h.api.actPlatformPending('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  h.approvals[2].pending.resolve({ok:true,status:'applied'});
  await third;
  assert.doesNotMatch(h.element.innerHTML,/bbbbbbbb/);
  assert.match(h.element.innerHTML,/Platform device approved/);
});
