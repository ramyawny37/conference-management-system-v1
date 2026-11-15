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
const expected = {
  'reservations-module.js': '4be3dc01c762f6f9b67f5f3fae74ca1d7f684d7777e2787bec8376b915f37ffe',
  'reservations-module.css': '049a9fe2e16dd54ae9bb477910732cb610d16a50bce12feb594d0e747e66f632',
};
const rev = 'reservations-design-b8f93367-v1';
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'cms-reservations-'));
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
  for (const [name, hash] of Object.entries(expected)) {
    const nested = path.join(temp, 'modules', 'reservations', name);
    const flat = path.join(temp, name);
    const source = fs.existsSync(nested) ? nested : flat;
    if (!fs.existsSync(source)) throw new Error('Artifact missing: ' + name);
    const bytes = fs.readFileSync(source);
    const actual = crypto.createHash('sha256').update(bytes).digest('hex');
    if (actual !== hash) throw new Error(name + ' SHA256 mismatch: ' + actual);
    payloads[name] = bytes;
  }
  const indexPath = path.join(root, 'index.html');
  const swPath = path.join(root, 'service-worker.js');
  let index = fs.readFileSync(indexPath, 'utf8');
  let sw = fs.readFileSync(swPath, 'utf8');
  const refs = {
    'reservations-module.css': 'reservations-lifecycle-active-only-v4',
    'reservations-module.js': 'reservations-lifecycle-active-only-v4',
  };
  for (const [name, oldRev] of Object.entries(refs)) {
    const oldRef = 'modules/reservations/' + name + '?rev=' + oldRev;
    const newRef = 'modules/reservations/' + name + '?rev=' + rev;
    index = replaceOnce(index, oldRef, newRef, 'index.html ' + name);
    sw = replaceOnce(sw, oldRef, newRef, 'service-worker.js ' + name);
  }
  sw = replaceOnce(sw, "'development-reservations-lifecycle-active-only-v4'", "'development-" + rev + "'", 'Development cache revision');
  // Validate all references and checksums before modifying any tracked file.
  for (const [name, bytes] of Object.entries(payloads)) {
    fs.writeFileSync(path.join(root, 'modules', 'reservations', name), bytes);
  }
  fs.writeFileSync(indexPath, index);
  fs.writeFileSync(swPath, sw);
  execFileSync('git', ['diff', '--check'], {cwd: root, stdio:'inherit'});
  console.log('Integrated verified Reservations artifact into Conference develop working tree.');
  console.log('Source Reservations commit: d438f051a8e62607e1a081045fe05d104a63266a');
  console.log('Review git diff, run checks, then commit/push develop only.');
} finally {
  fs.rmSync(temp, {recursive:true, force:true});
}
