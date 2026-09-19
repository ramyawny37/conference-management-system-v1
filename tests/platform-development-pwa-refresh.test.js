'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const worker=fs.readFileSync('service-worker.js','utf8');
const pwa=fs.readFileSync('pwa.js','utf8');

test('updates wait for explicit acceptance in Development and Production',()=>{
  assert.doesNotMatch(worker,/\.then\(\(\) => self\.skipWaiting\(\)\)/);
  assert.match(worker,/if \(event\.data\.action === 'skipWaiting'\)/);
});

test('the explicit update path prompts, activates, and reloads once',()=>{
  assert.match(pwa,/getActionableWaitingWorker\(registration\)/);
  assert.match(pwa,/waitingWorker\.postMessage\(\{ action: 'skipWaiting' \}\)/);
  assert.match(pwa,/addEventListener\('controllerchange'[\s\S]*reloadTriggered = true[\s\S]*window\.location\.reload\(\)/);
  assert.strictEqual((pwa.match(/window\.location\.reload\(\)/g)||[]).length,1);
});

test('first install can activate normally without a forced reload',()=>{
  assert.match(worker,/\.then\(\(\) => self\.clients\.claim\(\)\)/);
  assert.match(pwa,/return controller && worker && worker\.state === 'installed' \? worker : null/);
  assert.match(pwa,/if \(!updateInProgress \|\| reloadTriggered\) return/);
});

test('only the current registration waiting worker owns actionable update UI',()=>{
  assert.doesNotMatch(pwa,/registration\.waiting \|\| newWorker/);
  assert.match(pwa,/worker === getActionableWaitingWorker\(serviceWorkerRegistration\)/);
  assert.match(pwa,/waitingWorker !== displayedUpdateWorker/);
  assert.match(pwa,/observedUpdateWorkers\.has\(worker\)/);
});

test('Development non-navigation assets are network-first with cache fallback',()=>{
  assert.match(worker,/function developmentNetworkFirst\(request\)/);
  assert.match(worker,/fetch\(new Request\(request,\{cache:'no-store'\}\)\)/);
  assert.match(worker,/cache\.put\(request,responseToCache\)/);
  assert.match(worker,/catch\(\(\) => caches\.open\(CACHE_NAME\)\.then\(cache => cache\.match\(request\)\)\)/);
  assert.match(worker,/if \(IS_DEVELOPMENT\) \{\s*event\.respondWith\(developmentNetworkFirst\(request\)\);\s*return;\s*\}/);
});

test('Production retains the existing cache-first fallback path',()=>{
  assert.match(worker,/caches\.open\(CACHE_NAME\)\.then\(cache => \{\s*return cache\.match\(request\)\.then\(response => \{\s*return response \|\| fetch\(request\);/);
});
