const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');

test('canonical shell owns compact desktop geometry and floating header composition', () => {
  const css = read('platform-shell-v2.css');
  const tokens = read('shared-design-tokens.css');

  assert.match(css, /--platform-v2-sidebar-width:\s*196px/);
  assert.match(tokens, /--platform-v2-sidebar-width:196px/);
  assert.match(css, /--platform-v2-header-height:\s*64px/);
  assert.match(css, /\.platform-sidebar\s*\{/);
  assert.match(css, /width:\s*var\(--platform-v2-sidebar-width\)\s*!important/);
  assert.match(css, /\.application-shell\s*\{[\s\S]*margin-inline-end:\s*var\(--platform-v2-sidebar-width\)\s*!important/);
  assert.match(css, /\.topbar\s*\{[\s\S]*margin:\s*10px 12px -6px\s*!important/);
  assert.match(css, /\.topbar::before,[\s\S]*\.topbar::after\s*\{[\s\S]*content:\s*none\s*!important/);
});

test('reservations workspace is visually integrated below the floating shell header', () => {
  const css = read('platform-shell-v2.css');
  assert.match(css, /\.reservations-module\s*\{[\s\S]*padding:\s*0 12px 16px\s*!important/);
  assert.match(css, /\.reservations-context-bar/);
  assert.match(css, /border-radius:\s*12px 12px 0 0\s*!important/);
  assert.match(css, /\.reservations-hero/);
  assert.match(css, /border-radius:\s*0 0 16px 16px\s*!important/);
});

test('shell collapses progressively for tablet and mobile without horizontal overflow', () => {
  const css = read('platform-shell-v2.css');
  assert.match(css, /@media \(max-width:\s*1180px\)/);
  assert.match(css, /--platform-v2-sidebar-width:\s*176px/);
  assert.match(css, /@media \(max-width:\s*900px\)/);
  assert.match(css, /--platform-v2-sidebar-width:\s*72px/);
  assert.match(css, /@media \(max-width:\s*640px\)/);
  assert.match(css, /--platform-v2-sidebar-width:\s*0px/);
  assert.match(css, /\.application-shell\s*\{[\s\S]*margin-inline-end:\s*0\s*!important/);
  assert.match(css, /\.platform-sidebar\s*\{[\s\S]*height:\s*58px\s*!important/);
});

test('legacy pseudo-brand duplication is explicitly retired by the canonical shell', () => {
  const css = read('platform-shell-v2.css');
  assert.match(css, /\.topbar::before,[\s\S]*\.topbar::after\s*\{\s*content:\s*none\s*!important;\s*display:\s*none\s*!important;\s*\}/);
});
