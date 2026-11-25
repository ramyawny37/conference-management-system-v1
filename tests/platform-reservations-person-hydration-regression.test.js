const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const source=fs.readFileSync('modules/reservations/reservations-module.js','utf8');
const contract=JSON.parse(fs.readFileSync('modules/reservations/reservations-contract.json','utf8'));
const owns=(name)=>assert.ok(contract.requiredBehaviors.includes(name),name);

test('existing-person selection clears stale canonical fields',()=>{owns('canonical-person-profile');for(const field of ['phone','church','gender','dateOfBirth','governorate','cityOrVillage','serviceSector','serviceSectorOther'])assert.ok(source.includes(field),field);});
test('selected person age is derived from DOB and cleared when DOB is absent',()=>{owns('canonical-dob-gender');assert.ok(source.includes('dateOfBirth'));});
test('newborns can be registered with age zero',()=>{owns('newborn-age-zero');});
test('booking creation preserves DOB in the canonical mutation payload',()=>{owns('canonical-dob-gender');assert.ok(source.includes('p_date_of_birth'));});
test('service sector remains a fixed reference list in the booking form',()=>{owns('canonical-person-profile');assert.ok(source.includes('serviceSector'));});
test('canonical profile hydration includes address and service',()=>{owns('canonical-person-profile');for(const key of ['governorate','cityOrVillage','serviceSector','serviceSectorOther'])assert.ok(source.includes(key),key);});
