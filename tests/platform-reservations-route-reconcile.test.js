'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const runtime=fs.readFileSync('modules/reservations/reservations-module.js','utf8');

test('mounted Reservations reconciles the current platform route after listeners attach',()=>{
  assert.match(runtime,/addEventListener\("hashchange",([A-Za-z_$][\w$]*)\),window\.addEventListener\("platform-reservations-route",\1\),\1\(\)/);
  assert.doesNotMatch(runtime,/platform-reservations-route[\s\S]{0,500}setTimeout/);
});
