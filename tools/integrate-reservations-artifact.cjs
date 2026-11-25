#!/usr/bin/env node
'use strict';
// Integrate an immutable Reservations CI artifact into Conference develop.
// Usage: node tools/integrate-reservations-artifact.cjs /path/to/reservations-develop-integration-package.zip
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const archive = process.argv[2];
if (!archive) throw new Error('Pass the verified Reservations integration ZIP path');
const policyPath = path.join(__dirname, 'reservations-artifact-policy.json');
const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));
const artifactNames = ['reservations-module.js', 'reservations-module.css'];
const contractName = 'reservations-contract.json';
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'cms-reservations-'));
function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}
function sameFiles(actual, expected) {
  return artifactNames.every((name) => actual[name] === expected[name]);
}
function replaceOnce(source, before, after, label) {
  if (source.split(before).length !== 2) throw new Error(label + ': expected exactly one original reference');
  return source.replace(before, after);
}
try {
  const branch = execFileSync('git', ['branch', '--show-current'], {cwd: root, encoding:'utf8'}).trim();
  if (branch !== 'develop') throw new Error('Refusing integration outside Conference develop (found ' + branch + ')');
  const dirty = execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding:'utf8'}).trim();
  if (dirty) throw new Error('Working tree must be clean before integration');
  execFileSync('unzip', ['-q', path.resolve(archive), '-d', temp]);
  const payloads = {};
  const actualHashes = {};
  for (const name of artifactNames) {
    const nested = path.join(temp, 'modules', 'reservations', name);
    const flat = path.join(temp, name);
    const source = fs.existsSync(nested) ? nested : flat;
    if (!fs.existsSync(source)) throw new Error('Artifact missing: ' + name);
    const bytes = fs.readFileSync(source);
    actualHashes[name] = sha256(bytes);
    payloads[name] = bytes;
  }
  const contractSource = fs.existsSync(path.join(temp, contractName)) ? path.join(temp, contractName) : path.join(temp, 'modules', 'reservations', contractName);
  if (!fs.existsSync(contractSource)) throw new Error('Artifact missing: ' + contractName);
  const contractBytes = fs.readFileSync(contractSource);
  const contract = JSON.parse(contractBytes.toString('utf8'));
  if (contract.ownership !== 'reservation-management-system' || !Array.isArray(contract.requiredBehaviors)) throw new Error('RESERVATIONS_ARTIFACT_CONTRACT_INVALID');
  const rejected = policy.rejectedArtifacts.find((entry) => sameFiles(actualHashes, entry.files));
  if (rejected) throw new Error('RESERVATIONS_ARTIFACT_REJECTED:' + rejected.sourceCommit + ':' + rejected.reason);
  const approved = policy.approvedIntegrations.find((entry) => sameFiles(actualHashes, entry.files));
  if (!approved) throw new Error('RESERVATIONS_ARTIFACT_NOT_APPROVED:' + JSON.stringify(actualHashes));
  if (!/^[0-9a-f]{40}$/.test(approved.sourceCommit || '')) throw new Error('Approved source commit is invalid');
  if (!/^[a-z0-9][a-z0-9-]{2,80}$/.test(approved.revision || '')) throw new Error('Approved cache revision is invalid');
  for (const name of artifactNames) {
    const currentPath = path.join(root, 'modules', 'reservations', name);
    const currentHash = sha256(fs.readFileSync(currentPath));
    if (currentHash !== policy.currentRuntime.files[name]) {
      throw new Error('CURRENT_RESERVATIONS_RUNTIME_DRIFT:' + name + ':' + currentHash);
    }
  }
  const indexPath = path.join(root, 'index.html');
  const swPath = path.join(root, 'service-worker.js');
  let index = fs.readFileSync(indexPath, 'utf8');
  let sw = fs.readFileSync(swPath, 'utf8');
  for (const name of artifactNames) {
    const oldRev = policy.currentRuntime.revision;
    const oldRef = 'modules/reservations/' + name + '?rev=' + oldRev;
    const newRef = 'modules/reservations/' + name + '?rev=' + approved.revision;
    index = replaceOnce(index, oldRef, newRef, 'index.html ' + name);
    // Service-worker asset URLs are root-relative and include a leading "./".
    const swOldRef = './' + oldRef;
    const swNewRef = './' + newRef;
    sw = replaceOnce(sw, swOldRef, swNewRef, 'service-worker.js ' + name);
  }
  sw = replaceOnce(sw, "'development-" + policy.currentRuntime.revision + "'", "'development-" + approved.revision + "'", 'Development cache revision');
  // Validate all references and checksums before modifying any tracked file.
  for (const [name, bytes] of Object.entries(payloads)) {
    fs.writeFileSync(path.join(root, 'modules', 'reservations', name), bytes);
  }
  fs.writeFileSync(indexPath, index);
  fs.writeFileSync(swPath, sw);
  fs.writeFileSync(path.join(root, 'modules', 'reservations', contractName), contractBytes);
  policy.currentRuntime = { revision: approved.revision, files: actualHashes, contract: { version: contract.contractVersion, sha256: sha256(contractBytes) } };
  policy.approvedIntegrations = [];
  fs.writeFileSync(policyPath, JSON.stringify(policy, null, 2) + '\\n');
  execFileSync('git', ['diff', '--check'], {cwd: root, stdio:'inherit'});
  console.log('Integrated verified Reservations artifact into Conference develop working tree.');
  console.log('Source Reservations commit: ' + approved.sourceCommit);
  console.log('Review git diff, run checks, then commit/push develop only.');
} finally {
  fs.rmSync(temp, {recursive:true, force:true});
}
