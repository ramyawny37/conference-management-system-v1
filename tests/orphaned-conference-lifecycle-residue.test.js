'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const vm=require('vm');

const TARGET='de32a4ef-2c15-4397-96b1-012f6df3fc46';
const OTHER='835cb97d-50cd-4bba-8285-1d81dfa8608e';
const SOURCE=fs.readFileSync(path.join(__dirname,'../js/sync/orphaned-conference-cleanup.js'),'utf8');

function clone(value){return JSON.parse(JSON.stringify(value));}
function storage(initial){
  const values=new Map(Object.entries(initial||{}));
  return {
    get length(){return values.size;},
    key(index){return [...values.keys()][index]||null;},
    getItem(name){return values.has(name)?values.get(name):null;},
    setItem(name,value){values.set(name,String(value));},
    removeItem(name){values.delete(name);}
  };
}
function emptyStore(){
  return {openCursor(){
    const request={onsuccess:null,onerror:null,result:null,error:null};
    queueMicrotask(()=>{if(request.onsuccess)request.onsuccess();});
    return request;
  }};
}

(async function(){
  const appData={
    currentConferenceId:OTHER,
    conferences:[{id:OTHER,name:'مدرسه اعداد خدام مجمع'}],
    conferenceLifecycle:{records:{
      [OTHER]:{localLifecycle:'active',cloudLifecycle:'cloud_linked'},
      [TARGET]:{localLifecycle:'active',cloudLifecycle:'cloud_linked'}
    }}
  };
  const localStorage=storage({conf_v5:JSON.stringify(appData)});
  let stopCount=0;
  const sandbox={
    window:null,Promise,JSON,Object,String,Array,Date,console,
    structuredClone:clone,queueMicrotask,
    BrowserStorageNamespace:{environment:'production',key:value=>value},
    localStorage,appData,
    ConferenceLinkStore:{get(){return null;}},
    ConferenceRealtimeManager:{getState(){return null;}},
    AutomaticSyncOrchestrator:{stop(){stopCount++;return {promise:Promise.resolve()};}},
    SupabaseAuth:{getState(){return {authenticated:true};}},
    SupabaseDeviceIdentity:{getCurrent(){return {id:'device'};}},
    AppIndexedDB:{
      getAllRecords(){return Promise.resolve([]);},
      runTransaction(names,mode,executor){
        const stores={};names.forEach(name=>{stores[name]=emptyStore();});
        return Promise.resolve(executor(stores));
      }
    }
  };
  sandbox.window=sandbox;
  vm.createContext(sandbox);
  vm.runInContext(SOURCE,sandbox);

  const inspected=sandbox.OrphanedConferenceCleanup.inspect(TARGET);
  assert.strictEqual(inspected.ok,true);
  assert.strictEqual(inspected.status,'lifecycle_residue_confirmed');

  const result=await sandbox.OrphanedConferenceCleanup.cleanup(TARGET);
  assert.strictEqual(result.ok,true,JSON.stringify(result));
  assert.strictEqual(result.status,'local_orphan_removed');
  assert.strictEqual(stopCount,1);
  assert.strictEqual(sandbox.appData.conferenceLifecycle.records[TARGET],undefined);
  assert(sandbox.appData.conferenceLifecycle.records[OTHER]);
  assert.deepStrictEqual(sandbox.appData.conferences.map(item=>item.id),[OTHER]);

  const persisted=JSON.parse(localStorage.getItem('conf_v5'));
  assert.strictEqual(persisted.conferenceLifecycle.records[TARGET],undefined);
  assert(persisted.conferenceLifecycle.records[OTHER]);
  assert.deepStrictEqual(persisted.conferences.map(item=>item.id),[OTHER]);

  const second=await sandbox.OrphanedConferenceCleanup.cleanup(TARGET);
  assert.strictEqual(second.ok,true);
  assert.strictEqual(second.status,'already_clean');
  assert.strictEqual(stopCount,1);

  const replacementId='4c0d6322-7b4d-4f0b-a831-c51e01fa4d70';
  sandbox.appData={currentConferenceId:null,conferences:[{
    id:OTHER,name:'Preserved after hydration replacement'
  }],conferenceLifecycle:{records:{
    [OTHER]:{localLifecycle:'active',cloudLifecycle:'cloud_linked'},
    [replacementId]:{localLifecycle:'active',cloudLifecycle:'unpublished'}
  }}};
  const replacementInspection=sandbox.OrphanedConferenceCleanup.inspect(
    replacementId
  );
  assert.strictEqual(replacementInspection.status,
    'lifecycle_residue_confirmed',
    'cleanup resolves the current global appData after hydration replacement');

  console.log('orphaned conference lifecycle residue cleanup test passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
