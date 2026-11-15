'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync('modules/reservations/reservations-module.js','utf8');

test('booking detail edit invalidates shared resources after successful save', () => {
  assert.match(source, /await Me\.updateParticipantBooking\([\s\S]*?f\(_e\.participant\),p\(_e\.booking\),invalidateReservations\(\),b\(void 0\)/);
});

test('participants list edit invalidates shared resources and completes without an undefined refresh call', () => {
  assert.match(source, /await Me\.updateParticipantBooking\([\s\S]*?invalidateReservations\(\),w\(void 0\),V\(""\),O\("تم حفظ التعديل"\)/);
  assert.doesNotMatch(source, /invalidateReservations\(\),await p\(\)/);
});
