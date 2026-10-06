'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),test=require('node:test');
const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261010189000_platform_module_entry_permissions.sql'),'utf8');
test('all live modules have explicit canonical entry and management permissions',()=>{
 for(const module of ['conference','warehouse','reservations']){
  assert.match(sql,new RegExp(module+'\\.module\\.access'));
  assert.match(sql,new RegExp(module+'\\.module\\.manage'));
 }
});
test('module entry permissions are module scoped only',()=>{assert.doesNotMatch(sql,/resource','/);assert.match(sql,/'module',null/);});
