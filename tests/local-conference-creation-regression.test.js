const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'..','script.js'),'utf8');
const start=source.indexOf('var conferenceCanonicalCreatePending=null;');
const end=source.indexOf('function collectConferenceSelection()',start);
assert.ok(start>=0&&end>start,'canonical create implementation must exist');
const creationSource=source.slice(start,end);
assert.doesNotMatch(creationSource,/addLocalConference|organization_id|p_organization_id|cfg_organization/);
function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};}
function setup(options={}){
 const fields={cfg_name:{value:'اختبار مركزي'},cfg_start:{value:'2026-10-10'},cfg_end:{value:'2026-10-12'},cfg_days:{value:'3'},cfg_place:{value:''},nc_save_btn:{disabled:false}};
 const calls=[],messages=[],records=[],gate=options.gate||null;
 let nextId=0,closed=0,opened=0;
 const sandbox={Promise,Error,parseInt,console,conferenceDialogMode:'create',
  ge:id=>fields[id]||null,calculateConferencePeriod:()=>({valid:true,days:3,nights:2}),
  buildConferenceSchedule:()=>[],showToast:message=>messages.push(message),
  alert:message=>messages.push(message),closeNewConferenceModal:()=>{closed++;},
  showStartupConferenceList:()=>{},openDiscoveredConferenceFromStartup:id=>{opened++;return Promise.resolve(options.openResult===undefined?{ok:true}:options.openResult);},
  crypto:{randomUUID:()=>('00000000-0000-4000-8000-'+String(++nextId).padStart(12,'0'))},
  PlatformDeviceSession:{invokeModuleProtected:(module,operation,payload)=>{
   calls.push({module,operation,payload});
   return gate?gate.promise:Promise.resolve(options.createResult===undefined?{status:'created',conferenceId:payload.p_requested_conference_id,operationId:payload.p_operation_id}:options.createResult);
  }},
  StartupConferenceDiscovery:{refresh:()=>options.refreshResult===undefined?Promise.resolve({ok:true}):Promise.resolve(options.refreshResult),
   getRecords:()=>options.recordsMissing?[]:[{id:calls[0]?.payload.p_requested_conference_id}]}
 };
 sandbox.window=sandbox;
 vm.runInNewContext(creationSource,sandbox,{filename:'canonical-create.js'});
 return {sandbox,fields,calls,messages,get closed(){return closed;},get opened(){return opened;}};
}
async function run(){
 const ok=setup();
 const result=await ok.sandbox.createConferenceFromSelection();
 assert.equal(result.ok,true);
 assert.equal(ok.calls.length,1);
 assert.equal(ok.calls[0].module,'conference');
 assert.equal(ok.calls[0].operation,'create_canonical_conference');
 assert.deepEqual(Object.keys(ok.calls[0].payload).sort(),['p_end_date','p_name','p_operation_id','p_requested_conference_id','p_start_date'].sort());
 assert.equal(ok.opened,1);
 assert.equal(ok.closed,1);
 assert.ok(ok.messages.includes('تم إنشاء المؤتمر وفتحه بنجاح'));
 const missing=setup();missing.fields.cfg_name.value='';
 assert.equal(missing.sandbox.createConferenceFromSelection(),false);
 assert.equal(missing.calls.length,0);
 const denied=setup({createResult:{ok:false}});
 assert.equal(await denied.sandbox.createConferenceFromSelection(),false);
 assert.equal(denied.opened,0);
 const notListed=setup({recordsMissing:true});
 assert.equal(await notListed.sandbox.createConferenceFromSelection(),false);
 assert.equal(notListed.opened,0);
 const openFailed=setup({openResult:{ok:false}});
 assert.equal(await openFailed.sandbox.createConferenceFromSelection(),false);
 assert.ok(openFailed.messages.some(x=>x.includes('تعذر فتحه')));
 const gate=deferred(),pending=setup({gate});
 const first=pending.sandbox.createConferenceFromSelection();
 const second=pending.sandbox.createConferenceFromSelection();
 assert.equal(first,second);
 assert.equal(pending.calls.length,1);
 gate.resolve({status:'created',conferenceId:pending.calls[0].payload.p_requested_conference_id,operationId:pending.calls[0].payload.p_operation_id});await first;
 assert.equal(pending.calls.length,1);
 const retryGate=deferred(),retry=setup({gate:retryGate});
 const attempt=retry.sandbox.createConferenceFromSelection();
 const original=retry.calls[0].payload.p_operation_id;
 retryGate.reject(new Error('offline'));await attempt;
 retry.sandbox.PlatformDeviceSession.invokeModuleProtected=(m,o,p)=>{retry.calls.push({module:m,operation:o,payload:p});return Promise.resolve({status:'duplicate',conferenceId:p.p_requested_conference_id,operationId:p.p_operation_id});};
 await retry.sandbox.createConferenceFromSelection();
 assert.equal(retry.calls[1].payload.p_operation_id,original);
 console.log('canonical conference creation regression tests: passed');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
