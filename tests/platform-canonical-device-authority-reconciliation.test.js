'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync(
  'supabase/migrations/20260920221928_canonical_platform_device_authority_reconciliation.sql',
  'utf8'
);

test('canonical actor authorization requires approved Platform state and exact active binding',()=>{
  const helper=migration.match(/create or replace function platform_private\.require_canonical_device_authorization[\s\S]*?end; \$\$;/i)?.[0]||'';
  for(const contract of [
    "device_authorization.status='approved'",
    'device_authorization.revoked_at is null',
    "device.lifecycle_status='active'",
    'device.retired_at is null',
    'device.compromised_at is null',
    "profile.account_status='approved'",
    'binding.user_id=device_authorization.user_id',
    'binding.device_id=device_authorization.device_id',
    'binding.device_authorization_id=device_authorization.id',
    "binding.lifecycle_status='active'",
    'binding.revoked_at is null',
    'binding.retired_at is null'
  ]) assert.ok(helper.includes(contract),contract);
  assert.doesNotMatch(helper,/public\.(?:user_device_authorizations|devices)/i);
});

test('legacy-only authorization cannot satisfy canonical privileged administration',()=>{
  assert.doesNotMatch(migration,/public\.user_device_authorizations/i);
  assert.doesNotMatch(migration,/insert\s+into\s+public\.(?:user_device_authorizations|devices)/i);
  assert.doesNotMatch(migration,/update\s+public\.(?:user_device_authorizations|devices)/i);
  assert.match(migration,/require_system_owner_webauthn_actor[\s\S]*?require_canonical_device_authorization/i);
  assert.match(migration,/require_current_approved_device[\s\S]*?validated_phase1c_device_authorization[\s\S]*?require_canonical_device_authorization/i);
});

test('pending list and mutation have one canonical Platform owner',()=>{
  const listing=migration.match(/create or replace function public\.list_system_owner_pending_device_authorizations[\s\S]*?end; \$\$;/i)?.[0]||'';
  const completion=migration.match(/create or replace function public\.complete_system_owner_pending_device_operation[\s\S]*?end; \$\$;/i)?.[0]||'';
  assert.match(listing,/from platform\.user_device_authorizations device_authorization/i);
  assert.match(listing,/device_authorization\.status='pending'/i);
  assert.match(completion,/from platform\.user_device_authorizations device_authorization/i);
  assert.match(completion,/update platform\.user_device_authorizations set/i);
  assert.match(completion,/insert into public\.system_owner_device_authorization_operations/i);
  assert.match(completion,/insert into public\.privileged_device_authorization_audit_log/i);
  assert.match(completion,/platform_private\.write_audit_event/i);
  assert.doesNotMatch(completion,/public\.user_device_authorizations/i);
});

test('member administration uses Platform devices without dual-write',()=>{
  const member=migration.match(/create or replace function platform_private\.apply_member_device_authorization[\s\S]*?end; \$\$;/i)?.[0]||'';
  const listing=migration.match(/create or replace function public\.list_member_device_authorizations[\s\S]*?end; \$\$;/i)?.[0]||'';
  assert.match(member,/platform\.user_device_authorizations/i);
  assert.match(member,/platform\.device_key_bindings/i);
  assert.match(member,/DEVICE_REVOCATION_REPLACEMENT_REQUIRED/i);
  assert.match(member,/is_canonical_platform_owner/i);
  assert.doesNotMatch(member,/public\.user_device_authorizations/i);
  assert.match(listing,/from platform\.user_device_authorizations device_authorization/i);
  assert.doesNotMatch(listing,/public\.user_device_authorizations/i);
});

test('WebAuthn remains additional confirmation and credential lifecycle stays fail closed',()=>{
  for(const contract of [
    "userVerified')::boolean,false)<>true",
    "backupEligible')::boolean,true)<>false",
    "backupState')::boolean,true)<>false",
    'p_new_sign_count<credential.sign_count',
    'DEVICE_SECURITY_CREDENTIAL_DELETE_FORBIDDEN',
    'LIVE_SECURITY_CREDENTIAL_REVOCATION_REQUIRED',
    "'confirmation','webauthn'"
  ]) assert.ok(migration.includes(contract),contract);
});

