const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const sql=fs.readFileSync('supabase/migrations/20261031213000_reservations_dynamic_attendance_periods.sql','utf8');

test('event periods accept event-defined codes instead of the legacy two-value enum',()=>{
  assert.match(sql,/drop constraint if exists reservations_event_periods_kind_check/);
  assert.match(sql,/kind~'\^\[a-z\]\[a-z0-9_-\]\{0,39\}\$'/);
  assert.match(sql,/unique\(event_id,kind\)/);
  const rewritten=sql.slice(sql.indexOf('do $rewrite$'));
  assert.match(rewritten,/RESERVATIONS_PERIOD_MUTATION_SHAPE_CHANGED/);
  assert.match(rewritten,/\!~''\^\[a-z\]/);
});

test('booking types validate their segments against periods owned by the same event',()=>{
  assert.match(sql,/tg_table_name='booking_types'/);
  assert.match(sql,/period\.event_id=v_event_id and period\.kind=requested\.segment/);
  assert.match(sql,/RESERVATIONS_EVENT_PERIOD_REQUIRED/);
  assert.match(sql,/RESERVATIONS_EVENT_PERIOD_IN_USE/);
});

test('booking snapshots remain immutable facts while new writes require configured periods',()=>{
  assert.match(sql,/reservations_booking_dynamic_segments before insert or update/);
  assert.doesNotMatch(sql,/update reservations\.bookings set attendance_segments_snapshot/);
  assert.doesNotMatch(sql,/delete from reservations\.(bookings|payments)/);
});

test('attendance uses the booking snapshot and supports every configured segment code',()=>{
  assert.match(sql,/new\.segment=any\(v_segments\)/);
  assert.match(sql,/v_segments:=array\[new\.segment\]/);
  assert.match(sql,/reservations_attendance_dynamic_segment/);
});
