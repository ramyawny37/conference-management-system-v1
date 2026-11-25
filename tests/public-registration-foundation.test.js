'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync(
  'supabase/migrations/20261125090000_public_registration_foundation.sql',
  'utf8'
);
const contract=fs.readFileSync(
  'docs/contracts/public-registration-canonical-contract.md',
  'utf8'
);

test('public registration foundation stays event-scoped and canonical',()=>{
  assert.match(migration,/create table reservations\.public_registration_channels/);
  assert.match(migration,/event_id uuid not null references reservations\.events\(id\) on delete restrict/);
  assert.match(migration,/foreign key\(event_id,booking_type_id\)[\s\S]*references reservations\.booking_types\(event_id,id\)/);
  assert.match(migration,/resolved_person_id uuid references platform\.people\(id\)/);
  assert.match(migration,/booking_id uuid references reservations\.bookings\(id\)/);
  assert.doesNotMatch(migration,/create table .*people/i);
  assert.doesNotMatch(migration,/create table .*bookings/i);
});

test('tracking stores only a digest and submission replay has a stable identity',()=>{
  assert.match(migration,/tracking_secret_digest bytea not null[\s\S]*octet_length\(tracking_secret_digest\)=32/);
  assert.match(migration,/submit_operation_id uuid not null/);
  assert.match(migration,/unique\(channel_id,submit_operation_id\)/);
  assert.doesNotMatch(migration,/tracking_secret\s+text/i);
});

test('request states cannot claim approval without canonical person and booking',()=>{
  assert.match(migration,/state text not null default 'submitted'/);
  assert.match(migration,/state='approved'[\s\S]*resolved_person_id is not null and booking_id is not null/);
  assert.match(migration,/state in\('rejected','waitlisted'\)[\s\S]*booking_id is null/);
  assert.match(migration,/unique\(booking_id\)/);
});

test('foundation is fail-closed to browser and service roles',()=>{
  for(const table of ['public_registration_channels','public_registration_requests']){
    assert.match(migration,new RegExp(`alter table reservations\\.${table} enable row level security`));
    assert.match(migration,new RegExp(`alter table reservations\\.${table} force row level security`));
    assert.match(migration,new RegExp(`revoke all on reservations\\.${table}\\s+from public,anon,authenticated,service_role`));
  }
  assert.doesNotMatch(migration,/grant\s+(select|insert|update|delete|all).*anon/i);
  assert.doesNotMatch(migration,/create\s+(or\s+replace\s+)?function/i);
});

test('contract reuses existing event capacity instead of inventing another owner',()=>{
  assert.match(contract,/reservations\.events\.capacity/);
  assert.doesNotMatch(migration,/\bcapacity\s+(integer|bigint|numeric)/i);
});
