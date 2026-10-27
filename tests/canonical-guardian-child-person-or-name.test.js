const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const script=fs.readFileSync('script.js','utf8');
const migration=fs.readFileSync('supabase/migrations/20261027150000_atomic_guardian_child_accommodation.sql','utf8');
test('existing child sends person ID without name, new child sends name without person ID',()=>{
 const body=script.slice(script.indexOf('function ensureCanonicalGuardianChildAccommodation('),script.indexOf('function saveSeat('));
 assert.match(body,/childPersonId:matches\.length\?matches\[0\]\.personId:\(exact\.length\?exact\[0\]\.personId:null\)/);
 assert.match(body,/childFullName:matches\.length\|\|exact\.length\?null:name/);
 assert.match(migration,/ACCOMMODATION_CHILD_PERSON_OR_NAME_REQUIRED/);
});
