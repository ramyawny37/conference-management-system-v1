'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const migration=fs.readFileSync('supabase/migrations/20261128173500_public_registration_adult_phone_contract.sql','utf8');
const initialSubmit=fs.readFileSync('supabase/migrations/20261128174500_public_registration_initial_adult_phone_validation.sql','utf8');
const publicPage=fs.readFileSync('public-registration.js','utf8');

test('paid adult family members require an independent personal phone before booking creation',()=>{
 assert.match(migration,/PUBLIC_REGISTRATION_ADULT_PHONE_REQUIRED/);
 assert.match(initialSubmit,/PUBLIC_REGISTRATION_ADULT_PHONE_REQUIRED/);
 assert.match(publicPage,/m\.role==='adult'/);
 assert.match(publicPage,/رقم هاتف البالغ المشترك مطلوب/);
 assert.match(migration,/PUBLIC_REGISTRATION_ADULT_PHONE_MUST_BE_INDEPENDENT/);
 assert.match(migration,/public_registration_request_members_adult_phone_check/);
 assert.match(migration,/char_length\(phone\) between 7 and 20/);
});

test('paid children may use guardian phone only when their own phone is absent',()=>{
 assert.match(migration,/m\.role='child_paid'/);
 assert.match(migration,/coalesce\(nullif\(btrim\(m\.phone\),''\),v_guardian_phone\)/);
 assert.match(migration,/PUBLIC_REGISTRATION_GUARDIAN_PHONE_REQUIRED/);
});

test('member phone correction uses the audited canonical device operation',()=>{
 assert.match(migration,/update_public_registration_member_profile/);
 assert.match(migration,/p_phone/);
 assert.match(migration,/PUBLIC_REGISTRATION_PHONE_DISPATCH_ANCHOR_MISMATCH/);
 assert.match(migration,/p_phone/);
 assert.match(migration,/phone=v_phone/);
 assert.match(migration,/PUBLIC_REGISTRATION_ADULT_PHONE_REQUIRED/);
});
