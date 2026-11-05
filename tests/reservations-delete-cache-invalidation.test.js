'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const runtime=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');

test('delete invalidates the canonical booking resource before returning to participants',()=>{
  assert.match(runtime,/await \w+\.deleteBooking\(\w+\),\w+\(\),\w+\("\/participants"\)/);
  assert.equal((runtime.match(/await \w+\.deleteBooking\(\w+\)/g)||[]).length,1);
});
test('resource invalidation clears the cached rows and pending request epoch',()=>{
  assert.match(runtime,/useCallback\(\(\)=>\{\w+\.current\+=1,\w+\.current\.clear\(\),\w+\(\(\)=>\(\{\}\)\)\}/);
  assert.match(runtime,/`\$\{\w+\}:\$\{\w+\}`/);
});
