const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('modules/reservations/reservations-module.js', 'utf8');

test('booking detail payment immediately invalidates shared reservation data', () => {
  assert.match(source, /await Me\.recordPayment\(m\.id,_e\),invalidateReservations\(\),T\(await Me\.listPayments\(m\.id\)\)/);
});

test('booking detail voided payment immediately invalidates shared reservation data', () => {
  assert.match(source, /await Me\.voidPayment\(q\.id,_e\),invalidateReservations\(\),T\(await Me\.listPayments\(m\.id\)\)/);
});
