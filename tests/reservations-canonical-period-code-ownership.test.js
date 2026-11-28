const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
  path.join(__dirname, '../supabase/migrations/20261128113000_reservations_canonical_event_period_code_ownership.sql'),
  'utf8',
);

test('event period codes are database-owned, serialized, and immutable', () => {
  assert.match(migration, /pg_catalog\.regexp_match\(existing\.kind,''\^period_\(\[0-9\]\+\)\$''\)/);
  assert.match(migration, /for update; if length\(btrim/);
  assert.match(migration, /values\(v_event\.scope_partition_id,v_event\.id,\(select ''period_''\|\|/);
  assert.match(migration, /update reservations\.event_periods set label=/);
  assert.doesNotMatch(migration, /create or replace function reservations_private\.next_event_period_kind/i);
  assert.doesNotMatch(migration, /update reservations\.event_periods set kind=p_args/);
});

test('period mutation contract no longer accepts client-owned kind', () => {
  assert.match(migration, /''p_event_id'',''p_label'',''p_starts_on'/);
  assert.match(migration, /''p_expected_revision'',''p_label'',''p_starts_on'/);
  assert.doesNotMatch(migration, /''p_event_id'',''p_kind'',''p_label''/);
  assert.doesNotMatch(migration, /''p_expected_revision'',''p_kind'',''p_label''/);
});
