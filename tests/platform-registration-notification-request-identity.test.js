const fs=require('node:fs');
const assert=require('node:assert');
const migration=fs.readFileSync('supabase/migrations/20261126190000_platform_registration_notification_request_identity.sql','utf8');
const integration=fs.readFileSync('js/platform-integration.js','utf8');

assert.match(migration,/new\.id::text,'event',new\.event_id::text/);
assert.match(migration,/registration-requests\?eventId='\|\|new\.event_id::text\|\|'&requestId='\|\|new\.id::text/);
assert.match(migration,/update platform\.notification_events e[\s\S]*e\.resource_id=r\.request_reference/);
assert.match(migration,/update platform\.notification_outbox o[\s\S]*o\.resource_id=r\.request_reference/);
assert.doesNotMatch(migration,/\?tab=registration/);
assert.doesNotMatch(migration,/registration-requests\?eventId='\|\|new\.event_id::text\s*,/);
assert.match(integration,/function routePathname\(route\)\{return String\(route\|\|''\)\.split\('\?'\)\[0\];\}/);
assert.match(integration,/pathname===target\|\|pathname\.indexOf\(target\+'\/'\)===0/);
console.log('platform registration notification request identity: PASS');
