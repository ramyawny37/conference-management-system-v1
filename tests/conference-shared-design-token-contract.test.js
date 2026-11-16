'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const root = path.join(__dirname, '..');
const tokens = fs.readFileSync(path.join(root, 'shared-design-tokens.css'), 'utf8');
const conference = fs.readFileSync(path.join(root, 'style.css'), 'utf8');
const shell = fs.readFileSync(path.join(root, 'canonical-platform-shell.css'), 'utf8');
const reservations = fs.readFileSync(path.join(root, 'modules/reservations/reservations-module.css'), 'utf8');

test('shared visual values remain equivalent to the approved Conference presentation', () => {
  const values = {
    '--platform-surface': '#fff',
    '--platform-text-on-color': '#fff',
    '--platform-secondary': '#2e75b6',
    '--platform-radius-sm': '8px',
    '--platform-radius-control': '9px',
    '--platform-radius-md': '12px',
    '--platform-space-2': '6px',
    '--platform-space-3': '8px',
    '--platform-space-4': '10px',
    '--platform-space-7': '20px'
  };
  for (const [name, value] of Object.entries(values)) {
    assert.ok(tokens.includes(name + ':' + value + ';'), name + ' value changed');
  }
});

test('accommodation consumes shared tokens without adding a competing stylesheet', () => {
  assert.ok(conference.includes('.accommodation-search{background:var(--platform-surface)'));
  assert.ok(conference.includes('#tab0 .accommodation-room-card{border:1px solid #dce6ef;border-top:3px solid var(--room-status-color);background:var(--platform-surface)'));
  assert.ok(conference.includes('.accommodation-quick-filters button{flex:0 0 auto;border:1px solid #dbe6f0;border-radius:var(--platform-radius-control)'));
  assert.ok(conference.includes('.accommodation-room-key{display:flex;align-items:center;gap:7px;margin-top:var(--platform-space-3)'));
  assert.ok(conference.includes('.accommodation-floor-header{display:flex;width:100%;justify-content:space-between;align-items:center;gap:var(--platform-space-2)'));
});

test('shell and reservations retain their existing separate CSS ownership', () => {
  assert.ok(!shell.includes(':root{'));
  assert.ok(!shell.includes('#reservationsWorkspace'));
  assert.ok(reservations.includes('.reference-dashboard{'));
  assert.ok(reservations.includes('.reference-hero{'));
});
