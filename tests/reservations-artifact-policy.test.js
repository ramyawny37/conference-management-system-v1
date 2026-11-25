'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const policy = JSON.parse(fs.readFileSync(path.join(root, 'tools', 'reservations-artifact-policy.json'), 'utf8'));
const integrator = fs.readFileSync(path.join(root, 'tools', 'integrate-reservations-artifact.cjs'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const worker = fs.readFileSync(path.join(root, 'service-worker.js'), 'utf8');
const digest = (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

test('current runtime baseline is exact and loaded atomically', () => {
  for (const [name, expected] of Object.entries(policy.currentRuntime.files)) {
    assert.equal(digest(path.join(root, 'modules', 'reservations', name)), expected);
    const reference = `modules/reservations/${name}?rev=${policy.currentRuntime.revision}`;
    assert.ok(index.includes(reference));
    assert.ok(worker.includes(`./${reference}`));
  }
  assert.ok(worker.includes(`development-${policy.currentRuntime.revision}`));
});

test('reverted c56 artifact is explicitly rejected and cannot be approved simultaneously', () => {
  const rejected = policy.rejectedArtifacts.find((entry) => entry.sourceCommit === 'c56a8fdd2ccde4405a3c73f3580b27b08b1cf5c9');
  assert.ok(rejected);
  assert.equal(rejected.files['reservations-module.js'], '4be3dc01c762f6f9b67f5f3fae74ca1d7f684d7777e2787bec8376b915f37ffe');
  assert.equal(rejected.files['reservations-module.css'], '72925581c479521cb6dcf15b99b851c5bcd1dcc8e89da21d7c35a3eab6ee060d');
  assert.equal(policy.approvedIntegrations.some((entry) => entry.sourceCommit === rejected.sourceCommit), false);
  assert.match(integrator, /RESERVATIONS_ARTIFACT_REJECTED/);
  assert.match(integrator, /RESERVATIONS_ARTIFACT_NOT_APPROVED/);
});

test('integration is fail closed and permits at most one explicitly approved artifact', () => {
  assert.ok(Array.isArray(policy.approvedIntegrations));
  assert.ok(policy.approvedIntegrations.length <= 1);
  for (const entry of policy.approvedIntegrations) {
    assert.match(entry.sourceCommit, /^[0-9a-f]{40}$/);
    assert.match(entry.revision, /^[a-z0-9][a-z0-9-]{2,80}$/);
    assert.ok(entry.files['reservations-module.js']);
    assert.ok(entry.files['reservations-module.css']);
  }
  assert.match(integrator, /CURRENT_RESERVATIONS_RUNTIME_DRIFT/);
  assert.match(integrator, /branch !== 'develop'/);
  assert.match(integrator, /preserve the independently owned Platform design suffix/);
  assert.doesNotMatch(integrator, /"'development-" \+ policy\.currentRuntime\.revision/);
});
