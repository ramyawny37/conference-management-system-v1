const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
test('period save reads canonical event detail, verifies persistence, and refreshes pricing state',()=>{const s=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');const start=s.indexOf('function TN('),end=s.indexOf('const RN=',start);assert.ok(start>=0&&end>start);const editor=s.slice(start,end);assert.match(editor,/await Me\.getEventDetail\(a\)/);assert.doesNotMatch(editor,/await Me\.getEvent\(a\)/);assert.match(editor,/PERIOD_SAVE_READBACK_MISMATCH/);assert.match(editor,/await refreshEvent\?\.\(\)/);assert.match(s,/eventEndDate:de\.endDate,onSaved:I/);});

test('period reordering follows the edited draft order rather than server response order',()=>{const source=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');const start=source.indexOf('function TN('),end=source.indexOf('const RN=',start);const editor=source.slice(start,end);assert.match(editor,/const orderedIds=V\.map\(F=>q\.periods\.find\(se=>se\.kind===F\.kind\)\?\.id\)/);assert.match(editor,/orderedIds\.some\(F=>!F\)/);assert.match(editor,/orderedIds\.some\(\(F,se\)=>F!==q\.periods\[se\]\?\.id\)/);assert.match(editor,/reorderPeriods\(a,orderedIds\)/);assert.doesNotMatch(editor,/reorderPeriods\(a,q\.periods\.map\(F=>F\.id\)\)/);});

test('period save readback rejects incorrect persisted order',()=>{const source=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');const editor=source.slice(source.indexOf('function TN('),source.indexOf('const RN='));assert.ok(editor.includes('V.some((F,se)=>J.periods[se]?.kind!==F.kind'));assert.ok(editor.includes('J.periods[se]?.label!==F.label'));assert.ok(editor.includes('J.periods[se]?.from!==F.from'));assert.ok(editor.includes('J.periods[se]?.to!==F.to'));});

test('period editor validates the same 40-character letter-prefixed code as the canonical database',()=>{const s=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');const editor=s.slice(s.indexOf('function TN('),s.indexOf('const RN='));assert.match(editor,/\/\^\[a-z\]\[a-z0-9_-\]\{0,39\}\$\/\.test\(q\.kind\)/);assert.doesNotMatch(editor,/\/\^\[a-z0-9\]\[a-z0-9_-\]\{0,63\}\$/);});

test('new period codes are generated uniquely and remain immutable in the existing editor',()=>{
  const s=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');
  const editor=s.slice(s.indexOf('const _g='),s.indexOf('const RN='));
  assert.match(editor,/const i=new Set\(t\.map\(s=>s\.kind\)\)/);
  assert.match(editor,/while\(i\.has\(`period_\$\{a\}`\)\)a\+\+/);
  assert.match(editor,/kind:`period_\$\{a\}`/);
  assert.match(editor,/onClick:\(\)=>m\(V=>\[\.\.\.V,zN\(V\)\]\)/);
  assert.match(editor,/disabled:!0,value:V\.kind/);
  assert.doesNotMatch(editor,/onChange:\$=>w\(V\.draftKey,\{kind:/);
});

test('event mutations refresh the shared booking creation context without a browser reload',()=>{
  const s=fs.readFileSync(path.join(__dirname,'../modules/reservations/reservations-module.js'),'utf8');
  const editor=s.slice(s.indexOf('function DN('),s.indexOf('function DN(')+6500);
  assert.match(editor,/const \{refreshContext:refreshBookingContext\}=tr\(\)/);
  assert.match(editor,/a\(ye\),await refreshBookingContext\(\),y\(!1\)/);
  assert.match(editor,/a\(ye\.event\),await refreshBookingContext\(\)/);
  assert.match(editor,/onSaved:async\(\)=>\{await I\(\);await refreshBookingContext\(\)\}/);
});
