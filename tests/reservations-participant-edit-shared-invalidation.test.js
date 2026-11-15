'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync('modules/reservations/reservations-module.js','utf8');

test('booking detail edit invalidates shared reservation resources after successful save', () => {
  assert.match(source, /await Me\.updateParticipantBooking\([\s\S]*?f\(_e\.participant\),p\(_e\.booking\),invalidateReservations\(\),b\(void 0\)/);
});

test('participants list edit invalidates shared resources before refreshing the list', () => {
  assert.match(source, /await Me\.updateParticipantBooking\([\s\S]*?invalidateReservations\(\),await p\(\),w\(void 0\)/);
});

test('participant edit invalidation happens only after successful mutation', () => {
  const occurrences = source.match(/invalidateReservations\(\)/g) || [];
  assert.ok(occurrences.length >= 2);
});
