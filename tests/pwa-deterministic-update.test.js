'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const index=fs.readFileSync('index.html','utf8');
const worker=fs.readFileSync('service-worker.js','utf8');
test('every local JavaScript runtime loaded by index exists and is precached',()=>{
  const scripts=[...index.matchAll(/<script src="([^"?]+)(?:\?[^\"]*)?"><\/script>/g)].map(match=>match[1]).filter(value=>!value.startsWith('http'));
  for(const file of scripts){assert.equal(fs.existsSync(file),true,file);assert.equal(worker.includes(`./${file}`),true,file);}
});
test('service worker has no missing local precache asset',()=>{
  const assets=[...worker.matchAll(/'\.\/([^'?]+)(?:\?[^']*)?'/g)].map(match=>match[1]);
  for(const file of assets)assert.equal(fs.existsSync(file),true,file);
});
test('retired linked snapshot assets are neither loaded nor cached',()=>{
  for(const term of ['snapshot-sync.js','sync-queue.js','sync-processor.js','offline-first-integration.js','conference-realtime-manager.js','automatic-sync-orchestrator.js','conflict-resolution-ui.js','conference-publishing-engine.js'])assert.equal((index+worker).includes(term),false,term);
});
