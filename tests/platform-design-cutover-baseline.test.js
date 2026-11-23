'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const worker = read('service-worker.js');
const tokens = read('shared-design-tokens.css');
const shell = read('canonical-platform-shell.css');

test('all active runtime CSS assets use identical revisioned URLs in HTML and service worker', () => {
  const links = [...html.matchAll(/<link\b[^>]*rel=["']stylesheet["'][^>]*href=["']([^"']+)["']/g)].map(match => match[1]);
  assert.ok(links.length >= 4, 'expected the four current CSS layers');
  for (const url of links) {
    assert.ok(url.includes('?rev='), 'CSS asset must have a revision: ' + url);
    assert.equal(worker.split("'./" + url + "'").length - 1, 1, 'cache asset must match HTML exactly once: ' + url);
  }
});

test('approved design foundation values are present in the active runtime', () => {
  assert.match(tokens, /--platform-primary\s*:\s*#0a6cff\s*;/i);
  assert.match(tokens, /--platform-control-height\s*:\s*36px\s*;/);
  assert.match(tokens, /--platform-font-size-body\s*:\s*14px\s*;/);
  assert.match(shell, /--canonical-sidebar-width\s*:\s*224px\s*;/);
  assert.match(tokens, /--platform-touch-target\s*:\s*44px\s*;/);
});

test('the current four-layer stylesheet order is explicit', () => {
  const paths = [
    'shared-design-tokens.css',
    'style.css',
    'modules/reservations/reservations-module.css',
    'canonical-platform-shell.css'
  ];
  let previous = -1;
  for (const css of paths) {
    const at = html.indexOf('href="' + css + '?rev=');
    assert.ok(at > previous, 'missing or out-of-order stylesheet: ' + css);
    previous = at;
  }
});
