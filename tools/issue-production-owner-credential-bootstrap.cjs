'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');

const PROJECT_REF = 'mpezfbvcdfxpgflehuot';
const PROJECT_URL = `https://${PROJECT_REF}.supabase.co`;
const ENVIRONMENT = 'production';
const EXPECTED_ORIGIN = 'https://ramyawny37.github.io';
const RP_ID = 'ramyawny37.github.io';
const INTENDED_USER_ID = requiredEnvironment('OWNER_USER_ID');
const INTENDED_DEVICE_ID = requiredEnvironment('APPROVED_OWNER_DEVICE_ID');

function fail(message) {
  throw new Error(message);
}

function requiredEnvironment(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) fail(`${name} is required`);
  return value;
}

function assertExecutionGate() {
  if (process.argv.length !== 2) fail('Command-line arguments are forbidden');
  if (process.env.PRODUCTION_CREDENTIAL_BOOTSTRAP_ENABLED !== 'true') {
    fail('PRODUCTION_CREDENTIAL_BOOTSTRAP_ENABLED must equal true');
  }
  const serviceRoleKey = requiredEnvironment('SUPABASE_SERVICE_ROLE_KEY');
  return { serviceRoleKey };
}

function openSecureTerminal() {
  let descriptor;
  try {
    descriptor = fs.openSync('/dev/tty', 'w');
  } catch (_) {
    fail('A controlling secure terminal is required before issuance');
  }
  if (!fs.fstatSync(descriptor).isCharacterDevice()) {
    fs.closeSync(descriptor);
    fail('Token destination is not a terminal character device');
  }
  return descriptor;
}

async function request(serviceRoleKey, pathname, options = {}) {
  const response = await fetch(`${PROJECT_URL}${pathname}`, {
    method: options.method || 'GET',
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) fail(`${options.label || 'Production request'} failed with HTTP ${response.status}`);
  return payload;
}

function expectSingle(rows, label) {
  if (!Array.isArray(rows) || rows.length !== 1) fail(`${label} verification failed`);
  return rows[0];
}

async function verifyTarget(serviceRoleKey) {
  if (!/^[0-9a-f-]{36}$/i.test(INTENDED_USER_ID) || !/^[0-9a-f-]{36}$/i.test(INTENDED_DEVICE_ID)) fail('Invalid owner/device UUID');
  // The issuance RPC enforces canonical owner role and approved device authorization.
  const encodedUser = encodeURIComponent(INTENDED_USER_ID);
  const encodedDevice = encodeURIComponent(INTENDED_DEVICE_ID);
  const now = encodeURIComponent(new Date().toISOString());
  const [credentialRows, bootstrapRows] = await Promise.all([
    request(serviceRoleKey, `/rest/v1/device_security_credentials?select=id&user_id=eq.${encodedUser}&device_id=eq.${encodedDevice}&credential_kind=eq.platform_primary&lifecycle_status=eq.active&revoked_at=is.null`, { label: 'Active credential' }),
    request(serviceRoleKey, `/rest/v1/system_owner_credential_bootstrap_authorizations?select=id&intended_user_id=eq.${encodedUser}&intended_device_id=eq.${encodedDevice}&environment=eq.${ENVIRONMENT}&consumed_at=is.null&expires_at=gt.${now}`, { label: 'Live bootstrap authorization' }),
  ]);

  if (!Array.isArray(credentialRows) || credentialRows.length !== 0) fail('Active platform credential already exists');
  if (!Array.isArray(bootstrapRows) || bootstrapRows.length !== 0) fail('Live bootstrap authorization already exists');
}

async function issue(serviceRoleKey, state) {
  const tokenBytes = crypto.randomBytes(32);
  const plaintextToken = tokenBytes.toString('base64url');
  const authorizationHash = crypto.createHash('sha256').update(plaintextToken, 'utf8').digest('hex');
  tokenBytes.fill(0);
  const reason = 'Production owner credential enrollment; explicitly approved secure terminal execution';

  state.issuanceAttempted = true;
  const result = await request(serviceRoleKey, '/rest/v1/rpc/issue_system_owner_credential_bootstrap_authorization', {
    method: 'POST',
    label: 'Bootstrap issuance RPC',
    body: {
      p_operator_user_id: INTENDED_USER_ID,
      p_operator_device_id: INTENDED_DEVICE_ID,
      p_intended_user_id: INTENDED_USER_ID,
      p_intended_device_id: INTENDED_DEVICE_ID,
      p_environment: ENVIRONMENT,
      p_authorization_hash: `\\x${authorizationHash}`,
      p_origin: EXPECTED_ORIGIN,
      p_rp_id: RP_ID,
      p_reason: reason,
    },
  });
  if (!result || result.status !== 'issued' || !result.authorizationId || !result.auditId || result.expiresInSeconds !== 600) {
    fail('Bootstrap issuance RPC returned an unexpected result; do not retry automatically');
  }
  return { result, plaintextToken };
}

async function main() {
  let terminal = null;
  const state = { issuanceAttempted: false };
  try {
    const gate = assertExecutionGate();
    terminal = openSecureTerminal();
    await verifyTarget(gate.serviceRoleKey);
    const issuance = await issue(gate.serviceRoleKey, state);
    fs.writeSync(terminal, [
      '',
      'ONE-TIME PRODUCTION PLATFORM CREDENTIAL BOOTSTRAP TOKEN',
      issuance.plaintextToken,
      'Enter it immediately into Production → Enroll owner security credential.',
      'Do not copy it to files, logs, URLs, chat, or browser storage.',
      '',
    ].join('\n'));
    process.stdout.write(`${JSON.stringify({
      authorizationId: issuance.result.authorizationId,
      auditId: issuance.result.auditId,
      expiresInSeconds: issuance.result.expiresInSeconds,
      intendedUserId: INTENDED_USER_ID,
      intendedDeviceId: INTENDED_DEVICE_ID,
      environment: ENVIRONMENT,
      origin: EXPECTED_ORIGIN,
      rpId: RP_ID,
    })}\n`);
  } catch (error) {
    const suffix = state.issuanceAttempted ? '; issuance may have succeeded, do not retry automatically' : '';
    process.stderr.write(`Production credential bootstrap stopped: ${error instanceof Error ? error.message : 'unknown error'}${suffix}\n`);
    process.exitCode = 1;
  } finally {
    if (terminal !== null) fs.closeSync(terminal);
  }
}

main();
