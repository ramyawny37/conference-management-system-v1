const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const migration=fs.readFileSync('supabase/migrations/20261027150000_atomic_guardian_child_accommodation.sql','utf8');
const integration=fs.readFileSync('js/platform-integration.js','utf8');
const script=fs.readFileSync('script.js','utf8');

test('guardian-child addition is one canonical leased dispatcher operation',()=>{
  assert.match(integration,/mutateConferenceAccommodationOperation\(localId,'add_guardian_child'/);
  assert.match(integration,/mutate_conference_accommodation_operations/);
  assert.match(integration,/acquireResourceLease\('conference','accommodation_room'/);
  assert.match(migration,/add_conference_guardian_child_accommodation/);
  assert.match(migration,/require_conference_accommodation_context/);
  assert.match(migration,/require_conference_participation_context/);
  assert.match(migration,/platform\.audit_events/);
  assert.match(migration,/ACCOMMODATION_SHARED_CHILD_GUARDIAN_STAY_REQUIRED/);
  assert.match(migration,/add_guardian_child/);
});

test('UI resolves an existing person without client-side participation writes',()=>{
  const body=script.slice(script.indexOf('function ensureCanonicalGuardianChildAccommodation'),script.indexOf('\nfunction saveSeat'));
  assert.match(body,/searchConferencePeople\(current\.id,name,20\)/);
  assert.match(body,/assignConferenceAccommodation/);
  assert.doesNotMatch(body,/createConferenceParticipationWithPerson|setConferenceParticipationGuardian/);
});
