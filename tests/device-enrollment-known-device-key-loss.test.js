'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const enrollment=fs.readFileSync('js/supabase/device-enrollment.js','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-enrollment/index.ts','utf8');

test('known device without its bound private key fails closed before fresh enrollment',()=>{
  assert.match(enrollment,/getCurrent\(\{authenticatedUserId:auth\.userId\}\)/);
  assert.match(enrollment,/invoke\(\{action:'device-status',deviceId:identity\.id\}\)/);
  assert.match(enrollment,/if\(status&&status\.known\)throw \{code:'BOUND_PRIVATE_KEY_REQUIRED'/);
  const guard=enrollment.indexOf("if(status&&status.known)throw {code:'BOUND_PRIVATE_KEY_REQUIRED'");
  const fresh=enrollment.indexOf('return adoptProvedLegacy().then(function(adopted){return adopted||enroll(auth);});',guard);
  assert.ok(guard>=0&&fresh>guard,'known-device guard must run before fresh enrollment');
});

test('device-status lookup is authenticated and scoped to the current user and device',()=>{
  assert.match(edge,/if\(action==='device-status'\)/);
  assert.match(edge,/\.eq\('user_id',userResult\.data\.user\.id\)\.eq\('device_id',deviceId\)/);
  assert.match(edge,/data:\{known:!!row,status:row\?String\(row\.status\|\|'missing'\):'missing'/);
});

test('native enrollment remains the only path for an unknown device',()=>{
  assert.equal((edge.match(/action!=='enroll'/g)||[]).length,1);
  assert.equal((edge.match(/enroll_new_device_key/g)||[]).length,1);
  assert.doesNotMatch(enrollment,/binding_recovery|ownership_handoff|lost_private_key/);
});
