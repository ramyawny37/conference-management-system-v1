'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const sql=fs.readFileSync('supabase/migrations/20261125100000_public_registration_admin_review.sql','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');

test('admin review is device-dispatched and reuses booking-create event permission',()=>{
 assert.match(edge,/list_public_registration_requests','get_public_registration_request/);
 assert.match(sql,/resolve_event_scope\(p_device_id,p_event_id,'reservations\.booking\.create'\)/);
 assert.match(sql,/resolve_event_scope\(p_device_id,r\.event_id,'reservations\.booking\.create'\)/);
 assert.match(sql,/v_session\.device_id/);
});
test('request review exposes candidates only through protected admin function',()=>{
 assert.match(sql,/from platform\.people p/);
 assert.match(sql,/'hasEventBooking',exists/);
 assert.match(sql,/revoke all on function reservations_private\.get_public_registration_request[^;]+from public,anon,authenticated,service_role/);
 assert.doesNotMatch(fs.readFileSync('supabase/functions/public-registration/index.ts','utf8'),/identityCandidates|platform\.people/);
});
test('PR3 remains read-only and cannot approve or create canonical records',()=>{
 assert.doesNotMatch(sql,/insert into reservations\.bookings/i);
 assert.doesNotMatch(sql,/insert into platform\.people/i);
 assert.doesNotMatch(sql,/update reservations\.public_registration_requests/i);
 assert.doesNotMatch(sql,/delete from reservations\.public_registration_requests/i);
});
test('admin list is event scoped and bounded',()=>{
 assert.match(sql,/where event_id=p_event_id and \(p_state is null or state=p_state\)/);
 assert.match(sql,/v_limit<1 or v_limit>500/);
});
