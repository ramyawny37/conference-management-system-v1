'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const test=require('node:test');

const root=path.join(__dirname,'..');

function loadContract(){
  const window={};
  vm.runInNewContext(fs.readFileSync(path.join(root,'js/supabase/conference-device-operation-contract.js'),'utf8'),{window,Set,Object});
  return window.ConferenceDeviceOperationContract;
}

test('shared protected operations are owned by platform, not conference',()=>{
  const contract=loadContract();
  for(const operation of [
    'get_user_management_overview',
    'list_module_permission_grants',
    'manage_catalog_module_grant'
  ]){
    assert.equal(contract.isProtectedOperation(operation),true);
    assert.equal(contract.moduleFor(operation),'platform');
  }
  for(const retired of ['device_guarded_list_my_organizations','list_member_device_authorizations','list_organization_templates']) {
    assert.equal(contract.isProtectedOperation(retired),false);
    assert.equal(contract.moduleFor(retired),null);
  }
});

test('conference locks remain conference-owned',()=>{
  const contract=loadContract();
  for(const operation of ['acquire_conference_lock','get_conference_lock','acquire_conference_section_lock','get_conference_section_lock']){
    assert.equal(contract.moduleFor(operation),'conference');
  }
});

test('client interceptor dispatches protected RPCs through explicit module transport',()=>{
  const source=fs.readFileSync(path.join(root,'js/supabase/client.js'),'utf8');
  assert.match(source,/invokeModuleProtected\(protectedOperation\.module,protectedOperation\.operation,protectedArgs\)/);
  assert.doesNotMatch(source,/PlatformDeviceSession\.invokeProtected\(String\(name/);
});

test('unified Edge accepts platform and keeps shared administration out of conference',()=>{
  const source=fs.readFileSync(path.join(root,'supabase/functions/platform-device-operation/index.ts'),'utf8');
  assert.match(source,/const platform=new Set\(/);
  assert.match(source,/module!==['"]platform['"]/);
  assert.match(source,/module===['"]platform['"]\?platform/);
  const platformBlock=source.slice(source.indexOf('const platform=new Set('),source.indexOf('const conference=new Set('));
  const conferenceBlock=source.slice(source.indexOf('const conference=new Set('),source.indexOf('const warehouse='));
  assert.match(platformBlock,/get_user_management_overview/);
  assert.match(platformBlock,/list_module_permission_grants/);
  assert.doesNotMatch(conferenceBlock,/get_user_management_overview/);
  assert.doesNotMatch(conferenceBlock,/list_module_permission_grants/);
});
