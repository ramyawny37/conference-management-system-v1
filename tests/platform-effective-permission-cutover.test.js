'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),test=require('node:test');
const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261010181000_cut_effective_module_permission_to_platform.sql'),'utf8');
test('effective module permission reads canonical platform catalog and grants',()=>{
 assert.match(sql,/platform\.permissions/); assert.match(sql,/platform\.permission_grants/);
 assert.doesNotMatch(sql,/public\.module_permission_grants/); assert.doesNotMatch(sql,/public\.is_system_owner/);
});
test('platform owner is the only owner bypass',()=>{assert.match(sql,/platform_private\.is_canonical_platform_owner/);assert.match(sql,/'authoritySource','platform_owner'/);});
test('resource requests may fall back only to a module grant when catalog allows both',()=>{
 assert.match(sql,/allowed_scope_mode in \('module','both'\)/);
 assert.match(sql,/scope_type='resource'/); assert.match(sql,/scope_type='module'/);
});
