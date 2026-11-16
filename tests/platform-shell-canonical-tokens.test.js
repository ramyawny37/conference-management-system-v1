'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');

test('platform shell consumes canonical design tokens without transitional v2 aliases', () => {
  const shell = read('canonical-platform-shell.css');
  const tokens = read('shared-design-tokens.css');
  assert.doesNotMatch(shell, /var\(--platform-v2-(?:border|navy|text)\)/);
  for (const name of ['border', 'primary-dark', 'text']) {
    assert.match(shell, new RegExp('var\\(--platform-' + name + '\\)'));
    assert.match(tokens, new RegExp('--platform-' + name + '\\s*:'));
  }
});

test('Reservations generated styles remain a separately owned active artifact', () => {
  const html = read('index.html');
  const policy = JSON.parse(read('tools/reservations-artifact-policy.json'));
  assert.match(html, /modules\/reservations\/reservations-module\.css/);
  assert.equal(policy.approvedIntegrations.length, 0);
});
