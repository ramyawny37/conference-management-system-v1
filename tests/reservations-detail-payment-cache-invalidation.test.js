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
  assert.ok(source.includes('financialResource=$l(`cancellation-financial-summary:${c}`,()=>Me.cancellationFinancialSummary(c),!!c)'));
  assert.ok(source.includes('financialLoading=!!c&&(financialResource.status==="idle"||financialResource.status==="loading")'));
  assert.ok(source.includes('onDone:async()=>{setReportRefund(null);setRefundActionError("");await financialResource.refresh()}'));
  assert.doesNotMatch(source, /setFinancialSummary|setFinancialError|setFinancialLoading/);
});
