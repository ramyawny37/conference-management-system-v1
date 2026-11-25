import test from 'node:test'; import assert from 'node:assert/strict'; import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/20261125123000_public_registration_channel_settings_admin.sql','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');
test('public registration settings reuse canonical channel with protected optimistic update',()=>{
 assert.match(sql,/reservations\.public_registration_channels/);
 assert.match(sql,/get_public_registration_settings/); assert.match(sql,/update_public_registration_settings/);
 assert.match(sql,/p_expected_revision/); assert.match(sql,/settings_operation_id/); assert.match(sql,/PUBLIC_REGISTRATION_SETTINGS_IDEMPOTENCY_CONFLICT/);
 assert.match(sql,/resolve_event_scope\(p_device_id,p_event_id,'reservations\.booking\.create'\)/);
 assert.match(sql,/revoke all on function reservations_private\.get_public_registration_settings/);
 assert.match(sql,/revoke all on function reservations_private\.update_public_registration_settings/);
 assert.match(edge,/'get_public_registration_settings','update_public_registration_settings'/);
});
