'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const vm=require('node:vm');

const source=fs.readFileSync('pwa.js','utf8');

function eventTarget(extra={}) {
  const listeners=new Map();
  return Object.assign(extra,{
    addEventListener(type,listener){
      if(!listeners.has(type)) listeners.set(type,[]);
      listeners.get(type).push(listener);
    },
    emit(type,event={}){
      for(const listener of listeners.get(type)||[]) listener(event);
    },
    listenerCount(type){return (listeners.get(type)||[]).length;}
  });
}

function worker(state='installing') {
  const messages=[];
  return eventTarget({
    state,
    messages,
    postMessage(message,ports){
      messages.push(message);
      if(message.action==='getVersion'&&ports&&ports[0]) {
        ports[0].onmessage({data:{action:'versionInfo',version:'3.6.0'}});
      }
      if(message.action==='getUpdateDiagnostics'&&ports&&ports[0]) {
        ports[0].onmessage({data:{action:'updateDiagnostics',cacheRevision:'test'}});
      }
    }
  });
}

function harness({controller={},waiting=null,installing=null}={}) {
  const classes=new Set();
  const elements={
    'install-app-btn':{style:{},addEventListener(){}},
    'update-now':{textContent:'تحديث الآن',disabled:false,onclick:null},
    'update-message':{textContent:'يوجد تحديث جديد للبرنامج.'},
    'update-bar':{classList:{add:value=>classes.add(value),remove:value=>classes.delete(value),contains:value=>classes.has(value)}},
    'update-later':{onclick:null},
    'pwa-update-diagnostics':{textContent:''}
  };
  const registration=eventTarget({scope:'./',waiting,installing,active:controller});
  registration.update=()=>Promise.resolve();
  const serviceWorker=eventTarget({controller,register:()=>Promise.resolve(registration)});
  const windowTarget=eventTarget({
    APP_SHELL_REVISION:'test',
    matchMedia:()=>({matches:false}),
    location:{reloadCount:0,reload(){this.reloadCount++;}}
  });
  const documentTarget=eventTarget({
    visibilityState:'visible',
    getElementById:id=>elements[id]||null
  });
  const timers=new Map();
  let timerId=0;
  class MessageChannel {
    constructor(){
      this.port1={onmessage:null,close(){}};
      this.port2={onmessage:data=>this.port1.onmessage&&this.port1.onmessage(data)};
    }
  }
  const context={
    console:{log(){}},document:documentTarget,window:windowTarget,
    navigator:{serviceWorker,onLine:true},MessageChannel,Promise,WeakSet,Date,
    setTimeout(callback){const id=++timerId;timers.set(id,callback);return id;},
    clearTimeout(id){timers.delete(id);}
  };
  vm.runInNewContext(source,context,{filename:'pwa.js'});
  return {
    classes,elements,registration,serviceWorker,window:windowTarget,
    async start(){windowTarget.emit('load');await Promise.resolve();await Promise.resolve();},
    async flush(){await Promise.resolve();await Promise.resolve();}
  };
}

test('first install and installing-only workers never expose an actionable update',async()=>{
  const installing=worker('installing');
  const first=harness({controller:null,installing});
  await first.start();
  assert.equal(first.classes.has('show'),false);
  installing.state='installed';
  first.registration.waiting=installing;
  installing.emit('statechange');
  await first.flush();
  assert.equal(first.classes.has('show'),false);

  const updateInstall=worker('installing');
  const controlled=harness({controller:{},installing:updateInstall});
  await controlled.start();
  controlled.registration.emit('updatefound');
  await controlled.flush();
  assert.equal(controlled.classes.has('show'),false);
});

test('a real waiting worker owns the banner and explicit activation exactly once',async()=>{
  const waiting=worker('installed');
  const app=harness({controller:{},waiting});
  await app.start();
  assert.equal(app.classes.has('show'),true);
  app.elements['update-now'].onclick();
  await app.flush();
  assert.equal(waiting.messages.filter(message=>message.action==='skipWaiting').length,1);
  app.registration.waiting=null;
  waiting.state='activating';
  waiting.emit('statechange');
  await app.flush();
  assert.equal(app.classes.has('show'),false);
  app.serviceWorker.emit('controllerchange');
  app.serviceWorker.emit('controllerchange');
  assert.equal(app.window.location.reloadCount,1);
});

test('a disappeared or replaced waiting worker clears stale UI without fake activation',async()=>{
  const original=worker('installed');
  const app=harness({controller:{},waiting:original});
  await app.start();
  assert.equal(app.classes.has('show'),true);
  app.registration.waiting=null;
  original.state='activated';
  original.emit('statechange');
  await app.flush();
  assert.equal(app.classes.has('show'),false);
  app.elements['update-now'].onclick();
  await app.flush();
  assert.equal(original.messages.some(message=>message.action==='skipWaiting'),false);

  const replacement=worker('installed');
  app.registration.waiting=replacement;
  app.registration.emit('updatefound');
  await app.flush();
  assert.equal(app.classes.has('show'),true);
  assert.equal(replacement.listenerCount('statechange'),1);
  app.registration.emit('updatefound');
  await app.flush();
  assert.equal(replacement.listenerCount('statechange'),1);
});

test('each page bootstrap derives banner state only from its current registration',async()=>{
  const staleWorker=worker('activated');
  const app=harness({controller:{},waiting:null,installing:staleWorker});
  await app.start();
  assert.equal(app.classes.has('show'),false);
  assert.equal(app.elements['update-message'].textContent,'يوجد تحديث جديد للبرنامج.');
});
