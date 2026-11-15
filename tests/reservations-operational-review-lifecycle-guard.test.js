const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const migration = fs.readFileSync(path.join(__dirname, "..", "supabase", "migrations", "20261115190000_reservations_operational_review_active_booking_guard.sql"), "utf8");

test("canonical operational review writer locks booking and rejects non-active lifecycle before mutation", () => {
  const start = migration.indexOf("if p_operation='update_operational_review' then");
  const end = migration.indexOf("if p_operation='reorder_event_periods' then", start);
  assert.ok(start >= 0 && end > start, "canonical writer branch must exist");
  const branch = migration.slice(start, end);
  const lock = branch.indexOf("select * into v_booking from reservations.bookings b");
  const active = branch.indexOf("if v_booking.lifecycle_status<>'active'");
  const update = branch.indexOf("update reservations.operational_reviews");
  assert.ok(lock >= 0 && active > lock && update > active, "lock, guard and mutation must be ordered");
  assert.match(branch, /for update;\s*if not found then raise exception 'RESERVATIONS_BOOKING_NOT_FOUND'/);
  assert.match(branch, /RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE/);
  assert.match(branch, /o\.revision=\(p_args->>'p_expected_revision'\)::bigint/);
});

test("migration replaces the canonical scoped writer, not a parallel endpoint", () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION reservations_private\.mutate_scoped\(/);
  assert.doesNotMatch(migration, /CREATE (?:OR REPLACE )?FUNCTION reservations_private\.update_operational_review/);
});
