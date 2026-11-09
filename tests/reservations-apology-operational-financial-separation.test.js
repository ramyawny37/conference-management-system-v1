const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const moduleSource = fs.readFileSync(path.join(__dirname, "..", "modules", "reservations", "reservations-module.js"), "utf8");

test("apologized bookings are excluded from operational payments and attendance", () => {
  assert.match(moduleSource, /Ao\(a\)\.filter\(D=>D\.booking\.lifecycleStatus!==["']apologized["']\)/);
  assert.match(moduleSource, /Ao\(a\)\.filter\(N=>N\.booking\.lifecycleStatus!==["']apologized["']\)/);
});

test("dashboard derives operational KPIs and recent bookings from active bookings only", () => {
  assert.match(moduleSource, /activeBookings=.*\.filter\(S=>S\.lifecycleStatus!==["']apologized["']\)/);
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

test("non-refundable apology funds are never exposed as refundable or offered for payout", () => {
  assert.match(moduleSource, /Number\(financialSummary\.pendingRefunds\?\?0\)/);
  assert.doesNotMatch(moduleSource, /Number\(financialSummary\.pendingRefunds\?\?0\)\+Number\(financialSummary\.retainedApologyFunds\?\?0\)/);
  assert.match(moduleSource, /Number\(row\.pending\?\?0\)>0/);
  assert.doesNotMatch(moduleSource, /Number\(row\.refundableAvailable\?\?0\)>0/);
});