test('new devices remain pending and zero-owner recovery is not broadened',()=>{
  assert.doesNotMatch(migration,/insert\s+into\s+platform\.user_device_authorizations/i);
  assert.doesNotMatch(migration,/create or replace function [^(]*(?:zero[_ -]?approved|credential_recovery)/i);
  assert.match(migration,/system_owner_credential_recovery_authorizations[\s\S]*?recovery_platform_device_fk/i);
});

test('obsolete legacy mutators are retired and active provenance accepts Platform devices',()=>{
  assert.match(migration,/revoke execute on function public\.register_or_refresh_current_device[\s\S]*?authenticated,service_role/i);
  assert.match(migration,/revoke execute on function public\.request_current_device_authorization[\s\S]*?authenticated,service_role/i);
  for(const constraint of [
    'conference_locks_platform_device_fkey',
    'conference_snapshots_platform_device_fkey',
    'sync_operations_platform_device_fkey',
    'module_grant_operations_actor_platform_device_fkey',
    'module_permission_grants_grantor_platform_device_fkey',
    'module_permission_grants_revoker_platform_device_fkey'
  ]) assert.ok(migration.includes(constraint),constraint);
  assert.match(migration,/historical legacy provenance is preserved without being reclassified/i);
});

test('historical privileged provenance is prospectively enforced without validation or backfill',()=>{
  const prospective=[
    'device_security_credentials_platform_authorization_fk',
    'device_possession_challenges_actor_platform_authorization_fk',
    'device_possession_challenges_target_platform_authorization_fk',
    'system_owner_device_operations_actor_platform_authorization_fk',
    'system_owner_device_operations_target_platform_authorization_fk',
    'privileged_device_audit_actor_platform_authorization_fk',
    'privileged_device_audit_target_platform_authorization_fk',
    'system_owner_credential_bootstrap_platform_device_fk',
    'device_authorization_admin_actor_platform_device_fk',
    'device_authorization_admin_target_platform_device_fk',
    'device_authorization_audit_platform_device_owner_fk'
  ];
  for(const name of prospective){
    const declaration=migration.match(new RegExp(`add constraint ${name}[\\s\\S]*?(?=,\\n\\s*(?:--|add constraint)|;)`,'i'))?.[0]||'';
    assert.match(declaration,/references platform\.user_device_authorizations\(user_id,device_id\)/i,name);
    assert.match(declaration,/on delete restrict not valid/i,name);
  }
  for(const name of [
    'device_possession_challenges_replaced_platform_authorization_fk',
    'device_possession_challenges_replacement_platform_authorization_fk',
    'system_owner_device_operations_replaced_platform_authorization_fk',
    'system_owner_device_operations_replacement_platform_authorization_fk',
    'privileged_device_audit_replaced_platform_authorization_fk',
    'privileged_device_audit_replacement_platform_authorization_fk',
    'system_owner_credential_recovery_platform_device_fk',
    'device_authorization_admin_replacement_platform_device_fk'
  ]){
    const declaration=migration.match(new RegExp(`add constraint ${name}[\\s\\S]*?(?=,\\n\\s*(?:--|add constraint)|;)`,'i'))?.[0]||'';
    assert.doesNotMatch(declaration,/not valid/i,name);
  }
  assert.doesNotMatch(migration,/validate\s+constraint\s+(?:device_security_credentials_platform_authorization_fk|device_possession_challenges_(?:actor|target)_platform_authorization_fk|system_owner_device_operations_(?:actor|target)_platform_authorization_fk|privileged_device_audit_(?:actor|target)_platform_authorization_fk|system_owner_credential_bootstrap_platform_device_fk|device_authorization_admin_(?:actor|target)_platform_device_fk|device_authorization_audit_platform_device_owner_fk)/i);
  assert.doesNotMatch(migration,/insert\s+into\s+platform\.user_device_authorizations/i);
});

test('historical provenance never substitutes for current canonical authorization',()=>{
  const actor=migration.match(/create or replace function public\.require_system_owner_webauthn_actor[\s\S]*?end; \$\$;/i)?.[0]||'';
  assert.match(actor,/require_canonical_device_authorization/i);
  assert.ok(
    actor.indexOf('require_canonical_device_authorization')<actor.indexOf('from public.device_security_credentials'),
    'current canonical authorization must be established before historical credential lookup'
  );
  assert.doesNotMatch(actor,/device_authorization_(?:admin_operations|audit_log)/i);
  assert.doesNotMatch(actor,/privileged_device_authorization_audit_log/i);
});
