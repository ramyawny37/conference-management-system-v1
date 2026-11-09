const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const moduleSource = fs.readFileSync(path.join(__dirname, "..", "modules", "reservations", "reservations-module.js"), "utf8");

test("all non-active bookings are excluded from operational payments and attendance", () => {
  assert.match(moduleSource, /Ao\(a\)\.filter\(D=>D\.booking\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /Ao\(a\)\.filter\(N=>N\.booking\.lifecycleStatus===["']active["']\)/);
});

test("dashboard derives operational KPIs and recent bookings from active bookings only", () => {
  assert.match(moduleSource, /activeBookings=.*\.filter\(S=>S\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /bookingCount:activeBookings\.length/);
  assert.match(moduleSource, /bookingValue:activeBookings\.reduce/);
  assert.match(moduleSource, /collected:activeBookings\.reduce/);
});

test("reports preserve historical totals while separating active and apologized finance", () => {
  for (const label of [
    "قيمة الحجوزات الفعالة",
    "المتحصل من الحجوزات الفعالة",
    "المتبقي على الحجوزات الفعالة",
    "المتحصل من المعتذرين",
    "المتحصل من المحذوفين",
    "إجمالي المتحصل",
    "إجمالي قيمة الحجوزات التاريخية",
    "التسويات المالية والاعتذارات",
    "التسويات المتاحة للرد",
    "سجل رد المبالغ حسب تاريخ الصرف الفعلي"
  ]) assert.ok(moduleSource.includes(label), label);
  assert.match(moduleSource, /apologyReportRows=.*lifecycleStatus===["']apologized["']/);
  assert.match(moduleSource, /activeReportRows=.*lifecycleStatus===["']active["']/);
});


test("financial settlement summary uses component references directly", () => {
  assert.match(moduleSource, /label:"إجمالي المتحصل",value:Ae\(Number\(financialSummary\.grossCollected\?\?0\)\),detail:"كل الدفعات الفعلية قبل الرد",icon:An/);
  assert.match(moduleSource, /label:"المرتجعات المنفذة فعليًا",value:Ae\(Number\(financialSummary\.actualRefunds\?\?0\)\),detail:"حسب تاريخ الصرف الفعلي",icon:An/);
  assert.doesNotMatch(moduleSource, /financialSummary\[key\][\s\S]{0,180}icon:l\.jsx\(An/);
});

test("attendance, operations, payments, and booking actions require active lifecycle", () => {
  assert.match(moduleSource, /Ao\(a\)\.filter\(N=>N\.booking\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /Ao\(s\)\.filter\(X=>X\.booking\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /Ao\(a\)\.filter\(D=>D\.booking\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /activeBookings=.*\.filter\(S=>S\.lifecycleStatus===["']active["']\)/);
  assert.doesNotMatch(moduleSource, /lifecycleStatus!==["']apologized["']/);
});

test("report visibility separates participant history, financial history, and active operations", () => {
  assert.match(moduleSource, /i==="financial"\?allReportRows:i==="participants"\?allReportRows\.filter\(B=>B\.booking\.lifecycleStatus!==["']deleted["']\):allReportRows\.filter\(B=>B\.booking\.lifecycleStatus===["']active["']\)/);
});
