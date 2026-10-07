'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const testsDir = path.join(root, 'tests');

function runNode(args) {
  const result = spawnSync(process.execPath, args, {
    cwd: root,
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}

runNode(['--check', 'js/storage/environment-namespace.js']);
runNode(['--check', 'service-worker.js']);
runNode(['tests/browser-storage-isolation.test.js']);

const retiredAuthorityArtifacts = [
  'js/sync/device-authorization-operation-repository.js',
  'tools/approve-development-pending-device.cjs',
  'tools/verify-development-organization-templates-realtime.cjs',
  'supabase/device-authorization-foundation-readonly-verification.sql',
  'supabase/webauthn-privileged-device-security-foundation-readonly-verification.sql',
  'supabase/organization-access-role-variable-fix-readonly-verification.sql',
  'supabase/organization-administration-rpc-reads-readonly-verification.sql',
  'supabase/organization-member-list-role-variable-fix-readonly-verification.sql',
  'supabase/reservations-phase1br-runtime-verification.sql',
];

for (const artifact of retiredAuthorityArtifacts) {
  if (fs.existsSync(path.join(root, artifact))) {
    throw new Error(`RETIRED_AUTHORITY_ARTIFACT_PRESENT:${artifact}`);
  }
}


const platformTests = fs.readdirSync(testsDir)
  .filter((name) => /^platform-.*\.test\.js$/.test(name))
  .filter((name) => name !== 'platform-promotion-readiness.test.js')
  .sort()
  .map((name) => path.join('tests', name));

if (platformTests.length === 0) {
  throw new Error('DEVELOPMENT_PREVIEW_PLATFORM_TESTS_NOT_FOUND');
}

runNode(['--test', ...platformTests]);

for (const artifact of [
  'modules/reservations/reservations-module.js',
  'modules/reservations/reservations-module.css',
]) {
  if (!fs.existsSync(path.join(root, artifact))) {
    throw new Error(`DEVELOPMENT_PREVIEW_ARTIFACT_MISSING:${artifact}`);
  }
}

process.stdout.write(`Development preview validation passed (${platformTests.length} platform test files).\n`);
