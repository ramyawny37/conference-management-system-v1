const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('outer period dispatcher migration matches inner canonical argument lists', () => {
 const migration = fs.readFileSync(path.join(__dirname, '../supabase/migrations/20261102140000_reservations_event_period_dispatch_contract_alignment.sql'), 'utf8');
 const labels = fs.readFileSync(path.join(__dirname, '../supabase/migrations/20261101010000_reservations_event_period_labels.sql'), 'utf8');
 const create = "array[''p_operation_id'',''p_event_id'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']";
 const update = "array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']";
 assert.ok(migration.includes(create));
 assert.ok(migration.includes(update));
 assert.ok(labels.includes(create));
 assert.ok(labels.includes(update));
 assert.match(migration, /RESERVATIONS_PERIOD_OUTER_DISPATCH_SHAPE_CHANGED/);
});
