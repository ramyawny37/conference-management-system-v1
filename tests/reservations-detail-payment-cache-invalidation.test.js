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

\ntest('financial settlement summary participates in shared reservations cache invalidation', () => {
  assert.match(source, /financialResource=\$l\(\x60cancellation-financial-summary:\$\{c\}\x60,\(\)=>Me\.cancellationFinancialSummary\(c\),!!c\)/);
  assert.match(source, /financialLoading=!!c&&\(financialResource\.status==="idle"\|\|financialResource\.status==="loading"\)/);
  assert.match(source, /onDone:async\(\)=>\{setReportRefund\(null\);setRefundActionError\(" "\);await financialResource\.refresh\(\)\}/);
  assert.doesNotMatch(source, /setFinancialSummary|setFinancialError|setFinancialLoading/);
});
