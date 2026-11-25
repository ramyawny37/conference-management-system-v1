'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const html=fs.readFileSync('public-registration.html','utf8');
const js=fs.readFileSync('public-registration.js','utf8');

test('public page is isolated from authenticated platform shell',()=>{
  assert.match(html,/public-registration\.js/);
  assert.doesNotMatch(html,/script\.js|reservations-module\.js|device-session/);
});

test('public page uses the one family-capable submission route',()=>{
  assert.match(js,/call\('event'/);
  assert.match(js,/call\('submit_family'/);
  assert.match(js,/call\('status'/);
  assert.doesNotMatch(js,/call\('submit'/);
  assert.match(js,/SUPABASE_RUNTIME_CONFIG/);
  assert.match(js,/\/functions\/v1\/public-registration/);
  assert.doesNotMatch(js,/\.from\(|reservations\.bookings|platform\.people/);
});

test('family UX is progressive and every child selects a preceding guardian',()=>{
  assert.match(js,/\+ إضافة فرد من العائلة/);
  assert.match(js,/child_paid/);
  assert.match(js,/child_dependent/);
  assert.match(js,/guardians=members\.slice\(0,i\)/);
  assert.match(js,/data-f="guardianMemberKey"/);
  assert.match(js,/m\.role\.indexOf\('child_'\)===0&&!m\.guardianMemberKey/);
});

test('family summary uses canonical event booking type prices and dependent children are free',()=>{
  assert.match(js,/function familySummary\(\)/);
  assert.match(js,/eventData\.bookingTypes/);
  assert.match(js,/t&&t\.price/);
  assert.match(js,/طفل مرافق — بدون تكلفة مستقلة/);
  assert.match(js,/الإجمالي/);
});

test('public share URL stays stable while tracking is kept locally and recovery remains available',()=>{
  assert.doesNotMatch(js,/searchParams\\.set\\('track'/);
  assert.match(js,/localStorage\.setItem\(trackingKey\(\),value\)/);
  assert.match(js,/trackingSecret:tracking/);
  assert.match(js,/call\('recover'/);
});

test('child inheritance synchronizes the current guardian form values before copying shared context',()=>{
  assert.match(js,/function syncMemberCard\(card\)/);
  assert.match(js,/guardianCard=document\.querySelector/);
  assert.match(js,/if\(guardianCard\)syncMemberCard\(guardianCard\)/);
  assert.match(js,/\['church','governorate','cityOrVillage','serviceSector','serviceSectorOther'\]/);
});

test('device-local tracking keeps multiple request capabilities without storing registration PII',()=>{\n  assert.match(js,/public-registration-history:/);\n  assert.match(js,/history\.unshift\(\{reference:reference,trackingSecret:value\}\)/);\n  assert.match(js,/history\.slice\(0,8\)/);\n  assert.match(js,/data-saved-request/);\n  assert.doesNotMatch(js,/history\.unshift\(\{[^}]*phone|history\.unshift\(\{[^}]*dateOfBirth|history\.unshift\(\{[^}]*fullName/);\n});\n\ntest('tracking page renders only server-projected optional financial and accommodation fields',()=>{
  assert.match(js,/s\.financial/);
  assert.match(js,/s\.accommodation/);
  assert.match(js,/لم يتم تخصيص غرفة بعد/);
});
