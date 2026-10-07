'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const vm=require('node:vm');

const migration=fs.readFileSync('supabase/migrations/20261010202600_system_access_device_authority_cutover.sql','utf8');
const serviceSource=fs.readFileSync('js/supabase/first-system-bootstrap-service.js','utf8');

test('first bootstrap creates Platform account and owner authority only',()=>{
  assert.match(migration,/insert into platform\.profiles/i);
  assert.match(migration,/insert into platform\.user_roles/i);
  assert.match(migration,/r?ole_id[\s\S]*platform_owner/i);
  assert.match(migration,/BOOTSTRAP_CREDENTIAL_INVALID/i);
  assert.doesNotMatch(migration,/insert into public\.organizations/i);
  assert.doesNotMatch(migration,/insert into public\.system_user_(?:access|roles)/i);
  assert.doesNotMatch(migration,/insert into public\.(?:devices|user_device_authorizations)/i);
});

test('browser bootstrap service uses RPC only and carries no Organization input',async()=>{
  assert.doesNotMatch(serviceSource,/organizationName|organizationDescription|p_organization/i);
  assert.doesNotMatch(serviceSource,/\.from\s*\(|\.insert\s*\(|\.update\s*\(|\.delete\s*\(/);
  const calls=[];
  const identity='33333333-3333-4333-8333-333333333333';
  const sandbox={window:{
    SupabaseClientLayer:{getClient:()=>({rpc:(name,args)=>{calls.push({name,args});return Promise.resolve({data:{status:name.includes('status')?'setup_required':'completed'},error:null});}})},
    SupabaseDeviceIdentity:{getOrCreate:()=>({id:identity,deviceName:'Fresh',platform:'Browser'})},
    crypto:{randomUUID:()=> '44444444-4444-4444-8444-444444444444'}
  },Promise};
  vm.runInNewContext(serviceSource,sandbox);
  assert.equal((await sandbox.window.FirstSystemBootstrapService.getStatus()).status,'setup_required');
  assert.equal((await sandbox.window.FirstSystemBootstrapService.complete({setupToken:'not-logged'})).status,'completed');
  assert.equal(calls[1].args.p_device_id,identity);
  assert.equal(Object.keys(calls[1].args).some(key=>key.includes('organization')),false);
});
