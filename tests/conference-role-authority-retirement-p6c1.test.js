'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const exists = (p) => fs.existsSync(path.join(root, p));

const contract = read('js/sync/conference-permission-contract.js');
const resolver = read('js/sync/conference-permission-resolver.js');
const activation = read('js/sync/conference-activation-authorization.js');
const conferenceEdge = read('supabase/functions/conference-device-operation/index.ts');
const platformEdge = read('supabase/functions/platform-device-operation/index.ts');
const retirement = read('supabase/migrations/20261009120000_retire_conference_role_membership_authority.sql');
const locks = read('supabase/migrations/20261009121000_cut_conference_locks_to_canonical_permissions.sql');
const membershipPlane = read('supabase/migrations/20261009122000_retire_conference_membership_plane.sql');

assert.match(contract, /roles:Object\.freeze\(\[\]\)/);
assert.match(contract, /roleBundles:Object\.freeze\(\{\}\)/);
assert.match(contract, /hasSectionPermission:deny/);
assert.match(contract, /hasConferencePermission:deny/);
assert.match(resolver, /status:'retired'/);
assert.match(resolver, /can:function\(\)\{return false;\}/);
assert.match(resolver, /canConference:function\(\)\{return false;\}/);
assert.match(resolver, /ConferencePermissionShadowGate=function\(\)\{return true;\}/);
assert.doesNotMatch(activation, /owner|manager|viewer|conference_members/i);
assert.match(activation, /canonical_access_granted/);

[
  'js/sync/conference-membership-attempt-store.js',
  'js/sync/conference-members-service.js',
  'js/sync/conference-members-ui.js'
].forEach((file) => assert.equal(exists(file), false, `retired runtime still exists: ${file}`));

[
  'device_guarded_get_my_conference_access',
  'device_guarded_get_my_conference_membership',
  'device_guarded_list_conference_members',
  'device_guarded_lookup_conference_user_by_email',
  'device_guarded_manage_conference_member',
  'device_guarded_add_conference_manager',
  'device_guarded_remove_conference_manager'
].forEach((operation) => {
  assert.ok(!conferenceEdge.includes(`'${operation}'`), `conference edge still exposes ${operation}`);
  assert.ok(!platformEdge.includes(`'${operation}'`), `platform edge still exposes ${operation}`);
});

[
  'get_my_conference_access',
  'get_my_conference_membership',
  'list_conference_members',
  'lookup_conference_user_by_email',
  'manage_conference_member',
  'add_conference_manager',
  'remove_conference_manager'
].forEach((routine) => assert.ok(retirement.includes(routine), `retirement migration missing ${routine}`));
assert.match(retirement, /drop table if exists public\.conference_membership_operations/i);

assert.match(locks, /require_effective_module_permission/);
assert.match(locks, /conference\.accommodation\.manage/);
assert.match(locks, /conference\.sync\.write/);
assert.match(locks, /get_conference_section_lock/);
assert.match(locks, /CONFERENCE_LOCK_ROLE_AUTHORITY_REMAINS/);
assert.doesNotMatch(locks, /conference membership required/i);

assert.match(membershipPlane, /drop table if exists public\.conference_members/i);
assert.match(membershipPlane, /is_conference_member/);
assert.match(membershipPlane, /has_conference_role/);
assert.match(membershipPlane, /CONFERENCE_MEMBERSHIP_CONSUMER_REMAINS/);
assert.doesNotMatch(membershipPlane, /cascade/i);

console.log('P6C1 conference role authority retirement contract: passed');
