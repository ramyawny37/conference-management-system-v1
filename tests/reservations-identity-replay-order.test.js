const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const initial = fs.readFileSync(path.join(root, 'supabase/migrations/20261104104306_reservations_manual_person_identity_resolution.sql'), 'utf8');
const correction = fs.readFileSync(path.join(root, 'supabase/migrations/20261104122152_reservations_identity_replay_order.sql'), 'utf8');

test('booking replay is moved ahead of identity challenge without introducing another writer', () => {
  assert.match(initial, /RESERVATIONS_PERSON_IDENTITY_RESOLUTION_STALE/);
  assert.match(initial, /v_replay:=reservations_private\.begin_operation\(v_operation_id,v_context,p_operation,p_args\)/);
  assert.match(correction, /pg_get_functiondef\('reservations_private\.mutate_scoped\(uuid,text,jsonb\)'::regprocedure\)/);
  assert.match(correction, /replace\(definition,lock_anchor,replay_clause\|\|lock_anchor\)/);
  assert.match(correction, /replace\(definition,late_anchor,'v_number:=reservations_private\.allocate_booking_number'\)/);
  assert.match(correction, /RESERVATIONS_IDENTITY_REPLAY_CONTRACT_DRIFT/);
  assert.doesNotMatch(correction, /create\s+table|create\s+or\s+replace\s+function\s+reservations_private\.begin_operation/i);
});
