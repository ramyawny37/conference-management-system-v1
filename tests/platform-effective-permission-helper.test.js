const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261010200000_platform_effective_permission_helper.sql'),'utf8');

test('platform effective permission uses canonical Platform authority only',()=>{
  assert.match(sql,/platform_private\.is_canonical_platform_owner\(p_user_id\)/);
  assert.match(sql,/from platform\.permission_grants grant_row/i);
  assert.match(sql,/join platform\.permissions permission/i);
  assert.match(sql,/grant_row\.scope_type='platform'/);
  assert.match(sql,/permission\.domain='platform'/);
  assert.match(sql,/permission\.code=p_permission_code/);
  assert.doesNotMatch(sql,/system_user_access/i);
  assert.doesNotMatch(sql,/system_user_roles/i);
  assert.doesNotMatch(sql,/organization_members/i);
  assert.doesNotMatch(sql,/platform\.user_roles/i);
});

test('platform effective permission is platform-scoped and active-only',()=>{
  assert.match(sql,/p_permission_code like 'platform\.%'/);
  assert.match(sql,/profile\.account_status='approved'/);
  assert.match(sql,/grant_row\.revoked_at is null/);
  assert.match(sql,/grant_row\.resource_type is null/);
  assert.match(sql,/grant_row\.resource_id is null/);
});
