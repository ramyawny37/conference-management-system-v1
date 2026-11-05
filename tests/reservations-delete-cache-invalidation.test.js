'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const runtime=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');

test('delete invalidates the canonical booking resource before returning to participants',()=>{
  const detail=runtime.slice(runtime.indexOf('function Kw('),runtime.indexOf('function Ln('));
  assert.match(detail,/function Kw\([^]*?\{invalidate:invalidateReservations\}=tr\(\)/);
  assert.match(detail,/await Me\.deleteBooking\(m\),invalidateReservations\(\),Du\("\/participants"\)/);
  assert.equal((detail.match(/await Me\.deleteBooking\(m\)/g)||[]).length,1);
});
test('resource invalidation clears the cached rows and pending request epoch',()=>{
  const provider=runtime.slice(runtime.indexOf('function lN('),runtime.indexOf('function tr('));
  assert.match(provider,/de=x\.useCallback\(\(\)=>\{y\.current\+=1,_\.current\.clear\(\),I\(\(\)=>\(\{\}\)\)\}/);
  assert.match(runtime,/function wo\([^]*?\$l\(\x60\$\{t\}:\$\{d\}\x60,\(\)=>gN\(t,d\),m\)/);
});
