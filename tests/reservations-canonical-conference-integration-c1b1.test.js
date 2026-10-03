const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

const migration=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261008120000_reservations_canonical_conference_integration.sql'),'utf8');

test('Reservations creates canonical participation and keeps only integration identity',()=>{
  assert.match(migration,/truncate table reservations\.conference_person_links/i);
  assert.match(migration,/conference_participation_id/i);
  assert.match(migration,/link_booking_to_canonical_participation/i);
  assert.match(migration,/public\.create_conference_participation_with_person/i);
  assert.doesNotMatch(migration,/jsonb_set\s*\([^;]*peopleDb|room\.guests|room\.children/i);
});

test('Reservations accommodation reads canonical occupancy immediately',()=>{
  assert.match(migration,/conference_accommodation_occupancies/i);
  assert.match(migration,/conference_accommodation_rooms/i);
  assert.match(migration,/conference_accommodation_floors/i);
  assert.match(migration,/conference_accommodation_houses/i);
  assert.match(migration,/return reservations_private\.get_booking_accommodation_canonical\(v_booking_id\)/i);
});

test('migration rejects residual active snapshot and sync projection functions',()=>{
  assert.match(migration,/P6I_C1B1_RESERVATIONS_SNAPSHOT_FUNCTION_REMAINS/);
  assert.match(migration,/P6I_C1B1_RESERVATIONS_SYNC_PROJECTION_REMAINS/);
  assert.doesNotMatch(migration,/insert into public\.sync_operations/i);
});

test('legacy projection, self-heal, fallback and historical backfill are retired',()=>{
  assert.match(migration,/drop function reservations_private\.project_booking_to_conference\(/i);
  assert.match(migration,/P6I_C1B1_HISTORICAL_BOOKING_BACKFILL_REMAINS/);
  const linkBody=migration.slice(migration.indexOf('create or replace function reservations_private.link_standalone_event_to_conference'),migration.indexOf('create function reservations_private.get_booking_accommodation_canonical'));
  assert.doesNotMatch(linkBody,/project_booking_to_conference|link_booking_to_canonical_participation|for\s+v_booking/i);
  assert.doesNotMatch(migration,/coalesce\([^;]*conference_snapshots|fallback/i);
});
