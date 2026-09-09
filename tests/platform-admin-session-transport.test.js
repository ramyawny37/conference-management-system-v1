'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');

const services={
  user:fs.readFileSync('js/sync/user-management-read-service.js','utf8'),
  organization:fs.readFileSync('js/supabase/organization-management-service.js','utf8'),
  membership:fs.readFileSync('js/supabase/organization-administration-service.js','utf8'),
  account:fs.readFileSync('js/supabase/account-administration-service.js','utf8')
};
const combined=Object.values(services).join('\n');

for(const [name,source] of Object.entries(services)){
  assert.match(source,/PlatformDeviceSession/);
  assert.match(source,/invokeProtected/);
  assert.doesNotMatch(source,/\.rpc\s*\(/,name+' must not directly invoke a privileged RPC');
  assert.doesNotMatch(source,/p_actor_device_id\s*:/,name+' must not supply actor device identity');
  assert.doesNotMatch(source,/p_device_id\s*:/,name+' must not supply device/override device identity');
  assert.doesNotMatch(source,/p_actor_user_id\s*:/,name+' must not supply actor user identity');
}

for(const operation of [
  'get_user_management_actor_capabilities','search_user_management_users',
  'get_user_management_overview','get_user_management_devices','get_user_management_account',
  'get_organization_management_overview','manage_organization',
  'device_guarded_list_my_organizations','device_guarded_get_my_organization_access',
  'device_guarded_list_organization_members','device_guarded_lookup_organization_candidate_by_email',
  'device_guarded_get_organization_membership_operation','device_guarded_add_organization_member',
  'device_guarded_remove_organization_member','device_guarded_change_organization_role',
  'device_guarded_manage_system_user'
])assert.match(combined,new RegExp(operation));

console.log('Platform administration session transport contracts: passed');
