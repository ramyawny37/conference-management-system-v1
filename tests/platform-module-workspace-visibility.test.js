'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const css=fs.readFileSync('canonical-platform-shell.css','utf8');

test('Reservations active state hides peer workspaces and owns the visible workspace',()=>{
  assert.match(css,/\.canonical-platform-workspace-host\.platform-reservations-active \.canonical-platform-workspace>\.conference-workspace:not\(:has\(\[data-reservations-module-root\]\)\)\{display:none\}/);
});

test('Conference and Warehouse active states hide the Reservations workspace',()=>{
  assert.match(css,/\.canonical-platform-workspace-host\.platform-conference-active \.canonical-platform-workspace>\.conference-workspace:has\(\[data-reservations-module-root\]\)/);
  assert.match(css,/\.canonical-platform-workspace-host\.platform-warehouse-active \.canonical-platform-workspace>\.conference-workspace:has\(\[data-reservations-module-root\]\)/);
});

test('workspace visibility ownership does not use important overrides',()=>{
  const rules=css.match(/\.canonical-platform-workspace-host\.platform-(?:reservations|conference|warehouse)-active[^\n]+/g)||[];
  assert.ok(rules.length>=2);
  assert.equal(rules.some(rule=>rule.includes('!important')),false);
});
