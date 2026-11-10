'use strict';

const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const PROJECT_REF = 'mpezfbvcdfxpgflehuot';
const DEVELOPMENT_REF = 'gppwltrifgfxrkzvvxoe';
const API_URL = 'https://' + PROJECT_REF + '.supabase.co';
const EXPECTED_EMAIL = 'ramyawny37@gmail.com';

function fail(message) { throw new Error(message); }
function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) fail(name + ' is required');
  return value;
}
function sqlLiteral(value) { return "'" + String(value).replace(/'/g, "''") + "'"; }
function psql(databaseUrl, sql) {
  const result = spawnSync('psql', [databaseUrl, '-X', '-v', 'ON_ERROR_STOP=1', '-Atq'], {
    input: sql, encoding: 'utf8',
    env: { ...process.env, PGOPTIONS: '-c statement_timeout=15000 -c lock_timeout=5000' }
  });
  if (result.error) fail('Unable to execute psql: ' + result.error.message);
  if (result.status !== 0) fail('Production recovery database preflight failed');
  return String(result.stdout || '').trim();
}
async function api(path, key, options = {}) {
  const response = await fetch(API_URL + path, {
    ...options,
    headers: {
      apikey: key, Authorization: 'Bearer ' + key,
      'Content-Type': 'application/json', ...(options.headers || {})
    }
  });
  const raw = await response.text();
  let body = null;
  try { body = raw ? JSON.parse(raw) : null; } catch (_) {}
  if (!response.ok) fail('Production recovery API failed: HTTP ' + response.status + ' ' + JSON.stringify(body || { error: 'redacted response' }));
  return body;
}
async function main() {
  if (process.argv.length !== 2) fail('Command-line arguments are forbidden');
  if (process.env.PRODUCTION_ZERO_DEVICE_RECOVERY_ENABLED !== 'true') {
    fail('PRODUCTION_ZERO_DEVICE_RECOVERY_ENABLED must equal true');
  }
  const databaseUrl = required('PRODUCTION_DATABASE_URL');
  const key = required('PRODUCTION_SERVICE_ROLE_KEY');
  if (!databaseUrl.includes(PROJECT_REF) || databaseUrl.includes(DEVELOPMENT_REF)) fail('Production database identity check failed');
  if (!/^eyJ|^sb_secret_/.test(key)) fail('Production service-role key format is not recognized');

  const sql = [
    "with target as (",
    " select u.id user_id,a.id authorization_id,a.device_id,b.id binding_id",
    " from auth.users u",
    " join platform.profiles p on p.user_id=u.id and p.account_status='approved'",
    " join platform.user_roles ur on ur.user_id=u.id and ur.revoked_at is null",
    " join platform.roles r on r.id=ur.role_id and r.domain='platform' and r.code='platform_owner'",
    " join platform.user_device_authorizations a on a.user_id=u.id and a.status='pending'",
    " join platform.devices d on d.id=a.device_id and d.lifecycle_status='active'",
    " join platform.device_key_bindings b on b.user_id=u.id and b.device_id=a.device_id and b.device_authorization_id=a.id and b.lifecycle_status='active'",
    " where lower(u.email)=lower(" + sqlLiteral(EXPECTED_EMAIL) + ") and u.email_confirmed_at is not null and u.deleted_at is null",
    " and not exists (select 1 from platform.user_device_authorizations aa join platform.devices dd on dd.id=aa.device_id where aa.user_id=u.id and aa.status='approved' and dd.lifecycle_status='active')",
    "), counts as (select count(*) n from target)",
    "select case when counts.n=1 then concat_ws('|',target.user_id,target.device_id,target.authorization_id,target.binding_id) else '' end",
    "from counts left join target on counts.n=1;"
  ].join("\n");
  const target = psql(databaseUrl, sql);
  const parts = target.split('|');
  if (parts.length !== 4 || parts.some(x => !/^[0-9a-f-]{36}$/i.test(x))) fail('Production zero-device recovery preflight did not resolve exactly one canonical target');
  const [userId, deviceId, authorizationId, bindingId] = parts;

  const result = await api('/rest/v1/rpc/recover_zero_approved_owner_device', key, {
    method: 'POST',
    headers: { 'Content-Profile': 'platform', 'Accept-Profile': 'platform' },
    body: JSON.stringify({
      p_target_user_id: userId,
      p_target_device_id: deviceId,
      p_target_authorization_id: authorizationId,
      p_target_binding_id: bindingId,
      p_operation_id: crypto.randomUUID(),
      p_reason: 'Initial Production platform owner has zero approved devices after canonical first-system bootstrap'
    })
  });
  if (!result || result.authorizationStatus !== 'approved' || result.userId !== userId || result.deviceId !== deviceId) {
    fail('Canonical Production recovery did not return the exact approved target');
  }
  process.stdout.write('PRODUCTION FIRST DEVICE RECOVERY: PASS\n');
}
main().catch(error => {
  const safe = String(error && error.message || error)
    .replace(/postgres(?:ql)?:\/\/[^\s]+/gi, '[REDACTED_DATABASE_URL]')
    .replace(/eyJ[A-Za-z0-9._-]+/g, '[REDACTED_KEY]')
    .replace(/sb_secret_[A-Za-z0-9_-]+/g, '[REDACTED_KEY]');
  process.stderr.write(safe + '\n');
  process.exitCode = 1;
});
