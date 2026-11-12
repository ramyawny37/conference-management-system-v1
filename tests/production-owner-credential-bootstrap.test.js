'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

const script = path.resolve(__dirname, '../tools/issue-production-owner-credential-bootstrap.cjs');

test('production issuer is pinned to Production and requires explicit authorization', () => {
  const source = fs.readFileSync(script, 'utf8');
  assert.match(source, /PROJECT_REF = 'mpezfbvcdfxpgflehuot'/);
  assert.match(source, /ENVIRONMENT = 'production'/);
  assert.match(source, /PRODUCTION_CREDENTIAL_BOOTSTRAP_ENABLED/);
  assert.match(source, /openSecureTerminal\(\)/);
  assert.match(source, /require_canonical|issuance RPC enforces canonical/);
  assert.doesNotMatch(source, /916c0d83-4c5a-4a9e-89bb-4faa671166f7|4e9890fc-3389-4fd4-a530-51fde49cf0de/);
});

test('production issuer refuses execution without explicit enablement and credentials', () => {
  const result = spawnSync(process.execPath, [script], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH || '', OWNER_USER_ID: '00000000-0000-4000-8000-000000000001', APPROVED_OWNER_DEVICE_ID: '00000000-0000-4000-8000-000000000002' },
    timeout: 5000,
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /PRODUCTION_CREDENTIAL_BOOTSTRAP_ENABLED must equal true/);
  assert.doesNotMatch(result.stdout, /TOKEN/);
});

test('production issuer rejects execution without secure controlling terminal', () => {
  const result = spawnSync(process.execPath, [script], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH || '', OWNER_USER_ID: '00000000-0000-4000-8000-000000000001', APPROVED_OWNER_DEVICE_ID: '00000000-0000-4000-8000-000000000002', PRODUCTION_CREDENTIAL_BOOTSTRAP_ENABLED: 'true', SUPABASE_SERVICE_ROLE_KEY: 'test-only-not-a-real-key' },
    timeout: 5000,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /controlling secure terminal is required/);
});
