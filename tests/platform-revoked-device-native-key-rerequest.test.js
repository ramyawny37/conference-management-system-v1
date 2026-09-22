'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const migration=fs.readFileSync('supabase/migrations/20260921172640_revoked_device_native_key_rerequest.sql','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-enrollment/index.ts','utf8');
const client=fs.readFileSync('js/supabase/device-enrollment.js','utf8');
const gate=fs.readFileSync('js/sync/startup-access-gate.js','utf8');
const rerequestEdge=edge.slice(edge.indexOf("if(action==='rerequest')"),edge.indexOf("if(action!=='enroll')"));

test('backend mutates the same revoked authorization to pending without inserting authority rows',()=>{
  assert.match(migration,/where device_authorization\.user_id=p_user_id and device_authorization\.device_id=p_device_id[\s\S]*for update/);
  assert.match(migration,/v_authorization\.status<>'revoked'/);
  assert.match(migration,/update platform\.user_device_authorizations set[\s\S]*status='pending',requested_at=statement_timestamp\(\)/);
  assert.doesNotMatch(migration,/insert into platform\.(?:devices|user_device_authorizations|device_key_bindings)/);
  for(const field of ['approved_by=null','approved_at=null','blocked_by=null','blocked_at=null','revoked_by=null','revoked_at=null','status_reason=null'])assert.ok(migration.includes(field),field);
});

test('backend locks and validates exact active binding and device ownership',()=>{
  assert.match(migration,/binding\.id=p_binding_id for update/);
  assert.match(migration,/v_binding\.user_id<>p_user_id[\s\S]*v_binding\.device_id<>p_device_id[\s\S]*v_binding\.device_authorization_id<>v_authorization\.id/);
  assert.match(migration,/v_binding\.lifecycle_status<>'active'/);
  assert.match(migration,/v_device\.lifecycle_status<>'active'[\s\S]*v_device\.retired_at is not null[\s\S]*v_device\.compromised_at is not null/);
});

test('backend replay protection, audit, result, and privileges are narrow',()=>{
  assert.match(migration,/device_authorization_rerequest_nonces where nonce=p_nonce/);
  assert.match(migration,/DEVICE_REREQUEST_REPLAY_DENIED/);
  assert.match(migration,/'transition','revoked_to_pending'[\s\S]*'proof','native_key_possession'/);
  for(const value of ["'deviceId',p_device_id","'authorizationId',v_authorization.id","'bindingId',p_binding_id","'publicKeyThumbprint',v_binding.public_key_thumbprint","'status','pending'"])assert.ok(migration.includes(value),value);
  assert.match(migration,/revoke all on function platform\.rerequest_revoked_device_key\(uuid,uuid,uuid,text\)[\s\S]*from public,anon,authenticated,service_role/);
  assert.match(migration,/grant execute on function platform\.rerequest_revoked_device_key\(uuid,uuid,uuid,text\) to service_role/);
});

test('Edge rerequest authenticates exact stored binding, authorization, and device',()=>{
  assert.match(rerequestEdge,/rpc\('get_device_key_rerequest_verification_context',\{p_user_id:userResult\.data\.user\.id,p_device_id:deviceId,p_binding_id:bindingId\}\)/);
  assert.match(rerequestEdge,/context\.bindingId!==bindingId[\s\S]*context\.deviceId!==deviceId[\s\S]*context\.bindingLifecycle!=='active'[\s\S]*context\.bindingRevoked[\s\S]*context\.bindingRetired/);
  assert.match(rerequestEdge,/context\.authorizationStatus!=='revoked'/);
  assert.match(rerequestEdge,/context\.deviceLifecycle!=='active'[\s\S]*context\.deviceRetired[\s\S]*context\.deviceCompromised/);
  assert.match(rerequestEdge,/rerequest_revoked_device_key/);
});

test('Edge verifies freshness, canonical domain-separated payload, and signature',()=>{
  assert.match(rerequestEdge,/Math\.abs\(Date\.now\(\)-issued\)>120000/);
  assert.match(rerequestEdge,/PLATFORM_NATIVE_DEVICE_REREQUEST','v1'/);
  assert.match(rerequestEdge,/DEVICE_REREQUEST_PAYLOAD_INVALID/);
  assert.match(rerequestEdge,/crypto\.subtle\.verify/);
  assert.match(rerequestEdge,/DEVICE_REREQUEST_SIGNATURE_INVALID/);
});

test('browser cannot substitute an alternate public key for the stored binding key',()=>{
  assert.match(rerequestEdge,/importKey\('jwk',context\.publicKeyJwk/);
  assert.doesNotMatch(rerequestEdge,/body\.publicKeyJwk|body\.public_key_jwk/);
});

test('client signs only with the existing active record and preserves identity',()=>{
  assert.match(client,/function rerequest\(record,auth\)[\s\S]*record\.privateKey/);
  assert.match(client,/record\.deviceId!==identity\.id/);
  assert.match(client,/verifyNonExportable\(record\.privateKey\)[\s\S]*action:'status'/);
  assert.match(client,/action:'rerequest',bindingId:record\.bindingId,deviceId:record\.deviceId/);
  assert.doesNotMatch(client,/resetCurrent|deleteDatabase/);
});

test('rerequest remains explicit and never runs from ensure',()=>{
  const ensureBody=client.slice(client.indexOf('function ensure()'),client.indexOf('global.PlatformDeviceEnrollment'));
  assert.doesNotMatch(ensureBody,/rerequest\(|action:'rerequest'/);
  assert.match(gate,/deviceReEnrollmentAvailable=!!\(enrollment&&enrollment\.status==='revoked'/);
  assert.match(gate,/function reEnrollCurrentDevice\(\)[\s\S]*enrollment\.rerequestRevoked\(\)/);
});

test('obsolete reset-and-new-device revoked recovery is absent',()=>{
  assert.doesNotMatch(client,/reEnrollRevoked|resetCurrent/);
  assert.doesNotMatch(gate,/enrollment\.reEnrollRevoked/);
  assert.equal((client.match(/generateKey\(/g)||[]).length,1);
  assert.equal((edge.match(/p_device_id:crypto\.randomUUID\(\)/g)||[]).length,1);
});
