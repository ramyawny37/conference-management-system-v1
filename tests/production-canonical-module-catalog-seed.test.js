'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const seed=fs.readFileSync(path.join(root,'tools/production-release/canonical-system-catalog-seed.sql'),'utf8');
const gate=fs.readFileSync(path.join(root,'js/platform-integration.js'),'utf8');
test('production system seed includes all canonical modules and fails closed on missing or inactive rows',()=>{
 for(const module of ['conference','warehouse','reservations','custody']) assert.match(seed,new RegExp("\\('"+module+"','"));
 assert.match(seed,/INSERT INTO public\.platform_modules\s*\(module_key,display_name,status\)/);
 assert.match(seed,/ON CONFLICT \(module_key\) DO NOTHING/);
 assert.match(seed,/Canonical module catalog incomplete or inactive/);
 assert.match(seed,/m\.status <> 'active'/);
});
test('warehouse entry uses the same protected module gate as conference and reservations',()=>{
 assert.match(gate,/session\.invokeModuleProtected\(id,'check_module_access',\{\}\)/);
 assert.match(gate,/warehouse:'ليس لديك صلاحية للدخول إلى موديول المخازن'/);
});
