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
  assert.match(html,/modules\/reservations\/reservations-visual-prototype\.css\?rev=reservations-prototype-v1/);
  assert.match(html,/modules\/reservations\/reservations-visual-prototype\.js\?rev=reservations-prototype-v1/);
  assert.match(worker,/modules\/reservations\/reservations-visual-prototype\.css\?rev=reservations-prototype-v1/);
  assert.match(worker,/modules\/reservations\/reservations-visual-prototype\.js\?rev=reservations-prototype-v1/);
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
  assert.strictEqual(container.querySelectorAll('.rvp-insights>.rvp-panel').length,5);
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
  assert.match(css,/--rvp-primary:#0a6cff/);
  assert.match(css,/\.rvp-hero\{min-height:140px/);
  assert.match(css,/\.rvp-metrics\{[^}]*grid-template-columns:repeat\(7/);
  assert.match(css,/@media\(max-width:1360px\)/);
  assert.match(css,/@media\(max-width:1040px\)/);
  assert.match(css,/@media\(max-width:820px\)/);
  assert.match(css,/@media\(max-width:520px\)/);
  assert.match(css,/@media\(max-width:820px\)[\s\S]*\.rvp-table-wrap\{display:none\}[\s\S]*\.rvp-mobile-list\{display:grid/);
  assert.doesNotMatch(css,/!important/);
  assert.doesNotMatch(css,/platform-shell-v2|#reservationsWorkspace/);
});
