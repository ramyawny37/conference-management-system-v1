'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');

const root=path.join(__dirname,'..');
const runtime=fs.readFileSync(path.join(root,'supabase/migrations/20261010201000_reservations_organization_free_scope_runtime.sql'),'utf8');
const schema=fs.readFileSync(path.join(root,'supabase/migrations/20261010201100_conference_reservations_organization_schema_retirement.sql'),'utf8');
const contract=fs.readFileSync(path.join(root,'js/supabase/platform-device-operation-contract.js'),'utf8');

test('runtime cutover precedes the destructive schema cutover',()=>{
  assert.match(runtime,/create or replace function reservations_private\.read_scoped/);
  assert.match(runtime,/create or replace function reservations_private\.mutate_scoped/);
  assert.doesNotMatch(runtime,/organization_id|organizationId|organization_members|p_organization_id/i);
  assert.match(schema,/alter table public\.conferences[\s\S]*drop column if exists organization_id/);
  assert.match(schema,/alter table reservations\.events drop column if exists organization_id/);
});

test('Conference creation, reads and dispatcher expose no Organization contract',()=>{
  assert.match(runtime,/function public\.create_canonical_conference\(\s*p_actor_device_id uuid,\s*p_operation_id uuid,\s*p_requested_conference_id uuid,\s*p_name text/);
  assert.match(runtime,/require_effective_module_permission\([\s\S]*'conference','conference\.lifecycle\.create',null,null/);
  assert.match(runtime,/function public\.get_conference_core/);
  assert.match(runtime,/function public\.list_accessible_conferences/);
  assert.match(contract,/public\.create_canonical_conference\(uuid,uuid,uuid,text,date,date\)/);
  assert.doesNotMatch(contract,/p_organization_id|organizationId|organization_id/);
});

test('Reservations authority and partition invariants survive de-tenancy',()=>{
  assert.match(runtime,/public\.require_current_approved_device/);
  assert.match(runtime,/require_effective_module_permission/);
  assert.match(runtime,/scope_type='conference'[\s\S]*scope_partition_id=v_conference_id/);
  assert.match(runtime,/scope_type='standalone'[\s\S]*extensions\.gen_random_uuid\(\)/);
  assert.match(runtime,/on conflict\(scope_partition_id,booking_year\)/);
  assert.match(runtime,/new\.scope_partition_id=new\.conference_id/);
  assert.match(runtime,/old_scope_partition_id,new_scope_partition_id,event_id,conference_id,operation_id,linked_by/);
});

test('browser-supplied authority keys are absent from the canonical contracts',()=>{
  const router=runtime.match(/create or replace function platform_private\.route_canonical_conference_operation[\s\S]*?end \$\$;/i)?.[0]||'';
  assert.match(router,/require_exact_jsonb_keys/);
  assert.doesNotMatch(router,/organization|p_actor_user_id'|p_actor_device_id'/i);
  const reservationsRead=runtime.match(/create or replace function reservations\.read[\s\S]*?end \$\$;/i)?.[0]||'';
  assert.match(reservationsRead,/list_accessible_conferences/);
  assert.doesNotMatch(reservationsRead,/conference_members|organization_members/i);
});
