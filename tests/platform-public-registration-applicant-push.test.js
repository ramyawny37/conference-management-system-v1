import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261128170000_public_registration_push_gateway_user_agent_fix.sql',
  'utf8'
);
const sourceMigration = fs.readFileSync(
  'supabase/migrations/20261127170000_public_registration_applicant_push.sql',
  'utf8'
);
const edge = fs.readFileSync('supabase/functions/public-registration/index.ts', 'utf8');

test('applicant push gateway accepts the exact userAgent field sent by the Edge Function', () => {
  assert.match(edge, /p_operation:'upsert_push_subscription',[\s\S]*?userAgent:bounded\(a\.userAgent,512\)/);
  assert.match(sourceMigration, /array\['auth','endpoint','p256dh','publicId','trackingSecretDigest','userAgent'\]/);
  assert.match(migration, /v_old text := 'array\[''auth'',''endpoint'',''p256dh'',''publicId'',''trackingSecretDigest''\]'/);
  assert.match(migration, /v_new text := 'array\[''auth'',''endpoint'',''p256dh'',''publicId'',''trackingSecretDigest'',''userAgent''\]'/);
  assert.match(migration, /PUBLIC_REGISTRATION_PUSH_GATEWAY_USER_AGENT_PATCH_PRECONDITION_FAILED/);
});
