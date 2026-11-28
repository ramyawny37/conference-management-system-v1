const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('event period codes are database-owned and immutable', () => {
  const migration = fs.readFileSync(
    path.join(__dirname, '../supabase/migrations/20261128113000_reservations_canonical_event_period_code_ownership.sql'),
    'utf8',
  );
  assert.match(migration, /next_event_period_kind\(p_event_id uuid\)/);
  assert.match(migration, /for update; if length\(btrim/);
  assert.match(migration, /reservations_private\.next_event_period_kind\(v_event\.id\)/);
  assert.match(migration, /update reservations\.event_periods set label=/);
  assert.doesNotMatch(migration, /update reservations\.event_periods set kind=p_args/);
});

test('period mutation contract no longer accepts client-owned kind', () => {
  const migration = fs.readFileSync(
    path.join(__dirname, '../supabase/migrations/20261128113000_reservations_canonical_event_period_code_ownership.sql'),
    'utf8',
  );
  assert.match(migration, /'p_event_id',''p_label'',''p_starts_on'/);
  assert.match(migration, /'p_expected_revision',''p_label'',''p_starts_on'/);
});
