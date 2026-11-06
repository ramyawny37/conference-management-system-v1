const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const migration = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261106153000_reservations_dashboard_active_lifecycle_alignment.sql"),
  "utf8"
);

test("dashboard operational totals are lifecycle-active and scope predicates are grouped", () => {
  const grouped = /b\.lifecycle_status='active' and \(\(v_event_id is not null and e\.id=v_event_id and e\.scope_partition_id=v_partition\) or \(v_event_id is null and e\.scope_type='conference' and e\.conference_id=v_conference_id\)\)/g;
  assert.equal((migration.match(grouped) || []).length, 2, "bookings and bookingValue must both use grouped active scope");
  assert.match(
    migration,
    /where z\.status='active' and b\.lifecycle_status='active' and \(\(v_event_id is not null and e\.id=v_event_id and e\.scope_partition_id=v_partition\) or \(v_event_id is null and e\.scope_type='conference' and e\.conference_id=v_conference_id\)\)/
  );
});

test("historical report source remains lifecycle-inclusive", () => {
  const reportStart = migration.indexOf("elsif p_operation='get_report_source_data'");
  const pageStart = migration.indexOf("elsif p_operation='get_report_booking_page'");
  assert.ok(reportStart > 0 && pageStart > reportStart);
  const reportBlock = migration.slice(reportStart, pageStart);
  assert.doesNotMatch(reportBlock, /b\.lifecycle_status='active'/);
  assert.match(reportBlock, /'bookings'/);
  assert.match(reportBlock, /'payments'/);
});
