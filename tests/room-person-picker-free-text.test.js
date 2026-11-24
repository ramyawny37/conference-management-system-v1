'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const script=fs.readFileSync('script.js','utf8');
const style=fs.readFileSync('style.css','utf8');
const index=fs.readFileSync('index.html','utf8');

assert.doesNotMatch(script,/function (renderGuestPersonPickerList|openGuestPersonPicker|selectGuestPersonPickerNewName|bindGuestPersonRow)\s*\(/);
assert.doesNotMatch(style,/guest-person-picker/);
assert.doesNotMatch(index,/guestPersonPicker/);
const slotStart=script.indexOf('function renderCanonicalAccommodationRoomSlotCandidates(');
const slotEnd=script.indexOf('\nfunction ',slotStart+10);
assert.ok(slotStart>=0&&slotEnd>slotStart,'canonical room candidate list must exist');
const slot=script.slice(slotStart,slotEnd);
assert.match(slot,/canonical-room-slot-option/);
assert.match(slot,/selectCanonicalAccommodationRoomSlotParticipation/);
assert.match(script,/function openCanonicalAccommodationRoomSlotPersonDialog\(/);
assert.match(script,/accommodationRoomSlotKey/);
console.log('canonical room person picker ownership tests passed');
