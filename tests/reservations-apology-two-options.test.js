const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../modules/reservations/reservations-module.js'), 'utf8');
const start = source.indexOf('function CancellationSettlementDialog(');
const end = source.indexOf('function Kw(', start);
test('apology UI offers only full non-refundable or full pending refund', () => {
  assert.ok(start >= 0 && end > start);
  const dialog = source.slice(start, end);
  assert.match(dialog, /mode==="none"\?\[total,0,0,0\]:\[0,0,0,total\]/);
  assert.match(dialog, /\["none","بدون استرداد"/);
  assert.match(dialog, /\["pending","مع استرداد"/);
  assert.doesNotMatch(dialog, /\["credit","رصيد للشخص"|\["custom","تسوية مخصصة"|\["refund","استرداد فعلي"/);
  assert.match(dialog, /refunded:allocation\[1\],credit:allocation\[2\],pending:allocation\[3\]/);
});
