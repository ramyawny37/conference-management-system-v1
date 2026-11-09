const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const moduleSource = fs.readFileSync('modules/reservations/reservations-module.js','utf8');
const migration = fs.readFileSync('supabase/migrations/20261109064130_reservations_unified_delete_apology_rebooking_lifecycle.sql','utf8');
const refundReadReportingMigration = fs.readFileSync('supabase/migrations/20261106120000_reservations_refund_disbursement_read_reporting.sql','utf8');

test('delete is an operational lifecycle state and retains financial history', () => {
  assert.match(migration, /lifecycle_status in \('active','apologized','deleted'\)/);
  assert.match(migration, /pending_refund_amount/);
  assert.match(migration, /'حذف من الفعالية'/);
  assert.match(migration, /lifecycle_status='deleted'/);
  assert.doesNotMatch(migration, /delete from reservations\.bookings where id=v_booking\.id/);
});

test('only an active booking blocks registering the same person in the event', () => {
  assert.match(migration, /existing_booking\.lifecycle_status='active'/);
  assert.match(moduleSource, /كان معتذرًا في نفس الفعالية/);
  assert.match(moduleSource, /هل تريد إعادة حجزه في نفس الفعالية؟/);
  assert.match(moduleSource, /existing\?\.booking\.lifecycleStatus===\"active\"/);
});

test('deleted bookings leave operations but remain available to financial reports', () => {
  assert.match(moduleSource, /map\(cg\)\.filter\(s=>s\.booking\.lifecycleStatus!=="deleted"\)/);
  assert.match(moduleSource, /i==="financial"\?allReportRows:allReportRows\.filter\(B=>B\.booking\.lifecycleStatus!=="deleted"\)/);
  assert.match(moduleSource, /deletedReportRows=allReportRows\.filter\(B=>B\.booking\.lifecycleStatus==="deleted"\)/);
  assert.match(moduleSource, /label:"المتحصل من المحذوفين"/);
});

test('delete and apology are separate actions regardless of payments', () => {
  assert.match(moduleSource, /children:\[l\.jsx\(eo,\{\}\),"اعتذار"\]/);
  assert.match(moduleSource, /"حذف من الفعالية"/);
  assert.match(moduleSource, /function CN\(\)\{return\{allowed:!0\}\}/);
});


test('booking form does not route apologized history through the active duplicate modal', () => {
  assert.doesNotMatch(moduleSource, /if\(existing\)\{k\(\{kind:\"duplicate\"/);
  assert.match(moduleSource, /existing\?\.booking\.lifecycleStatus===\"apologized\"/);
});


test('successful booking outcome returns to participants list, not booking detail', () => {
  assert.match(moduleSource, /U=\(\)=>\{k\(null\),Du\("\\\/participants"\)\}/);
  assert.doesNotMatch(moduleSource, /U=\(\)=>\{if\(!o\?\.bookingId\)return;k\(null\),Du\(\x60\\\/participants\/\$\{o\.bookingId\}\x60\)\}/);
});


test('financial report separates booking value from cash and exposes one settlement refund path', () => {
  assert.match(moduleSource, /label:"قيمة الحجوزات الفعالة"/);
  assert.match(moduleSource, /label:"المتحصل من الحجوزات الفعالة"/);
  assert.match(moduleSource, /label:"إجمالي المتحصل"/);
  assert.match(moduleSource, /children:"التسويات المتاحة للرد"/);
  assert.match(moduleSource, /children:"تنفيذ رد"/);
  assert.match(moduleSource, /Me\.disburseRefund/);
});


test('financial settlement summary uses the canonical cash semantics only', () => {
  assert.match(moduleSource, /label:"المرتجعات المنفذة فعليًا"/);
  assert.match(moduleSource, /label:"صافي النقد"/);
  assert.match(moduleSource, /label:"المتاح لاتخاذ قرار رده"/);
  assert.doesNotMatch(moduleSource, /\["إيراد اعتذارات غير مسترد","nonRefundableApologyRevenue"\]/);
  assert.doesNotMatch(moduleSource, /\["المرتجعات المعلقة","pendingRefunds"\]/);
});


test('financial table and CSV never treat inactive booking balance as collectible debt', () => {
  assert.match(moduleSource, /"حالة الحجز"/);
  assert.match(moduleSource, /"المتبقي المطلوب تحصيله"/);
  assert.match(moduleSource, /active\?a\.financial\.remainingBalance:"—"/);
  assert.match(moduleSource, /activeRow\?Ae\(i\.financial\.remainingBalance\):"—"/);
  assert.match(moduleSource, /activeRow\?.*:"تسوية مالية"/s);
});


test('actual refunds and net cash are derived from the refund disbursement ledger', () => {
  assert.match(refundReadReportingMigration, /'actualRefunds',coalesce\(\(select sum\(d\.amount\) from reservations\.refund_disbursements d/);
  assert.match(refundReadReportingMigration, /'netCash'.*select sum\(d\.amount\) from reservations\.refund_disbursements d/s);
  assert.doesNotMatch(refundReadReportingMigration, /'actualRefunds'.*sum\(s\.refunded_amount\)/s);
});


test('shared report aggregation treats remaining balance as collectible only for active bookings', () => {
  assert.match(moduleSource, /remaining:a\.remaining\+\(i\.booking\.lifecycleStatus==="active"\?i\.financial\.remainingBalance:0\)/);
});
