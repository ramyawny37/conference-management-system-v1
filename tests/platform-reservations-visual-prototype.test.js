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
  assert.match(html,/modules\/reservations\/reservations-visual-prototype\.css\?rev=reservations-prototype-fidelity-v2/);
  assert.match(html,/modules\/reservations\/reservations-visual-prototype\.js\?rev=reservations-prototype-fidelity-v2/);
  assert.match(worker,/modules\/reservations\/reservations-visual-prototype\.css\?rev=reservations-prototype-fidelity-v2/);
  assert.match(worker,/modules\/reservations\/reservations-visual-prototype\.js\?rev=reservations-prototype-fidelity-v2/);
  assert.match(source,/id:MODULE_ID/);
  assert.match(source,/MODULE_ID='reservations-prototype'/);
  assert.doesNotMatch(source,/invokeProtected|createClient|fetch\(|XMLHttpRequest|PlatformReservationsRuntime/);
});

test('prototype presentation renders replaceable view-model data and optional details',()=>{
  const {dom,container}=mountPrototype();
  assert.match(source,/var mockViewModel=Object\.freeze/);
  assert.match(source,/shell\(mockViewModel\)/);
  assert.match(source,/metricCards\(viewModel\.metrics\)/);
  assert.ok(dom.window.ReservationsVisualPrototype.mockViewModel);
  assert.strictEqual(dom.window.ReservationsVisualPrototype.mockViewModel.bookings.length,6);
  const secondDetail=container.querySelectorAll('[data-open-details]')[3];
  secondDetail.click();
  assert.strictEqual(container.querySelector('[data-detail-email]').textContent,'—');
  assert.strictEqual(container.querySelector('[data-detail-notes-section]').hidden,true);
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
  assert.match(css,/--canonical-sidebar-width:228px/);
  assert.match(css,/--canonical-header-height:72px/);
  assert.match(css,/\.canonical-platform-workspace-host\{width:calc\(100% - 300px\);max-width:calc\(100% - 300px\);[^}]*margin-right:276px;margin-left:24px/);
  assert.match(css,/\.canonical-platform-workspace,[^}]*#reservations-prototypeWorkspace\{width:100%;max-width:100%;min-width:0\}/);
  assert.match(css,/\.canonical-platform-header\{top:24px;right:276px;left:24px/);
  assert.match(css,/\.rvp-sidebar-brand img\{filter:none;border-radius:50%;background:#fff\}/);
  assert.doesNotMatch(css,/\.canonical-platform-main/);
  assert.match(css,/\.rvp-hero\{min-width:0;min-height:140px/);
  assert.match(css,/\.rvp-hero\{[^}]*grid-template-columns:minmax\(0,30fr\) minmax\(0,39fr\) minmax\(0,31fr\)/);
  assert.match(css,/\.rvp-metrics\{height:66px;[^}]*grid-template-columns:repeat\(7/);
  assert.match(css,/\.rvp-metrics article\{[^}]*gap:5px;padding:5px 6px/);
  assert.match(css,/\.rvp-metric-icon\{width:29px;height:29px/);
  assert.match(css,/\.rvp-actions\{height:44px;[^}]*grid-template-columns:repeat\(8[^}]*padding:4px/);
  assert.match(css,/\.rvp-alerts,\.rvp-ring-panel,\.rvp-chart\{height:166px/);
  assert.match(css,/\.rvp-panel>header\{height:34px/);
  assert.match(css,/\.rvp-ring-layout\{height:94px/);
  assert.match(css,/\.rvp-ring\{width:80px;height:80px/);
  assert.match(css,/\.rvp-bars\{height:94px/);
  assert.match(css,/\.rvp-operations\{display:grid;[^}]*grid-template-areas:"list list list" "side side schedule";align-items:start/);
  assert.match(css,/\.rvp-side-stack\{grid-area:side;[^}]*align-items:start/);
  assert.match(css,/\.rvp-table-wrap td\{height:35px/);
  assert.match(css,/\.rvp-schedule\{grid-area:schedule;align-self:start\}/);
  assert.match(css,/@media\(max-width:1240px\) and \(min-width:1041px\)[\s\S]*\.rvp-metrics\{height:auto;grid-template-columns:repeat\(4,minmax\(0,1fr\)\)\}/);
  assert.match(css,/@media\(max-width:1240px\) and \(min-width:1041px\)[\s\S]*\.rvp-actions\{height:auto;grid-template-columns:repeat\(4,minmax\(0,1fr\)\)\}/);
  assert.match(css,/@media\(max-width:1240px\) and \(min-width:1041px\)[\s\S]*\.rvp-insights\{grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.doesNotMatch(css,/@media\(max-width:1499px\)/);
  assert.doesNotMatch(css,/\.rvp-operations\{height:360px|\.rvp-list-panel\{height:420px|\.rvp-schedule\{grid-area:schedule;height:360px/);
  assert.doesNotMatch(css,/height:clamp\(198px|height:clamp\(300px|--canonical-sidebar-width:288px|right:336px|margin-right:336px/);
  assert.doesNotMatch(css,/Final consolidation|Round 4/);
  assert.match(css,/@media\(max-width:1040px\)/);
  assert.match(css,/@media\(max-width:820px\)/);
  assert.match(css,/@media\(max-width:520px\)/);
  assert.match(css,/@media\(max-width:820px\)[\s\S]*\.rvp-table-wrap\{display:none\}[\s\S]*\.rvp-mobile-list\{[^}]*display:grid/);
  assert.doesNotMatch(css,/!important/);
  assert.doesNotMatch(css,/platform-shell-v2|#reservationsWorkspace/);
});
