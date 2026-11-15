const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync('modules/reservations/reservations-module.js', 'utf8');

test('payment and review are independently offered while both are pending', () => {
  const start = source.indexOf('function Xw(');
  const end = source.indexOf('function cn(', start);
  assert.ok(start >= 0 && end > start);
  const block = source.slice(start, end);
  assert.match(block, /const f=t>0,aPending=!a/);
  assert.match(block, /f&&v\.push\(l\.jsxs\(Se,\{ref:i,onClick:s/);
  assert.match(block, /aPending&&v\.push\(l\.jsxs\(Se,\{onClick:c/);
  assert.match(block, /إتمام المراجعة/);
  assert.match(block, /تسجيل دفعة/);
  assert.doesNotMatch(block, /t>0\?\(/);
});

test('readiness still requires completed review and no outstanding balance', () => {
  assert.match(source, /function Gw\(t\).*?reviewStatus\)!==["']completed["']&&a\.push/);
  assert.match(source, /t\.remainingBalance>0&&a\.push/);
  assert.match(source, /onReview:U,pending:aa/);
  assert.match(source, /updateOperationalReview\(N\.booking\.id,O\.revision\?\?0,["']completed["']\)/);
});
