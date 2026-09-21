const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const migration = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'migrations', '20260922113000_reservations_standalone_zero_state_authorization_reconciliation.sql'),
  'utf8'
);

test('standalone booking creation context uses canonical module authority', () => {
  assert.match(
    migration,
    /require_effective_module_permission\(\s*p_device_id,'reservations','reservations\.booking\.create',null,null\s*\)/
  );
  assert.doesNotMatch(
    migration,
    /v_actor\s*:=\s*public\.require_current_approved_device\(p_device_id\)/
  );
});

test('standalone zero state remains a successful empty JSON array', () => {
  assert.match(migration, /coalesce\(jsonb_agg\(/);
  assert.match(migration, /'\[\]'::jsonb/);
  assert.match(migration, /e\.scope_type='standalone'/);
  assert.match(migration, /e\.conference_id is null/);
  assert.match(migration, /e\.organization_id is null/);
});

test('event visibility remains permission-filtered after initialization authorization', () => {
  assert.match(
    migration,
    /reservations_private\.has_event_permission\(\s*v_actor,'reservations\.booking\.create',e\.id\s*\)/
  );
});

test('conference target still requires active organization membership', () => {
  assert.match(migration, /join public\.organizations o/);
  assert.match(migration, /o\.status='active'/);
  assert.match(migration, /join public\.organization_members om/);
  assert.match(migration, /om\.user_id=v_actor/);
  assert.match(migration, /RESERVATIONS_CONFERENCE_ACCESS_REQUIRED/);
});

test('private helper remains inaccessible to client roles', () => {
  assert.match(
    migration,
    /revoke all on function reservations_private\.booking_creation_context\(uuid,jsonb\)\s*from public,anon,authenticated,service_role;/
  );
  assert.match(
    migration,
    /grant execute on function reservations_private\.booking_creation_context\(uuid,jsonb\)\s*to postgres;/
  );
});
