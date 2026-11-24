'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const {JSDOM}=require('jsdom');

const read=file=>fs.readFileSync(file,'utf8');
const tokens=read('shared-design-tokens.css');
const style=read('style.css');
const shell=read('canonical-platform-shell.css');
const reservations=read('modules/reservations/reservations-module.css');
const index=read('index.html');
const worker=read('service-worker.js');
const reference=read('design-system-reference.html');

test('canonical tokens own visual decisions without Conference compatibility aliases',()=>{
  assert.doesNotMatch(style,/:root\s*\{[\s\S]{0,9000}--app-primary:/);
  for(const token of ['--platform-primary','--platform-success-soft','--platform-font-size-body','--platform-motion-fast','--platform-compact-font-size-body'])assert.match(tokens,new RegExp(token.replaceAll('-','\\-')+'\\s*:'));
  for(const legacyPrefix of ['--app-','--ds-','--acc-']){
    assert.doesNotMatch(tokens,new RegExp(legacyPrefix));
    assert.doesNotMatch(style,new RegExp(legacyPrefix));
    assert.doesNotMatch(shell,new RegExp(legacyPrefix));
    assert.doesNotMatch(reservations,new RegExp(legacyPrefix));
  }
  const compactValues={
    '--platform-compact-touch-target':'40px',
    '--platform-compact-font-size-xs':'8px',
    '--platform-compact-font-size-sm':'10px',
    '--platform-compact-font-size-body':'12px',
    '--platform-compact-font-size-heading':'16px',
    '--platform-compact-font-weight-bold':'800'
  };
  for(const [name,value] of Object.entries(compactValues))assert.match(tokens,new RegExp(name+'\\s*:\\s*'+value+'\\s*;'));
  const v2Definitions=[...tokens.matchAll(/(--platform-v2-[\w-]+)\s*:\s*([^;]+)/g)];
  assert.deepEqual(v2Definitions.map(match=>match[1]),['--platform-v2-border','--platform-v2-navy','--platform-v2-text']);
  for(const match of v2Definitions)assert.match(match[2],/^var\(--platform-/);
  assert.doesNotMatch(tokens,/--platform-v2-(?:primary|success|warning|danger|purple|cyan|radius|shadow|sidebar)/);
});

test('every shared component family has one central contract',()=>{
  const contracts=['ui-icon-button','ui-field','ui-choice','ui-search','ui-toolbar','ui-kpi','ui-table','ui-pagination','ui-filter','ui-tab','ui-badge','ui-dialog','ui-feedback','ui-toast','ui-skeleton','ui-state'];
  for(const name of contracts){
    assert.match(tokens,new RegExp('\\.'+name+'(?:[-_{:.]|\\b)'));
    assert.doesNotMatch(style,new RegExp('^\\.'+name+'(?:[-_{:.]|\\b)','m'));
    assert.doesNotMatch(shell,new RegExp('^\\.'+name+'(?:[-_{:.]|\\b)','m'));
    assert.doesNotMatch(reservations,new RegExp('^\\.'+name+'(?:[-_{:.]|\\b)','m'));
  }
  assert.match(tokens,/@media\(prefers-reduced-motion:reduce\)/);
  assert.match(tokens,/@media\(max-width:600px\)[\s\S]*\.ui-toolbar/);
});

test('Conference consumes central button card and dialog foundations without base competitors',()=>{
  assert.match(tokens,/\.ui-dialog-backdrop,\.overlay\{/);
  assert.match(tokens,/\.ui-dialog,\.modal\{width:100%;background:var\(--platform-surface\);border:1px solid var\(--platform-border\);border-radius:var\(--platform-radius-lg\);box-shadow:var\(--platform-shadow-dialog\)\}/);
  assert.doesNotMatch(style,/\.app-modal \.modal\{[^}]*\b(?:border|border-radius|box-shadow):/);
  assert.doesNotMatch(tokens,/\.modal\{max-width:[^}]*\b(?:border-radius|box-shadow):/);
  assert.doesNotMatch(style,/^\.overlay\{/m);
  assert.doesNotMatch(style,/^\.modal\{/m);
  assert.doesNotMatch(style,/\.transport-toolbar \.btn,\.transport-empty-state \.btn\{[^}]*display:/);
  assert.doesNotMatch(style,/\.transport-toolbar \.btn,\.transport-empty-state \.btn\{[^}]*border-radius:/);
  assert.doesNotMatch(style,/\.reports-v3-actions \.btn\{[^}]*display:/);
  assert.doesNotMatch(style,/\.reports-v3-actions \.btn\{[^}]*border-radius:/);
  assert.doesNotMatch(style,/\.settings-accounts-panel \.card\{[^}]*background:/);
  assert.doesNotMatch(style,/\.settings-accounts-panel \.card\{[^}]*border:/);
  assert.doesNotMatch(style,/\.accommodation-canonical-summary>\.card\{[^}]*box-shadow:/);
  assert.doesNotMatch(style,/--room-modal-/);
  assert.match(style,/\.transport-toolbar \.btn,\.transport-empty-state \.btn\{[^}]*min-height:var\(--platform-compact-touch-target\)/);
  assert.match(style,/\.settings-accounts-panel \.card\{[^}]*border-radius:var\(--platform-radius-md\)/);
});

test('Development reference uses real components without app routing, data, or scripts',()=>{
  const dom=new JSDOM(reference,{url:'https://development.invalid/design-system-reference.html'});
  const document=dom.window.document;
  assert.equal(document.documentElement.dir,'rtl');
  assert.equal(document.querySelectorAll('script').length,0);
  assert.equal(document.querySelectorAll('.canonical-platform-shell').length,0);
  assert.equal(document.querySelectorAll('[data-platform-module]').length,0);
  assert.equal(document.querySelectorAll('.btn').length>=7,true);
  assert.equal(document.querySelectorAll('.ui-state').length,4);
  assert.equal(document.querySelectorAll('[role="alert"]').length>=3,true);
  const disabled=document.querySelector('button:disabled');
  let clicks=0;disabled.addEventListener('click',()=>{clicks++});disabled.click();
  assert.equal(clicks,0,'native disabled behavior must remain intact');
  const primary=document.querySelector('.btn-blue');primary.focus();
  assert.equal(document.activeElement,primary,'shared action must remain keyboard focusable');
  assert.doesNotMatch(reference,/style="|onclick=|fetch\(|supabase|PlatformDeviceSession/);
  assert.match(worker,/\.\/design-system-reference\.html/);
  assert.doesNotMatch(index,/design-system-reference\.html/);
});

test('runtime CSS load order and cache revisions remain atomic',()=>{
  const shared='shared-design-tokens.css?rev=platform-soft-controls-v5';
  const pages='style.css?rev=conference-report-subcard-base-v17';
  const canonical='canonical-platform-shell.css?rev=platform-design-cutover-canonical-v2';
  assert.ok(index.indexOf(shared)<index.indexOf(pages));
  assert.ok(index.indexOf(pages)<index.indexOf(canonical));
  for(const asset of [shared,pages,canonical])assert.equal(worker.split('./'+asset).length-1,1);
  assert.match(worker,/development-reservations-lifecycle-active-only-v4-design-foundation-v1/);
});

test('proven duplicate global definitions were actually removed',()=>{
  assert.equal((style.match(/^\.body\{/gm)||[]).length,1);
  assert.equal((tokens.match(/^\.toast,/gm)||[]).length,1);
  assert.equal((style.match(/^\.toast(?:[.{])/gm)||[]).length,0);
  assert.equal((style.match(/--app-primary\s*:/g)||[]).length,0);
});

test('specialized Conference dialog shells inherit central chrome',()=>{
  for(const match of style.matchAll(/([^{}]+)\{([^{}]*)\}/g)){
    if(/(?:\.modal|\.room-editor-modal|\.transport-(?:editor|seat|bulk)-modal)$/.test(match[1].trim()))assert.doesNotMatch(match[2],/\b(?:border|border-radius|background|box-shadow):/,match[1]);
  }
});

test('room row and footer buttons inherit central control radius',()=>{
  for(const match of style.matchAll(/#roomModal \.(?:guest-person-row|room-modal-footer) \.btn\{([^{}]*)\}/g))assert.doesNotMatch(match[1],/border-radius:/);
});

test('retired child section title button chrome does not return',()=>{
  assert.doesNotMatch(style,/#roomModal \.room-children-section \.room-modal-section-title>\.btn/);
});

test('report actions use shared soft button chrome',()=>{
  assert.match(tokens,/\.btn\.btn-soft\{/);
  assert.doesNotMatch(style,/\.reports-v3-actions \.btn(?:-green|-blue|-purple|:hover)\{/);
});

test('house library action buttons inherit central radius',()=>{
  const rules=[...style.matchAll(/([^{}]+)\{([^{}]*)\}/g)].filter(m=>m[1].includes('.settings-library-section .house-')&&m[1].includes('.btn'));
  assert.ok(rules.length>0);
  for(const rule of rules)assert.doesNotMatch(rule[2],/border-radius:/);
});
