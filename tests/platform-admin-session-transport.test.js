'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');

const user=fs.readFileSync('js/sync/user-management-read-service.js','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');

assert.match(user,/PlatformDeviceSession/);
assert.match(user,/invokeModuleProtected\('platform'/);
assert.doesNotMatch(user,/\.rpc\s*\(/);
assert.doesNotMatch(user,/p_actor_device_id\s*:/);
assert.doesNotMatch(user,/p_actor_user_id\s*:/);
for(const operation of ['get_user_management_actor_capabilities','search_user_management_users','get_user_management_overview','get_user_management_devices','get_user_management_account'])assert.match(user,new RegExp(operation));
assert.doesNotMatch(user,/organization/i);
assert.doesNotMatch(edge,/device_guarded_list_my_organizations|get_organization_management_overview|manage_organization/);
for(const stage of ['origin_validation','authentication','request_validation','session_validation','operation_dispatch'])assert.match(edge,new RegExp("['\"]"+stage+"['\"]"));
assert.match(edge,/const diagnostic=\{module:requestedModule\|\|null,operation:requestedOperation\|\|null,stage,sqlstate,applicationCode,requestId,timestamp:new Date\(\)\.toISOString\(\)\};/);
assert.match(edge,/console\.error\(JSON\.stringify\(\{\.\.\.diagnostic,code:safe\.code,status:safe\.status\}\)\);/);
assert.match(edge,/return json\(safe\.status,\{ok:false,error:\{code:safe\.code\},diagnostic\}\);/);
assert.doesNotMatch(edge,/error:\{[^}]*message:/);
console.log('Platform administration session transport contracts: passed');
