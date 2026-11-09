const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('modules/reservations/reservations-module.js', 'utf8');

test('operational procedures include active bookings only', () => {
  assert.match(source, /Ct=x\.useMemo\(\(\)=>Ao\(s\)\.filter\(X=>X\.booking\.lifecycleStatus===["']active["']\),\[s\]\)/);
});

test('apologized participant preview is read-only', () => {
  assert.match(source, /!S&&W\.booking\.lifecycleStatus===["']active["']&&l\.jsx\(Se,\{variant:["']outline["'],size:["']sm["'],onClick:xe/);
  assert.match(source, /W\.booking\.lifecycleStatus===["']active["']&&l\.jsx\(["']div["'],\{className:["']reference-detail-actions["']/);
});

test('participant rows open preview without hijacking nested actions', () => {
  assert.match(source, /tabIndex:0,onClick:Le=>\{Le\.target\.closest\(["']a,button["']\)\|\|\(A\(ae\.booking\.id\),setDetailOpen\(!0\),Re\(\)\)\}/);
  assert.match(source, /onKeyDown:Le=>\{Le\.target===Le\.currentTarget&&\(Le\.key===["']Enter["']\|\|Le\.key===["'] ["']\)/);
});
