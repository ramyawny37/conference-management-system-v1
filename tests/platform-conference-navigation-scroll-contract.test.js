'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const script = fs.readFileSync(path.join(__dirname, '..', 'script.js'), 'utf8');

test('changing conference tabs resets document scroll, but re-rendering the same tab does not', () => {
  const start = script.indexOf('function switchTab(n,options){');
  const end = script.indexOf('\nfunction getApplicationTabIdByName(', start);
  assert.ok(start >= 0 && end > start, 'canonical tab navigation must exist');
  const body = script.slice(start, end);
  assert.match(body, /var previousTab=currentTab;/);
  assert.match(body, /currentTab=tabId;/);
  assert.match(body, /renderTab\(tabId\);[\s\S]*?if\(previousTab!==tabId\)resetAdministrativeViewScroll\(\);/);
  assert.doesNotMatch(body, /window\.scrollTo\(/, 'use the existing centralized scroll helper');
});

test('administrative navigation retains its dedicated scroll reset', () => {
  assert.match(script, /function switchSettingsTab\(tab\)[\s\S]*?resetAdministrativeViewScroll\(\);/);
  assert.match(script, /function resetAdministrativeViewScroll\(\)[\s\S]*?window\.scrollTo/);
});
