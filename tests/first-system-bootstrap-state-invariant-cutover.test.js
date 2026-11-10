const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const assert=require('node:assert/strict');

const migration=fs.readFileSync(path.join(__dirname,'..','supabase','migrations','20261110161000_first_system_bootstrap_state_invariant_cutover.sql'),'utf8');

test('first-system bootstrap persists singleton state for P-256 follow-up lifecycle',()=>{
  assert.match(migration,/insert into public\.system_bootstrap_state\(singleton_id\)[\s\S]*on conflict\(singleton_id\) do nothing/i);
  assert.match(migration,/select \* into strict state_row[\s\S]*for update/i);
  assert.match(migration,/device_id=null/i);
  assert.match(migration,/if not found then raise exception 'BOOTSTRAP_STATE_WRITE_FAILED'/i);
  assert.match(migration,/completed_at is not null[\s\S]*completed_by is not null[\s\S]*operation_id is not null[\s\S]*intent_hash is not null[\s\S]*stored_result is not null/i);
  assert.doesNotMatch(migration,/completed_at is not null[\s\S]{0,160}device_id is not null/i);
});
