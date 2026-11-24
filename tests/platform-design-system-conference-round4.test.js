'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const read=file=>fs.readFileSync(file,'utf8');
const index=read('index.html');
const worker=read('service-worker.js');
const tokens=read('shared-design-tokens.css');
const style=read('style.css');
const shell=read('canonical-platform-shell.css');
const script=read('script.js');
const guide=read('docs/platform-design-system.md');

test('design layers have one documented runtime owner and deterministic cache graph',()=>{
  const assets=[
    'shared-design-tokens.css?rev=platform-soft-controls-v5',
    'style.css?rev=conference-accommodation-filter-button-v14',
    'canonical-platform-shell.css?rev=platform-design-cutover-canonical-v2'
  ];
  for(const asset of assets){
    assert.equal(index.split(asset).length-1,1,asset+' must load once');
    assert.equal(worker.split('./'+asset).length-1,1,asset+' must be precached once');
  }
  assert.ok(index.indexOf(assets[0])<index.indexOf(assets[1]));
  assert.ok(index.indexOf(assets[1])<index.indexOf(assets[2]));
  assert.match(guide,/Foundations[\s\S]*Shared components[\s\S]*Platform shell[\s\S]*Page patterns[\s\S]*Module-specific UI/i);
  assert.equal((shell.match(/^\.canonical-platform-shell\{/gm)||[]).length,1);
});

test('foundations centrally own shared controls and semantic states',()=>{
  for(const contract of [/\.card\{/,/\.btn\{/,/input,select,textarea\{/,/\.ui-state\{/,/\.btn:focus-visible/,/\.btn:disabled/])assert.match(tokens,contract);
  assert.doesNotMatch(style,/^\.card\{/m);
  assert.doesNotMatch(style,/^\.btn\{/m);
  assert.doesNotMatch(style,/^input,select,textarea\{/m);
  assert.match(tokens,/@media\(max-width:600px\)/);
  assert.match(tokens,/direction:rtl/);
});

test('Conference cards expose hierarchy, busy state and keyboard activation',()=>{
  const start=script.indexOf('function renderStartupConferenceCards(');
  const end=script.indexOf('\nvar startupDiscoveredOpenBusy',start);
  const renderer=script.slice(start,end);
  assert.match(renderer,/aria-busy="true"/);
  assert.match(renderer,/role="button" tabindex="0"/);
  assert.match(renderer,/event\.key===\\'Enter\\'/);
  assert.match(style,/\.conference-workspace-heading\{/);
  assert.match(style,/\.startup-conference-card:focus-visible/);
  assert.match(style,/@media\(max-width:600px\)[\s\S]*startup-conference/);
});

test('canonical accommodation composes shared states with scoped responsive patterns',()=>{
  const start=script.indexOf('function renderCanonicalAccommodation(');
  const end=script.indexOf('\nfunction deactivateAccommodationRoom',start);
  const renderer=script.slice(start,end);
  for(const marker of ['accommodation-toolbar','accommodation-canonical-summary','accommodation-room-toolbar','accommodation-compact-occupants','ui-state--loading','ui-state--error','ui-state--denied'])assert.match(renderer,new RegExp(marker));
  assert.ok(renderer.indexOf('accommodation-toolbar-search')<renderer.indexOf("h+='</section>'"));
  assert.ok(renderer.indexOf("renderAccommodationQuickFilters('canonical-accommodation-filter-strip')")<renderer.indexOf("h+='</section>'"));
  assert.doesNotMatch(renderer,/style="/);
  assert.match(renderer,/getConferenceOperationalDay\(getCurrentConference\(\)\)/);
  assert.match(renderer,/getCanonicalAccommodationOccupanciesOnDay\(room,operationalDay\)/);
  assert.match(renderer,/room\.isClosed\?'disabled title="الغرفة مغلقة"'/);
  assert.match(style,/#tab0 \.accommodation-toolbar\{/);
  assert.match(style,/\.accommodation-dashboard \.accommodation-room-card\.room-status-closed\{--room-status-color:/);
  for(const breakpoint of ['900','600','420'])assert.match(style,new RegExp('@media\\(max-width:'+breakpoint+'px\\)'));
});

test('Reservations and Warehouse keep module-specific layout ownership',()=>{
  assert.match(index,/modules\/reservations\/reservations-module\.css\?rev=/);
  assert.match(style,/\.warehouse-app\{/);
  assert.match(guide,/Reservations layout[\s\S]*Reservations module stylesheet/);
  assert.match(guide,/Warehouse layout[\s\S]*Warehouse-scoped section/);
});

test('compact room guest actions fit their 90px column',()=>{
  const row=style.match(/#roomModal\.canonical-room-readonly \.guest-person-row\.canonical-room-guest:not\(\.canonical-room-child\)\{([^}]*)\}/);
  const actions=style.match(/#roomModal\.canonical-room-readonly \.guest-person-row\.canonical-room-guest:not\(\.canonical-room-child\)>\.canonical-room-guest-actions\{([^}]*)\}/);
  const icons=style.match(/#roomModal\.canonical-room-readonly \.canonical-room-action\{([^}]*)\}/);
  assert.ok(row&&actions&&icons,'canonical room layout must remain present');
  const column=Number(row[1].match(/\s(\d+)px\s*;/)?.[1]);
  const gap=Number(actions[1].match(/gap:(\d+)px/)?.[1]);
  const width=Number(icons[1].match(/width:(\d+)px/)?.[1]);
  assert.equal(column,90);
  assert.equal(gap,3);
  assert.equal(width,28);
  assert.ok(3*width+2*gap<=column,'arrival, move and remove controls must fit');
});

test('canonical room editor fits guest columns and keeps mobile override',()=>{
  assert.match(style,/#roomModal\.canonical-room-readonly \.room-editor-modal\{width:min\(760px,calc\(100vw - 20px\)\);max-width:760px;/);
  assert.match(style,/@media\(max-width:600px\)\{[\s\S]*?#roomModal\.canonical-room-readonly \.room-editor-modal\{width:100%;max-height:100dvh\}/);
  const row=style.match(/#roomModal\.canonical-room-readonly \.guest-person-row\.canonical-room-guest:not\(\.canonical-room-child\)\{([^}]*)\}/);
  assert.ok(row);
  assert.match(row[1],/grid-template-columns:52px minmax\(150px,180px\) minmax\(0,1fr\) 90px/);
  assert.ok(52+180+90+3*5+2*7<760-2*10,'room controls must leave flexible space for stay fields');
});

test('canonical room action controls occupy one grid row without an implicit extra row',()=>{
  const actions=style.match(/#roomModal\.canonical-room-readonly \.guest-person-row\.canonical-room-guest:not\(\.canonical-room-child\)>\.canonical-room-guest-actions\{([^}]*)\}/);
  assert.ok(actions);
  assert.match(actions[1],/grid-column:4;grid-row:1;/);
  assert.doesNotMatch(actions[1],/grid-row:1\/3/);
});

test('canonical room action spacing has one scoped owner',()=>{
  assert.doesNotMatch(style,/#roomModal\.canonical-room-readonly \.canonical-room-guest-actions\{gap:/);
  assert.match(style,/#roomModal\.canonical-room-readonly \.guest-person-row\.canonical-room-guest:not\(\.canonical-room-child\)>\.canonical-room-guest-actions\{[^}]*gap:3px;/);
});

test('canonical room editor base geometry has a single declaration',()=>{
  const bases=[...style.matchAll(/#roomModal\.canonical-room-readonly \.room-editor-modal\{/g)];
  assert.equal(bases.length,2,'one base rule and one mobile override');
  assert.match(style,/#roomModal\.canonical-room-readonly \.room-editor-modal\{width:min\(760px,calc\(100vw - 20px\)\);max-width:760px;max-height:calc\(100dvh - 20px\);display:flex;/);
});

test('room editor has one closed-state owner and no repeated mobile stay-field reset',()=>{
  assert.equal([...style.matchAll(/#roomModal\.canonical-room-readonly \.room-information-grid>\.room-closed-state\{/g)].length,1);
  assert.equal([...style.matchAll(/#roomModal\.canonical-room-readonly \.guest-person-row\.canonical-room-guest:not\(\.canonical-room-child\)>\.canonical-room-stay-fields\{grid-column:1\/-1;grid-row:auto\}/g)].length,1);
  assert.doesNotMatch(style,/\.guest-slot-label\{flex-basis:64px\}/);
});
