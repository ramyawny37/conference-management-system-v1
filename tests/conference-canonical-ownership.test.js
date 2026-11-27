'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('active Conference presentation and canonical service files are loaded exactly once', () => {
  const index = read('index.html');
  const active = [
    'js/platform-integration.js',
    'js/supabase/canonical-conference-transport.js',
    'people.js',
    'houses.js',
    'transport.js',
    'js/conference/accounts.js',
    'cards.js',
    'script.js',
  ];
  for (const file of active) {
    const matches = index.match(new RegExp(`<script src="${file.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\?`, 'g')) || [];
    assert.equal(matches.length, 1, `${file} must have one active runtime load`);
  }
  assert.ok(index.indexOf('js/platform-integration.js?') < index.indexOf('script.js?'));
});

test('active browser runtime has no direct table mutation writer', () => {
  const files = [
    'script.js', 'people.js', 'houses.js', 'transport.js', 'cards.js',
    'js/conference/accounts.js', 'js/platform-integration.js',
    'js/supabase/canonical-conference-transport.js',
    'js/supabase/canonical-conference-restaurant.js',
    ...fs.readdirSync(path.join(root, 'js', 'warehouse')).filter((name) => name.endsWith('.js')).map((name) => `js/warehouse/${name}`),
  ];
  const directMutation = /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/;
  for (const file of files) assert.doesNotMatch(read(file), directMutation, `${file} bypasses protected writer ownership`);
});

test('canonical mutations use protected dispatch and refresh authoritative state', () => {
  const integration = read('js/platform-integration.js');
  assert.match(integration, /invokeProtected\('conference','mutate_conference_core'/);
  assert.match(integration, /invokeProtected\('conference',operation,args\)/);
  assert.match(integration, /invokeProtected\('conference','mutate_conference_accommodation_operations'/);
  assert.match(integration, /then\(function\(\)\{return hydrateConferenceAccommodation\(localId,record\.remoteConferenceId\)\}/);
  assert.match(integration, /Promise\.all\(\[hydrateConferenceAccommodation\(localId,record\.remoteConferenceId\),hydrateConferenceParticipations\(localId,record\.remoteConferenceId\)\]\)/);

  const transport = read('js/supabase/canonical-conference-transport.js');
  assert.match(transport, /invokeModuleProtected\('conference',operation,args\|\|\{\}\)/);
  assert.match(transport, /function refreshAfter\(localId,promise\).*hydrate\(localId,conferenceId\)/);
  assert.match(transport, /return refreshAfter\(localId,invoke\('mutate_conference_transport_vehicle'/);

  const accounts = read('js/conference/accounts.js');
  assert.match(accounts, /CanonicalConferenceFinance\.mutate/);
  assert.match(accounts, /mutateConferenceAirConditioning/);
});

test('Reservations generated runtime remains governed by the artifact policy', () => {
  const policy = JSON.parse(read('tools/reservations-artifact-policy.json'));
  assert.ok(Array.isArray(policy.approvedIntegrations));
  assert.ok(policy.approvedIntegrations.length <= 1);
  for (const entry of policy.approvedIntegrations) {
    assert.match(entry.sourceCommit, /^[0-9a-f]{40}$/);
    assert.deepEqual(Object.keys(entry).sort(), ['sourceCommit']);
  }
  assert.ok(policy.rejectedArtifacts.some((entry) => entry.sourceCommit === 'c56a8fdd2ccde4405a3c73f3580b27b08b1cf5c9'));
  assert.equal(read('modules/reservations/reservations-module.js').includes('PlatformIntegration'), true);
});
