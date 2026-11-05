'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const worker = read('service-worker.js');

test('reservations runtime assets have one matching revision in HTML and service worker', () => {
  for (const extension of ['js', 'css']) {
    const asset = `modules/reservations/reservations-module.${extension}`;
    const escaped = asset.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const matches = [...html.matchAll(new RegExp(escaped + '\\?rev=([A-Za-z0-9_-]+)', 'g'))];
    assert.equal(matches.length, 1, `exactly one HTML reference for ${asset}`);
    const revision = matches[0][1];
    assert.ok(fs.existsSync(path.join(root, asset)), `missing ${asset}`);
    assert.ok(worker.includes(`./${asset}?rev=${revision}`),
      `service worker and HTML revision differ for ${asset}`);
  }
});

test('canonical reservations identity flow is present in the shipped module', () => {
  const moduleSource = read('modules/reservations/reservations-module.js');
  assert.match(moduleSource, /function ManualPersonIdentityModal/);
  assert.match(moduleSource, /function useManualPersonIdentityResolution/);
  assert.equal((moduleSource.match(/function useReservationScopeDialog/g) || []).length, 1);
  assert.match(moduleSource, /dateOfBirth/);
  assert.match(moduleSource, /createRoot/);
});

test('retired reservations artifact workflows cannot silently restore a second publishing path', () => {
  for (const file of [
    '.github/workflows/integrate-reservations-batch-church.yml',
    '.github/workflows/verify-private-reservations-artifact.yml',
  ]) {
    assert.equal(fs.existsSync(path.join(root, file)), false, `retired workflow reappeared: ${file}`);
  }
});
