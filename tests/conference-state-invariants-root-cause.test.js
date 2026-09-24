'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const vm=require('vm');

const root=path.join(__dirname,'..');
const conferenceId='4c0d6322-7b4d-4f0b-a831-c51e01fa4d79';
const otherId='de32a4ef-2c15-4397-96b1-012f6df3fc46';
const scriptSource=fs.readFileSync(path.join(root,'script.js'),'utf8');
const deleteStart=scriptSource.indexOf('function deleteCurrentConference()');
const deleteEnd=scriptSource.indexOf('function moveTemplateToTrash(',deleteStart);
assert(deleteStart>=0&&deleteEnd>deleteStart);
const deleteSource=scriptSource.slice(deleteStart,deleteEnd);

function record(id){
  return {localConferenceId:id,localLifecycle:'active',
    cloudLifecycle:'cloud_linked',localContentVersion:0,
    localOwnerUserId:null,publishMetadata:null};
}
function clone(value){return JSON.parse(JSON.stringify(value));}

(async function(){
  const links={
    [conferenceId]:{localConferenceId:conferenceId,
      remoteConferenceId:'11111111-1111-4111-8111-111111111111',
      knownRevision:1,linkStatus:'linked'}
  };
  let saved=null,releaseCalls=0;
  const sandbox={window:null,Promise,JSON,Object,Array,String,Number,Date,
    structuredClone:clone,confirm:()=>true,
    appData:{currentConferenceId:conferenceId,
      conferences:[{id:conferenceId,name:'Deleted'},
        {id:otherId,name:'Preserved'}],
      conferenceLifecycle:{schemaVersion:1,records:{
        [conferenceId]:record(conferenceId),[otherId]:record(otherId)
      }},trash:{rooms:[{payload:{conferenceId:conferenceId}},
        {payload:{conferenceId:otherId}}]}},
    SupabaseAuth:{getState:()=>({user:{id:
      '22222222-2222-4222-8222-222222222222'}})},
    getCurrentConference(){return sandbox.appData.conferences.find(
      item=>item.id===sandbox.appData.currentConferenceId)||null;},
    updateCurrentConferenceData(){},showSelectConferenceModal(){},showToast(){},
    save(){
      saved=sandbox.ConferenceActivationAuthorization
        .preparePersistedAppData(sandbox.appData);
      return true;
    },
    ConferenceLinkStore:{
      get(id){return links[id]?clone(links[id]):null;},
      remove(id){delete links[id];return {ok:true,status:'removed'};},
      save(link){links[link.localConferenceId]=clone(link);return {ok:true};}
    },
    ConferenceEditLockManager:{
      endAccommodationEdit(){releaseCalls++;return Promise.resolve({ok:true});}
    }
  };
  sandbox.window=sandbox;
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.join(root,
    'js/storage/conference-repository.js'),'utf8'),sandbox);
  vm.runInContext(fs.readFileSync(path.join(root,
    'js/sync/conference-activation-authorization.js'),'utf8'),sandbox);
  sandbox.ConferenceActivationAuthorization.capturePersistedCandidate(
    conferenceId,'indexeddb'
  );
  vm.runInContext(deleteSource,sandbox);

  assert.strictEqual(sandbox.deleteCurrentConference(),true);
  await Promise.resolve();
  assert.deepStrictEqual(sandbox.appData.conferences.map(item=>item.id),[otherId]);
  assert.strictEqual(
    sandbox.appData.conferenceLifecycle.records[conferenceId],undefined
  );
  assert(sandbox.appData.conferenceLifecycle.records[otherId]);
  assert.strictEqual(sandbox.appData.currentConferenceId,null);
  assert.strictEqual(saved.currentConferenceId,null);
  assert.strictEqual(links[conferenceId],undefined);
  assert.strictEqual(sandbox.appData.trash.rooms.length,1);
  assert.strictEqual(sandbox.appData.trash.rooms[0].payload.conferenceId,otherId);
  assert.strictEqual(releaseCalls,1);
  assert.strictEqual(
    sandbox.ConferenceActivationAuthorization.getPersistedCandidate(),''
  );
  assert.doesNotMatch(deleteSource,/conferences\.splice/,
    'UI deletion must not mutate the conference collection directly');

  console.log('conference state invariant root-cause tests passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
