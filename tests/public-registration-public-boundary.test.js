'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const migration=fs.readFileSync('supabase/migrations/20261125093000_public_registration_public_boundary.sql','utf8');
const edge=fs.readFileSync('supabase/functions/public-registration/index.ts','utf8');
const config=fs.readFileSync('supabase/config.toml','utf8');

test('public boundary exposes only narrow service-role RPCs while tables stay closed',()=>{
 for(const fn of ['public_registration_read','public_registration_status']){
  assert.match(migration,new RegExp(`grant execute on function reservations\\.${fn}[^;]+to service_role`));
  assert.match(migration,new RegExp(`revoke all on function reservations\\.${fn}[^;]+from public,anon,authenticated`));
 }
 assert.match(migration,/force row level security/);
 assert.doesNotMatch(migration,/grant\s+(select|insert|update|delete|all).*anon/i);
});

test('public read is allowlisted and never exposes person candidates',()=>{
 assert.match(migration,/'name',v_event\.name,'startDate',v_event\.start_date,'endDate',v_event\.end_date,'location',v_event\.location/);
 assert.match(migration,/where bt\.event_id=v_event\.id and bt\.active/);
 assert.doesNotMatch(migration,/platform\.people.*jsonb_build_object/i);
});

test('submit is approval-only, event scoped, rate limited and idempotent',()=>{
 assert.match(migration,/v_channel\.registration_mode<>'approval_required'/);
 assert.match(migration,/bt\.id=p_booking_type_id and bt\.event_id=v_event\.id and bt\.active/);
 assert.match(migration,/public_registration_rate_limit\(v_channel\.id,p_fingerprint_digest,8\)/);
 assert.match(migration,/pg_advisory_xact_lock/);
 assert.match(migration,/PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT/);
 assert.doesNotMatch(migration,/insert into reservations\.bookings/i);
 assert.doesNotMatch(migration,/insert into platform\.people/i);
});

test('tracking secret is deterministic at edge but only digest crosses into storage',()=>{
 assert.match(edge,/tracking:'\+publicId\+':'\+operationId/);
 assert.match(edge,/trackingSecret=b64url\(trackingBytes\)/);
 assert.match(edge,/p_tracking_secret_digest:hex\(await hmac\(secret,'track:'\+trackingSecret\)\)/);
 assert.doesNotMatch(migration,/tracking_secret\s+text/i);
});

test('edge is anonymous-jwt but origin restricted and operation allowlisted',()=>{
 assert.match(config,/\[functions\.public-registration\][\s\S]*verify_jwt = false/);
 assert.match(edge,/const operations=new Set\(\['event','submit_family','status'\]\)/);\n assert.doesNotMatch(edge,/operation==='submit'/);
 assert.match(edge,/request\.headers\.get\('Origin'\)!==ORIGIN/);
 assert.doesNotMatch(edge,/Authorization/);
});
