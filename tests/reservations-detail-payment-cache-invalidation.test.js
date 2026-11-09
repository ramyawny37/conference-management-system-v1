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


test('financial settlement summary participates in shared reservations cache invalidation', () => {
  assert.ok(source.includes('financialResource=$l(`cancellation-financial-summary:${c}`,()=>Me.cancellationFinancialSummary(c),!!c)'));
  assert.ok(source.includes('financialLoading=!!c&&(financialResource.status==="idle"||financialResource.status==="loading")'));
  assert.ok(source.includes('onDone:async()=>{setReportRefund(null);setRefundActionError("");await financialResource.refresh()}'));
  assert.doesNotMatch(source, /setFinancialSummary|setFinancialError|setFinancialLoading/);
});

\ntest('payments workspace invalidates every shared reservation resource after record and void', () => {
  assert.match(source, /function oC\(\)\{const\{mode:t\}=vn\(\),\{invalidate:invalidateReservations\}=tr\(\),\{data:a,loading:i,error:s,ready:c\}=wo\("payments"\)/);
  assert.ok(source.includes('await Me.recordPayment(ee.booking.id,D),invalidateReservations(),T("تم تسجيل الدفعة وتحديث السجل")'));
  assert.ok(source.includes('await Me.voidPayment(A.id,D),invalidateReservations(),S(void 0),T("تم إلغاء الدفعة وتحديث السجل")'));
});

test('booking list payment and finish-procedures payment invalidate the shared reservations cache', () => {
  assert.ok(source.includes('function bb({defaultEventId:t="all"}){const{mode:a}=vn(),{invalidate:invalidateReservations}=tr()'));
  assert.ok(source.includes('await Me.recordPayment(W.booking.id,ae),invalidateReservations(),O("تم تسجيل الدفعة وتحديث بيانات الحجز")'));
  assert.ok(source.includes('if(await Me.recordPayment(N.booking.id,X),!S.current.owns(ue))return;i.invalidate();await Yr(N)'));
});
