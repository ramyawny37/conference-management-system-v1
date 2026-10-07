'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const authority=fs.readFileSync('supabase/migrations/20261010202000_platform_account_authority_cutover.sql','utf8');
const retirement=fs.readFileSync('supabase/migrations/20261010202600_system_access_device_authority_cutover.sql','utf8');

test('Platform roles are the sole owner and admin authority',()=>{
  assert.match(authority,/from platform\.user_roles/i);
  assert.match(authority,/join platform\.roles/i);
  assert.match(authority,/r\.code='platform_owner'/i);
  assert.match(authority,/r\.code in \('platform_owner','platform_admin'\)/i);
  assert.doesNotMatch(authority,/from public\.system_user_roles/i);
});

test('Platform profiles are the sole account approval authority',()=>{
  assert.match(authority,/from platform\.profiles/i);
  assert.match(authority,/p\.account_status='approved'/i);
  assert.doesNotMatch(authority,/system_user_access/i);
});

test('legacy System Access authority and compatibility projection are retired',()=>{
  assert.match(retirement,/drop table public\.system_user_access/i);
  assert.match(retirement,/drop table public\.system_user_roles/i);
  assert.match(retirement,/drop function if exists platform_private\.reconcile_system_user_access_profile/i);
  assert.match(retirement,/drop function if exists platform_private\.reconcile_system_owner_platform_owner/i);
  assert.doesNotMatch(retirement,/insert into public\.system_user_(?:access|roles)/i);
});

test('legacy Public device authority is retired rather than mirrored',()=>{
  assert.match(retirement,/drop table public\.user_device_authorizations/i);
  assert.match(retirement,/drop table public\.devices/i);
  assert.match(retirement,/drop table if exists public\.device_authorization_operations/i);
  assert.doesNotMatch(retirement,/insert into public\.(?:devices|user_device_authorizations)/i);
});
