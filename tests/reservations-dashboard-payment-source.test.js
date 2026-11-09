const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert/strict');

const source = fs.readFileSync('modules/reservations/reservations-module.js', 'utf8');

test('reservations dashboard uses payment-enriched booking rows for collected totals', () => {
  const mapper = source.match(/function dg\(t,a,i\)\{[\s\S]*?\}function tt\(/);
  assert.ok(mapper, 'dashboard response mapper must exist');
  assert.match(mapper[0], /bookings:Xe\(i\)\.map\(er\)/);
  assert.doesNotMatch(mapper[0], /bookings:Xe\(a\.bookings\)\.map\(er\)/);
  assert.match(source, /totalPaid:t\.total_paid==null\?void 0:ut\(t,\"total_paid\"\)/);
});
