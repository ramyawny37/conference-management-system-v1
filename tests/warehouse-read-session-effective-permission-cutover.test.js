const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const assert=require('node:assert/strict');

const migration=fs.readFileSync(path.join(__dirname,'..','supabase','migrations','20261110150000_warehouse_read_session_effective_permission_cutover.sql'),'utf8');

test('warehouse read session uses only canonical effective permission authority',()=>{
  assert.match(migration,/create or replace function warehouse_private\.require_read_session\(p_device_id uuid\)/i);
  assert.match(migration,/public\.require_effective_module_permission\([\s\S]*p_device_id,[\s\S]*'warehouse',[\s\S]*'warehouse\.module\.access',[\s\S]*null,[\s\S]*null/i);
  assert.doesNotMatch(migration,/context\s*:=\s*public\.require_module_permission\(/i);
});
