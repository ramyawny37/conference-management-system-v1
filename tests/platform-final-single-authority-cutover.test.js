'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const finalCutover=fs.readFileSync('supabase/migrations/20261010202600_system_access_device_authority_cutover.sql','utf8');
const organizationApiRetirement=fs.readFileSync('supabase/migrations/20261010201500_organization_api_root_retirement.sql','utf8');
const organizationStorageRetirement=fs.readFileSync('supabase/migrations/20261010201400_organization_subsystem_storage_retirement.sql','utf8');
const indexedDb=fs.readFileSync('js/storage/indexeddb.js','utf8');

test('final authority cutover drops every legacy Public account and device authority table',()=>{
  for(const table of ['system_user_access','system_user_roles','user_device_authorizations','devices']){
    assert.match(finalCutover,new RegExp('drop table public\\.'+table+';','i'),table);
  }
  assert.match(finalCutover,/insert into platform\.profiles/i);
  assert.match(finalCutover,/insert into platform\.user_roles/i);
});

test('Organization authority and member-device API roots are retired rather than bridged',()=>{
  for(const contract of [
    'drop table if exists public.organization_members',
    'drop table if exists public.organizations',
    'drop function if exists public.list_member_device_authorizations',
    'drop function if exists public.approve_member_device',
    'drop function if exists public.reject_member_pending_device',
    'drop function if exists public.revoke_member_device',
    'drop function if exists public.replace_member_active_device',
    'drop function if exists public.require_device_authorization_manager',
    'drop function if exists platform_private.apply_member_device_authorization'
  ]) assert.ok((organizationStorageRetirement+'\n'+organizationApiRetirement).includes(contract),contract);
});

test('browser runtime retains Organization IndexedDB names only as one-time deletion targets',()=>{
  for(const store of [
    'organization_membership_pending_operations',
    'organization_template_operations',
    'organization_template_access_operations'
  ]) assert.equal((indexedDb.match(new RegExp(store,'g'))||[]).length,1,store);
  assert.match(indexedDb,/var DATABASE_VERSION = 8;/);
  assert.match(indexedDb,/db\.deleteObjectStore\(name\)/);
});
