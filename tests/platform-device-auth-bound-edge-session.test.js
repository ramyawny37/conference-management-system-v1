'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

const root=path.resolve(__dirname,'..');
const sessionSource=fs.readFileSync(
  path.join(root,'js/supabase/device-session.js'),'utf8'
);
const enrollmentSource=fs.readFileSync(
  path.join(root,'js/supabase/device-enrollment.js'),'utf8'
);

test('device session edge calls are bound to the current Supabase auth session',()=>{
  assert.match(sessionSource,/client\.auth\.getSession\(\)/);
  assert.match(sessionSource,/Authorization:'Bearer '\+auth\.token/);
  assert.match(sessionSource,/auth\.userId!==memorySession\.userId/);
  assert.doesNotMatch(
    sessionSource,
    /SupabaseAuth\.initialize\(\)/,
    'device session must not authorize an edge request from cached auth readiness'
  );
});

test('device enrollment uses the current Supabase auth session for identity and transport',()=>{
  assert.match(enrollmentSource,/client\.auth\.getSession\(\)/);
  assert.match(enrollmentSource,/Authorization:'Bearer '\+auth\.token/);
  assert.match(enrollmentSource,/function enroll\(auth\)/);
  assert.match(enrollmentSource,/userId=auth\.userId/);
  assert.doesNotMatch(
    enrollmentSource,
    /SupabaseAuth\.getSession\(\)/,
    'enrollment identity must not come from the cached SupabaseAuth snapshot'
  );
  assert.doesNotMatch(
    enrollmentSource,
    /SupabaseAuth\.initialize\(\)/,
    'enrollment must not authorize an edge request from cached auth readiness'
  );
});
