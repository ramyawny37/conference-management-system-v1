const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync(
  'supabase/migrations/20260925143000_reservations_effective_capability_dispatch_reconciliation.sql','utf8'
);
const contract=fs.readFileSync(
  'supabase/migrations/20260922113000_reservations_effective_capability_contract.sql','utf8'
);
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');

test('Edge and canonical Platform dispatcher admit the capability projection',()=>{
  assert.match(edge,/reservations\.add\('get_effective_capabilities'\)/);
  assert.match(migration,/p_operation in \('get_effective_capabilities','update_participant_booking'\)/);
  assert.match(migration,/return reservations\.read\(session\.device_id,p_operation,p_args\)/);
});

test('canonical dispatcher preserves session validation and existing operations',()=>{
  assert.match(migration,/profile\.account_status='approved'/);
  assert.match(migration,/return reservations_private\.mutate_scoped\(session\.device_id,p_operation,p_args\)/);
  assert.match(migration,/execute_device_operation_pre_generic_permission_resource_administration/);
  assert.match(migration,/list_module_permission_resources_for_administration/);
});

test('Reservations retains business capability ownership and exact scope validation',()=>{
  assert.match(contract,/function reservations_private\.effective_capabilities/);
  assert.match(contract,/public\.require_current_approved_device\(p_device_id\)/);
  assert.match(contract,/public\.is_system_owner\(v_actor\)/);
  assert.match(contract,/public\.module_permission_grants/);
  assert.match(contract,/g\.resource_type='event'/);
  assert.match(contract,/RESERVATIONS_CONFERENCE_ACCESS_REQUIRED/);
});

test('migration creates no feature-specific delegation layer and preserves privileges',()=>{
  assert.doesNotMatch(migration,/rename to|pg_get_functiondef|pre_effective_capability_dispatch/);
  assert.match(migration,/security definer[\s\S]*set search_path='pg_catalog','public','platform','platform_private'/);
  assert.match(migration,/revoke all on function platform\.execute_device_operation\(uuid,uuid,bytea,text,text,jsonb\)[\s\S]*from public,anon,authenticated,service_role/);
  assert.match(migration,/grant execute on function platform\.execute_device_operation\(uuid,uuid,bytea,text,text,jsonb\)[\s\S]*to service_role/);
});
