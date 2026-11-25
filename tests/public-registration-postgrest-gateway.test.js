'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const migration=fs.readFileSync('supabase/migrations/20261125140000_public_registration_postgrest_gateway.sql','utf8');
const edge=fs.readFileSync('supabase/functions/public-registration/index.ts','utf8');

test('public registration uses one service-role PostgREST gateway while reservations stays private',()=>{
 assert.match(migration,/create or replace function public\.public_registration_gateway/);
 assert.match(migration,/revoke all on function public\.public_registration_gateway\(text,jsonb\) from public,anon,authenticated/);
 assert.match(migration,/grant execute on function public\.public_registration_gateway\(text,jsonb\) to service_role/);
 assert.match(edge,/service\.rpc\('public_registration_gateway'/);
 assert.doesNotMatch(edge,/schema\('reservations'\)\.rpc/);
});

test('gateway is a strict dispatcher to the existing canonical reservations functions',()=>{
 for(const fn of ['public_registration_read','public_registration_status']){
   assert.match(migration,new RegExp('reservations\\.'+fn+'\\('));
 }
 assert.match(migration,/PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED/);
 assert.doesNotMatch(migration,/insert into reservations\./i);
 assert.doesNotMatch(migration,/update reservations\./i);
 assert.doesNotMatch(migration,/delete from reservations\./i);
});
