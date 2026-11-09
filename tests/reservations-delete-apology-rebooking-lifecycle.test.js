const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const moduleSource = fs.readFileSync('modules/reservations/reservations-module.js','utf8');
const migration = fs.readFileSync('supabase/migrations/20261109064130_reservations_unified_delete_apology_rebooking_lifecycle.sql','utf8');

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
  assert.match(moduleSource, /هل تريد إنشاء حجز جديد له؟/);
});

test('deleted bookings leave operations but remain available to financial reports', () => {
  assert.match(moduleSource, /map\(cg\)\.filter\(s=>s\.booking\.lifecycleStatus!=="deleted"\)/);
  assert.match(moduleSource, /i==="financial"\?allReportRows:allReportRows\.filter\(B=>B\.booking\.lifecycleStatus!=="deleted"\)/);
  assert.match(moduleSource, /label:"المحذوفون"/);
});

test('delete and apology are separate actions regardless of payments', () => {
  assert.match(moduleSource, /children:\[l\.jsx\(eo,\{\}\),"اعتذار"\]/);
  assert.match(moduleSource, /"حذف من الفعالية"/);
  assert.match(moduleSource, /function CN\(\)\{return\{allowed:!0\}\}/);
});
