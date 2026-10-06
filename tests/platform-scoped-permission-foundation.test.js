'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),test=require('node:test');
const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261010180000_platform_scoped_permission_foundation.sql'),'utf8');
test('canonical permission catalog covers all live modules',()=>{
 for(const domain of ['platform','conference','warehouse','reservations']) assert.match(sql,new RegExp(domain));
 assert.match(sql,/allowed_scope_mode/); assert.match(sql,/allowed_resource_type/);
});
test('canonical direct grants support module and resource scope without roles-per-resource',()=>{
 assert.match(sql,/create table platform\.permission_grants/);
 assert.match(sql,/scope_type text not null check \(scope_type in \('module','resource'\)\)/);
 assert.match(sql,/resource_type text null/); assert.match(sql,/resource_id text null/);
});
test('foundation imports catalog semantics only, not disposable user grants',()=>{
 assert.match(sql,/from public\.module_permission_catalog catalog/);
 assert.doesNotMatch(sql,/from public\.module_permission_grants/);
});
