const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('modules/reservations/reservations-module.js', 'utf8');

test('existing-person selection clears stale canonical fields', () => {
  for (const field of ['phone', 'church', 'gender', 'dateOfBirth']) {
    assert.ok(
      source.includes('V("'+field+'",Z.'+field+'??""'),
      'Selected person must overwrite stale '+field+' values, including null'
    );
  }
});

test('selected person age is derived from DOB and cleared when DOB is absent', () => {
  assert.match(source, /V\("age",Z\.dateOfBirth\?String\(/);
  assert.match(source, /\):"",\{shouldValidate:!0\}\)/);
});

test('newborns can be registered with age zero', () => {
  assert.ok(source.includes('.min(0,"السن لا يمكن أن يكون سالبًا")'));
  assert.ok(!source.includes('.min(1,"السن يجب أن يكون أكبر من صفر")'));
});

test('booking creation preserves DOB in the canonical mutation payload', () => {
  assert.ok(source.includes('p_date_of_birth:Z.dateOfBirth'));
});

test('service sector remains a fixed reference list in the booking form', () => {
  assert.ok(source.includes('Bi.map(Z=>'));
});
