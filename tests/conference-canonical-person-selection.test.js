'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../script.js'),'utf8');
test('conference people search retains revision for safe central updates',()=>{
  const start=source.indexOf('function searchCanonicalPersonSuggestions()');
  const end=source.indexOf('function openPersonDialog(',start);
  assert.ok(start>=0&&end>start);
  const search=source.slice(start,end);
  assert.match(search,/canonicalPersonSelectedSnapshot=\{revision:Number\(person\.revision\)/);
  assert.match(search,/canonicalPersonSelectedId=person\.personId/);
});
test('conference canonical update uses expected revision and never silent update',()=>{
  const start=source.indexOf('function saveCanonicalConferenceParticipant(');
  const end=source.indexOf('function saveLocalOnlyPersonDialog(',start);
  assert.ok(start>=0&&end>start);
  const save=source.slice(start,end);
  assert.match(save,/updateConferenceCanonicalPerson\(linkedCurrent\.id,canonicalPersonSelectedId,snapshot\.revision/);
  assert.match(save,/PERSON_REVISION_CONFLICT/);
  assert.match(save,/createConferenceParticipationForExistingPerson\(linkedCurrent\.id,selectedPersonId\)/);
});
