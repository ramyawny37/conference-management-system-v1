import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const sql = fs.readFileSync("supabase/migrations/20261128134453_canonical_family_booking_read_model.sql", "utf8");

test("family approval is dependency-safe", () => {
  assert.match(sql, /case role when ''adult'' then 0 when ''child_paid'' then 1 when ''child_dependent'' then 2/);
});

test("booking read model exposes family root, guardian and dependent children without creating bookings", () => {
  assert.match(sql, /booking_family_context/);
  assert.match(sql, /'rootBookingId',root\.booking_id/);
  assert.match(sql, /'guardianBookingId',g\.booking_id/);
  assert.match(sql, /c\.role='child_dependent'/);
  assert.match(sql, /booking_family_context\(b\.id\) family_context/);
});
