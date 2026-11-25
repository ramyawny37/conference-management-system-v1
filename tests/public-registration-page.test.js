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

test('tracking capability stays in participant link and is required for status',()=>{
  assert.match(js,/searchParams\.set\('track',result\.trackingSecret\)/);
  assert.match(js,/trackingSecret:tracking/);
});

test('tracking page renders only server-projected optional financial and accommodation fields',()=>{
  assert.match(js,/s\.financial/);
  assert.match(js,/s\.accommodation/);
  assert.match(js,/لم يتم تخصيص غرفة بعد/);
});
