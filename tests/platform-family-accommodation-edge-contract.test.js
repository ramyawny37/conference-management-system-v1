'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const edge = fs.readFileSync(path.join(root, 'supabase/functions/platform-device-operation/index.ts'), 'utf8');
const operation = 'save_conference_family_accommodation_draft';

test('canonical family accommodation save crosses the single conference device gateway', () => {
  const registration = "conference.add('" + operation + "');";
  assert.equal(edge.split(registration).length - 1, 1, 'exactly one canonical gateway registration');
  assert.match(edge, /const allowed=module==='platform'\?platform:module==='conference'\?conference/);
  assert.match(edge, /if\(!allowed\.has\(operation\)\)throw new Error\('PLATFORM_OPERATION_NOT_ALLOWED'\)/);
  assert.match(edge, /schema\('platform'\)\.rpc\('execute_device_operation'/);
  assert.doesNotMatch(edge, /\.rpc\('save_conference_family_accommodation_draft'/);
});
