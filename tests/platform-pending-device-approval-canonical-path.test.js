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

function lifecycleHarness(){
  const element={style:{},innerHTML:''};
  const approvals=[];
  const overlap={targetUserId:'11111111-1111-4111-8111-111111111111',deviceId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'};
  const memberOnly={targetUserId:'33333333-3333-4333-8333-333333333333',deviceId:'cccccccc-cccc-4ccc-8ccc-cccccccccccc'};
  const members=[
    {userId:overlap.targetUserId,displayName:'Platform Member'},
    {userId:memberOnly.targetUserId,displayName:'Member Only'}
  ];
  const platformResult=()=>({ok:true,status:'listed',data:{devices:[{...overlap,displayName:'Platform Owner',deviceName:'Platform iPhone',platform:'iOS',requestedAt:'2026-09-19T10:00:00Z'}]}});
  const memberResult=targetUserId=>({ok:true,data:{devices:[{deviceId:targetUserId===overlap.targetUserId?overlap.deviceId:memberOnly.deviceId,deviceName:targetUserId===overlap.targetUserId?'Member iPhone':'Member Android',platform:targetUserId===overlap.targetUserId?'iOS':'Android',authorizationStatus:'pending',requestedAt:'2026-09-19T10:00:00Z'}]}});
  let platformList=()=>Promise.resolve(platformResult()),memberList=targetUserId=>Promise.resolve(memberResult(targetUserId));
  const service={
    listPlatformPendingDevices:()=>platformList(),
    listMemberDevices:({targetUserId})=>memberList(targetUserId),
    approveSystemOwnerPendingDevice:input=>{approvals.push(input);return Promise.resolve({ok:false,status:'unknown',error:{code:'AMBIGUOUS_RESULT'}});}
  };
  const sandbox={window:null,Promise,Object,Array,String,JSON,console,document:{getElementById:()=>element},SupabaseAuth:{initialize:()=>Promise.resolve(),getSession:()=>({user:{id:'actor'}})},SupabaseClientLayer:{getClient:()=>null},OrganizationAdministrationService:{listMyOrganizations:()=>Promise.resolve({ok:true,data:{organizations:[{organizationId:'organization',displayName:'Conference Org'}]}}),getCurrentAccess:()=>Promise.resolve({ok:true,data:{role:'organization_owner'}}),listMembers:()=>Promise.resolve({ok:true,data:{members}})},UserManagementReadService:{listUsers:()=>Promise.resolve({ok:true,data:{users:members.map(member=>({userId:member.userId,email:member.userId+'@example.com'}))}})},DeviceAuthorizationAdministrationService:service};
  sandbox.window=sandbox;
  const context=vm.createContext(sandbox);
  vm.runInContext(uiSource,context);
  return {api:sandbox.DeviceAuthorizationAdministrationUI,element,approvals,context,overlap,memberOnly,platformResult,memberResult,setPlatformList:value=>{platformList=value;},setMemberList:value=>{memberList=value;}};
}

test('Platform pending approval has one canonical System Owner UI owner',()=>{
  assert.ok(uiSource.includes("actPlatformPending(\\''+escapeHtml(request.targetUserId)"));
  assert.match(uiSource,/approveSystemOwnerPendingDevice\(\{targetUserId:targetUserId,deviceId:deviceId\}\)/);
  assert.doesNotMatch(uiSource+serviceSource,/approvePlatformPendingDevice/);
  assert.doesNotMatch(uiSource+serviceSource,/\.rpc\('approve_pending_device_authorization'/);
  assert.equal((uiSource.match(/function actPlatformPending\(/g)||[]).length,1);
});

test('initialize and member refresh preserve one rendered Platform-owned pending action',async()=>{
  const h=lifecycleHarness();
  await h.api.initialize();
  let cards=h.element.innerHTML.match(/<article[\s\S]*?<\/article>/g)||[];
  assert.equal(cards.length,2);
  const platformCard=cards.find(card=>card.includes('aaaaaaaa'));
  const memberCard=cards.find(card=>card.includes('cccccccc'));
  assert.ok(platformCard);
  assert.match(platformCard,/Conference Org/);
  assert.match(platformCard,/DeviceAuthorizationAdministrationUI\.actPlatformPending/);
  assert.doesNotMatch(platformCard,/openPendingInUserManagement/);
  assert.ok(memberCard);
  assert.match(memberCard,/openPendingInUserManagement/);
  assert.doesNotMatch(memberCard,/actPlatformPending/);

  const handler=platformCard.match(/onclick="([^"]*actPlatformPending[^"]*)"/)[1];
  await vm.runInContext(handler,h.context);
  assert.equal(JSON.stringify(h.approvals),JSON.stringify([h.overlap]));

  await h.api.refreshPendingRequests();
  cards=h.element.innerHTML.match(/<article[\s\S]*?<\/article>/g)||[];
  assert.equal(cards.filter(card=>card.includes('aaaaaaaa')).length,1);
  assert.match(cards.find(card=>card.includes('aaaaaaaa')),/actPlatformPending/);
  assert.equal((uiSource.match(/\.rpc\('approve_pending_device_authorization'/g)||[]).length,0);
});

test('asynchronous Platform and member refresh order cannot downgrade Platform ownership',async()=>{
  const h=lifecycleHarness();
  await h.api.initialize();
  async function runOrder(platformFirst){
    const platformGate=deferred(),memberGate=deferred();
    h.setPlatformList(()=>platformGate.promise);
    h.setMemberList(targetUserId=>memberGate.promise.then(()=>h.memberResult(targetUserId)));
    const platformRefresh=h.api.refreshPlatformPendingRequests();
    const memberRefresh=h.api.refreshPendingRequests();
    if(platformFirst){
      platformGate.resolve(h.platformResult());
      await platformRefresh;
      memberGate.resolve();
      await memberRefresh;
    }else{
      memberGate.resolve();
      await memberRefresh;
      platformGate.resolve(h.platformResult());
      await platformRefresh;
    }
    const cards=h.element.innerHTML.match(/<article[\s\S]*?<\/article>/g)||[];
    assert.equal(cards.filter(card=>card.includes('aaaaaaaa')).length,1);
    assert.match(cards.find(card=>card.includes('aaaaaaaa')),/actPlatformPending/);
  }
  await runOrder(true);
  await runOrder(false);
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
