'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261010160000_platform_module_transport_cutover.sql'),'utf8');
test('database accepts explicit platform module during transport cutover',()=>{
 assert.match(sql,/if p_module=''platform'' then/);
 assert.match(sql,/PLATFORM_MODULE_CUTOVER_PREDECESSOR_MISMATCH/);
});
test('bridge is visibly transitional and does not alter conference canonical route',()=>{
 assert.match(sql,/if p_module=''conference'' then/);
 assert.match(sql,/execute_conference_device_operation_phase1c_core/);
});
