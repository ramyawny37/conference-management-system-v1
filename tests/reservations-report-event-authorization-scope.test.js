'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync(
  'supabase/migrations/20260920120000_reservations_report_event_authorization_scope.sql',
  'utf8'
);
const pagination=fs.readFileSync(
  'supabase/migrations/20260911120000_reservations_scope_partition_integrity.sql',
  'utf8'
);

test('report event resolution authorizes the module-scoped reports grant',()=>{
  assert.match(migration,/p_permission\s*=\s*'reservations\.reports\.view'[\s\S]*require_effective_module_permission\([\s\S]*p_permission\s*,\s*null\s*,\s*null/i);
  assert.match(migration,/else[\s\S]*require_effective_module_permission\([\s\S]*p_permission\s*,\s*'event'\s*,\s*p_event_id::text/i);
});

test('report authorization remains tied to the selected event partition',()=>{
  assert.match(migration,/select \* into v_event from reservations\.events where id=p_event_id/i);
  assert.match(migration,/'scopePartitionId'\s*,\s*v_event\.scope_partition_id/i);
  assert.match(migration,/RESERVATIONS_CONFERENCE_ACCESS_REQUIRED/);
  assert.match(pagination,/p_operation='get_report_booking_page'[\s\S]*b\.event_id=v_event_id[\s\S]*b\.scope_partition_id=v_partition/i);
});

test('report page producer keeps a terminating boolean and final cursor contract',()=>{
  assert.match(pagination,/'hasMore'\s*,\s*coalesce\(v_has_more,false\)/i);
  assert.match(pagination,/'nextCursor'\s*,\s*case when coalesce\(v_has_more,false\)[\s\S]*else null end/i);
});

test('replacement stays private and executable only by postgres',()=>{
  assert.match(migration,/security definer set search_path=''/i);
  assert.match(migration,/revoke all on function reservations_private\.resolve_event_scope\(uuid,uuid,text\)[\s\S]*from public,anon,authenticated,service_role/i);
  assert.match(migration,/grant execute on function reservations_private\.resolve_event_scope\(uuid,uuid,text\)[\s\S]*to postgres/i);
});
