'use strict';

const crypto = require('node:crypto');

const PROJECT_REF = 'mpezfbvcdfxpgflehuot';
const API_URL = 'https://' + PROJECT_REF + '.supabase.co';
const EXPECTED_EMAIL = 'ramyawny37@gmail.com';

function fail(message) { throw new Error(message); }
function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) fail(name + ' is required');
  return value;
}
async function api(path, key, options = {}) {
  const response = await fetch(API_URL + path, {
    ...options,
    headers: {
      apikey: key,
      Authorization: 'Bearer ' + key,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const text = await response.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch (_) {}
  if (!response.ok) fail('Production recovery API failed: HTTP ' + response.status + ' ' + JSON.stringify(body || { error: 'redacted response' }));
  return body;
}
async function main() {
  if (process.argv.length !== 2) fail('Command-line arguments are forbidden');
  if (process.env.PRODUCTION_ZERO_DEVICE_RECOVERY_ENABLED !== 'true') {
    fail('PRODUCTION_ZERO_DEVICE_RECOVERY_ENABLED must equal true');
  }
  const key = required('PRODUCTION_SERVICE_ROLE_KEY');
  if (!/^eyJ|^sb_secret_/.test(key)) fail('Production service-role key format is not recognized');

  const ownerRows = await api(
    '/rest/v1/rpc/get_production_zero_device_recovery_target',
    key,
    { method: 'POST', body: JSON.stringify({ p_expected_email: EXPECTED_EMAIL }) }
  ).catch(() => null);

  // The canonical recovery RPC remains the only writer. Target discovery is performed
  // through read-only REST queries when no dedicated helper RPC is installed.
  const users = await api('/auth/v1/admin/users?per_page=1000', key);
  const matches = (users.users || []).filter(u => String(u.email || '').toLowerCase() === EXPECTED_EMAIL);
  if (matches.length !== 1 || !matches[0].email_confirmed_at || matches[0].deleted_at) {
    fail('Expected exactly one confirmed, non-deleted Production owner auth user');
  }
  const userId = matches[0].id;

  const auths = await api('/rest/v1/user_device_authorizations?select=id,device_id,status&user_id=eq.' + encodeURIComponent(userId), key, {
    headers: { 'Accept-Profile': 'platform' }
  });
  const approved = auths.filter(x => x.status === 'approved');
  const pending = auths.filter(x => x.status === 'pending');
  if (approved.length !== 0 || pending.length !== 1) fail('Production zero-device recovery invariant failed');

  const authorization = pending[0];
  const devices = await api('/rest/v1/devices?select=id,lifecycle_status&id=eq.' + authorization.device_id, key, {
    headers: { 'Accept-Profile': 'platform' }
  });
  if (devices.length !== 1 || devices[0].lifecycle_status !== 'active') fail('Target Production device is not uniquely active');

  const bindings = await api('/rest/v1/device_key_bindings?select=id,lifecycle_status,device_authorization_id&user_id=eq.' + encodeURIComponent(userId) + '&device_id=eq.' + authorization.device_id, key, {
    headers: { 'Accept-Profile': 'platform' }
  });
  const activeBindings = bindings.filter(x => x.lifecycle_status === 'active' && x.device_authorization_id === authorization.id);
  if (activeBindings.length !== 1) fail('Target Production device binding is not uniquely active');

  const operationId = crypto.randomUUID();
  const result = await api('/rest/v1/rpc/recover_zero_approved_owner_device', key, {
    method: 'POST',
    headers: { 'Content-Profile': 'platform', 'Accept-Profile': 'platform' },
    body: JSON.stringify({
      p_target_user_id: userId,
      p_target_device_id: authorization.device_id,
      p_target_authorization_id: authorization.id,
      p_target_binding_id: activeBindings[0].id,
      p_operation_id: operationId,
      p_reason: 'Initial Production platform owner has zero approved devices after canonical first-system bootstrap'
    })
  });

  if (!result || result.authorizationStatus !== 'approved') fail('Canonical Production recovery did not return approved status');
  process.stdout.write('PRODUCTION FIRST DEVICE RECOVERY: PASS\n');
}
main().catch(error => {
  const safe = String(error && error.message || error).replace(/eyJ[A-Za-z0-9._-]+/g, '[REDACTED_KEY]').replace(/sb_secret_[A-Za-z0-9_-]+/g, '[REDACTED_KEY]');
  process.stderr.write(safe + '\n');
  process.exitCode = 1;
});
