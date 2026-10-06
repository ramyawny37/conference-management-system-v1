'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync(
  'supabase/migrations/20261010120000_retire_legacy_conference_core_mutation_overloads.sql',
  'utf8'
);
const contract=fs.readFileSync(
  'js/supabase/platform-device-operation-contract.js','utf8'
);
const router=fs.readFileSync(
  'supabase/migrations/20261009123000_final_canonical_conference_creation_reconciliation.sql',
  'utf8'
);

test('legacy Conference core mutation overload is explicitly retired',()=>{
  assert.match(
    migration,
    /drop function if exists public\.mutate_conference_core\(\s*uuid,uuid,bigint,text,date,date,text\s*\)/
  );
  assert.match(
    migration,
    /count\(\*\)[\s\S]*proname='mutate_conference_core'[\s\S]*<>1/
  );
});

test('final Conference core mutation remains private and uniquely canonical',()=>{
  const signature='public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text)';
  assert.ok(contract.includes(signature));
  assert.match(
    migration,
    /CANONICAL_CONFERENCE_CORE_MUTATION_DIRECT_EXECUTE_REMAINS/
  );
  assert.match(
    router,
    /p_operation='mutate_conference_core'[\s\S]*public\.mutate_conference_core\(\s*p_actor_device_id,\(p_args->>'p_operation_id'\)::uuid/
  );
  assert.doesNotMatch(
    router,
    /public\.mutate_conference_core\(\s*p_actor_device_id,\(p_args->>'p_conference_id'\)::uuid/
  );
});
