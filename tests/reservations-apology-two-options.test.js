const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../modules/reservations/reservations-module.js'), 'utf8');
const start = source.indexOf('function CancellationSettlementDialog(');
const end = source.indexOf('function RefundPayoutDialog(', start);
test('apology UI offers only full non-refundable or full pending refund', () => {
  assert.ok(start >= 0 && end > start);
  const dialog = source.slice(start, end);
  assert.match(dialog, /mode==="none"\?\[total,0,0,0\]:\[0,0,0,total\]/);
  assert.match(dialog, /\["none","بدون استرداد"/);
  assert.match(dialog, /\["pending","مع استرداد"/);
  assert.doesNotMatch(dialog, /\["credit","رصيد للشخص"|\["custom","تسوية مخصصة"|\["refund","استرداد فعلي"/);
  assert.match(dialog, /refunded:allocation\[1\],credit:allocation\[2\],pending:allocation\[3\]/);
});

test('refund payout stays on canonical financial writer', () => {
  assert.match(source, /disburseRefund\(t,a\)\{return dn\("disburse_refund"/);
  assert.match(source, /function RefundPayoutDialog\(/);
  assert.match(source, /pending_refund_amount/);
});

test('refund payout validates cents, due balance and local disbursement date', () => {
  const start = source.indexOf('function RefundPayoutDialog(');
  const end = source.indexOf('function Kw(', start);
  assert.ok(start >= 0 && end > start);
  const dialog = source.slice(start, end);
  assert.match(dialog, /Number\(amount\)<=due/);
  assert.match(dialog, /date<=\[new Date\(\)\.getFullYear\(\)/);
  assert.match(dialog, /getMonth\(\)\+1/);
  assert.match(dialog, /getDate\(\)/);
  assert.match(dialog, /Me\.disburseRefund\(t,/);
  assert.match(dialog, /method!=="other"\|\|other\.trim\(\)/);
});

test('reservations browser bundle is valid JavaScript after payout dialog insertion', () => {
  assert.doesNotThrow(() => new vm.Script(source, { filename: 'reservations-module.js' }));
});

test("financial summary does not display retired person-credit balance", () => {
  assert.doesNotMatch(source, /\["الأرصدة المستحقة","outstandingCredits"\]/);
});

test('refund review shows ledger even after pending amount reaches zero', () => {
  const start = source.indexOf('function RefundPayoutDialog(');
  const end = source.indexOf('function Kw(', start);
  const dialog = source.slice(start, end);
  const detail = source.slice(end, source.indexOf('function ', end + 10));
  assert.match(dialog, /refundDisbursements/);
  assert.match(dialog, /عمليات الرد السابقة/);
  assert.match(dialog, /d\.date/);
  assert.match(dialog, /due>0&&field\("المبلغ"/);
  assert.match(dialog, /due>0&&l\.jsx\(Se,\{disabled:busy\|\|!valid/);
  assert.match(detail, /Me\.bookingSettlement\(m\.id\)/);
  assert.match(detail, /setRefundSettlement\(settlement\);setRefundDialog\(!0\)/);
  assert.doesNotMatch(detail, /if\(Number\(settlement\.pending_refund_amount/);
});

test('financial report displays scoped dated refund disbursements', () => {
  assert.match(source, /financialSummary\.refundDisbursements/);
  assert.match(source, /سجل رد المبالغ حسب تاريخ الصرف الفعلي/);
  assert.match(source, /d\.date/);
  assert.match(source, /لا توجد عمليات رد مسجلة لهذه الفعالية/);
});
