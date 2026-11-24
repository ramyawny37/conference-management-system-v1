'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const script=fs.readFileSync('script.js','utf8');
const style=fs.readFileSync('style.css','utf8');
const index=fs.readFileSync('index.html','utf8');

for(const name of ['openRoomEditor','renderRoomEditorFromDraft','applyEditorFormToDraftRoom','openMoveGuestDialog','openMoveRoomDialog','saveRoomData']){
  assert.doesNotMatch(script,new RegExp('function\\s+'+name+'\\s*\\('),name+' must remain retired');
}
assert.match(script,/function openCanonicalAccommodationRoomDetails\(/);
assert.match(script,/function saveCanonicalAccommodationRoomData\(/);
assert.match(script,/canonical-room-candidate-filters/);
assert.match(script,/canonical-room-slot-candidates/);
assert.match(style,/@media\(max-width:600px\)/);
assert.match(style,/#roomModal\.canonical-room-readonly \.canonical-room-slot-candidates/);
assert.match(style,/#roomModal\.canonical-room-readonly \.guest-person-row\.canonical-room-guest/);
assert.doesNotMatch(style,/guest-person-picker-popover|partialTransferModal/);
assert.doesNotMatch(index,/partialTransferModal|onclick="addCI\(\)"/);
assert.match(index,/width=device-width,initial-scale=1\.0/);
assert.doesNotMatch(index,/user-scalable\s*=\s*no|maximum-scale\s*=\s*1/i);
console.log('canonical room mobile input UX boundary tests passed');
