'use strict';

const assert=require('node:assert');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const vm=require('node:vm');
const {JSDOM}=require('jsdom');

const root=path.join(__dirname,'..');
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const worker=fs.readFileSync(path.join(root,'service-worker.js'),'utf8');
const source=fs.readFileSync(path.join(root,'modules/reservations/reservations-visual-prototype.js'),'utf8');
const css=fs.readFileSync(path.join(root,'modules/reservations/reservations-visual-prototype.css'),'utf8');

function mountPrototype(){
  const dom=new JSDOM('<div id="workspace"></div>',{url:'https://example.test/#/reservations-prototype'});
  let definition=null;
  dom.window.PlatformIntegration={registerModule(value){definition=value;return {id:value.id};}};
  vm.runInContext(source,vm.createContext(dom.window));
  const container=dom.window.document.getElementById('workspace');
  definition.mount({container});
  return {dom,definition,container};
}

test('prototype is an isolated canonical module route with cached assets',()=>{
  assert.match(html,/id="reservations-prototypeWorkspace"/);
  assert.match(html,/modules\/reservations\/reservations-visual-prototype\.css\?rev=reservations-prototype-round3-v1/);
  assert.match(html,/modules\/reservations\/reservations-visual-prototype\.js\?rev=reservations-prototype-round3-v1/);
  assert.match(worker,/modules\/reservations\/reservations-visual-prototype\.css\?rev=reservations-prototype-round3-v1/);
  assert.match(worker,/modules\/reservations\/reservations-visual-prototype\.js\?rev=reservations-prototype-round3-v1/);
  assert.match(source,/id:MODULE_ID/);
  assert.match(source,/MODULE_ID='reservations-prototype'/);
  assert.doesNotMatch(source,/invokeProtected|createClient|fetch\(|XMLHttpRequest|PlatformReservationsRuntime/);
});

test('prototype mounts complete mock reservations surfaces and remains interactive locally',()=>{
  const {dom,definition,container}=mountPrototype();
  assert.ok(container.querySelector('[data-reservations-prototype-root]'));
  assert.strictEqual(container.querySelectorAll('[data-booking-row]').length,6);
  assert.ok(container.querySelector('.rvp-hero'));
  assert.strictEqual(container.querySelectorAll('.rvp-metrics article').length,7);
  assert.strictEqual(container.querySelectorAll('.rvp-actions>button').length,8);
  assert.strictEqual(container.querySelectorAll('.rvp-insights>.rvp-panel').length,5);
  assert.strictEqual(container.querySelectorAll('.rvp-table-tabs>button').length,5);
  assert.ok(container.querySelector('.rvp-quick-search'));
  assert.ok(container.querySelector('.rvp-tools'));
  assert.ok(container.querySelector('.rvp-schedule'));
  assert.ok(container.querySelector('[data-details-overlay]'));
  assert.ok(container.querySelector('[data-form-overlay]'));
  for(const state of ['loading','empty','no-results','error'])assert.ok(container.querySelector(`[data-state-surface="${state}"]`));
  for(const mode of ['validation','saving','success','error'])assert.ok(container.querySelector(`[data-form-state="${mode}"]`));

  container.querySelector('[data-open-details]').click();
  assert.strictEqual(container.querySelector('[data-details-overlay]').hidden,false);
  container.querySelector('[data-close-details]').click();
  assert.strictEqual(container.querySelector('[data-details-overlay]').hidden,true);

  const search=container.querySelector('[data-search]');
  search.value='اسم غير موجود';
  search.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  assert.strictEqual(container.querySelector('[data-reservations-prototype-root]').getAttribute('data-prototype-state'),'no-results');
  container.querySelector('[data-reset-filters]').click();
  assert.strictEqual(container.querySelectorAll('[data-booking-row]').length,6);
  definition.unmount();
  assert.strictEqual(container.innerHTML,'');
});

test('prototype styling is scoped, reusable, responsive, and free of override hacks',()=>{
  assert.match(css,/\[data-reservations-prototype-root\]\{/);
  assert.match(css,/--rvp-primary:#0a6fff/);
  assert.match(css,/--canonical-sidebar-width:288px/);
  assert.match(css,/--canonical-header-height:72px/);
  assert.match(css,/\.canonical-platform-workspace-host\{[^}]*margin-inline-end:336px/);
  assert.match(css,/\.canonical-platform-header\{top:24px;right:336px;left:24px/);
  assert.doesNotMatch(css,/\.canonical-platform-main/);
  assert.match(css,/\.rvp-hero\{min-width:0;min-height:140px/);
  assert.match(css,/\.rvp-hero\{[^}]*grid-template-columns:minmax\(0,30fr\) minmax\(0,39fr\) minmax\(0,31fr\)/);
  assert.match(css,/\.rvp-metrics\{height:104px;[^}]*grid-template-columns:repeat\(7/);
  assert.match(css,/\.rvp-actions\{height:64px;[^}]*grid-template-columns:repeat\(8/);
  assert.match(css,/\.rvp-alerts,\.rvp-ring-panel,\.rvp-chart\{height:240px/);
  assert.match(css,/\.rvp-operations\{height:360px/);
  assert.match(css,/@media\(max-width:1500px\) and \(min-width:1041px\)[\s\S]*\.rvp-insights\{grid-template-columns:minmax\(0,.75fr\) repeat\(3,minmax\(0,1fr\)\) minmax\(0,1.28fr\)/);
  assert.match(css,/@media\(max-width:1040px\)/);
  assert.match(css,/@media\(max-width:820px\)/);
  assert.match(css,/@media\(max-width:520px\)/);
  assert.match(css,/@media\(max-width:820px\)[\s\S]*\.rvp-table-wrap\{display:none\}[\s\S]*\.rvp-mobile-list\{[^}]*display:grid/);
  assert.doesNotMatch(css,/!important/);
  assert.doesNotMatch(css,/platform-shell-v2|#reservationsWorkspace/);
});
