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
    "إجمالي الاشتراكات التاريخية",
    "الحجوزات الفعالة",
    "المحصل من الفعالين",
    "المتبقي المطلوب تحصيله",
    "المعتذرون",
    "المحصل من المعتذرين",
    "حجوزات فعالة عليها رصيد",
    "التسويات المالية والاعتذارات",
    "سجل رد المبالغ حسب تاريخ الصرف الفعلي"
  ]) assert.ok(moduleSource.includes(label), label);
  assert.match(moduleSource, /apologyReportRows=.*lifecycleStatus===["']apologized["']/);
  assert.match(moduleSource, /activeReportRows=.*lifecycleStatus!==["']apologized["']/);
});


test("report financial summary passes the icon component type, not a rendered element", () => {
  assert.match(moduleSource, /l\.jsx\(Yd,\{label,value:Ae\(Number\(financialSummary\[key\]\?\?0\)\),detail:["']من التسويات المركزية["'],icon:An\},key\)/);
  assert.doesNotMatch(moduleSource, /financialSummary\[key\][\s\S]{0,180}icon:l\.jsx\(An/);
});

\ntest("attendance, operations, payments, and booking actions require active lifecycle", () => {
  assert.match(moduleSource, /Ao\(a\)\.filter\(N=>N\.booking\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /Ao\(s\)\.filter\(X=>X\.booking\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /Ao\(a\)\.filter\(D=>D\.booking\.lifecycleStatus===["']active["']\)/);
  assert.match(moduleSource, /activeBookings=.*\.filter\(S=>S\.lifecycleStatus===["']active["']\)/);
  assert.doesNotMatch(moduleSource, /lifecycleStatus!==["']apologized["']/);
});
