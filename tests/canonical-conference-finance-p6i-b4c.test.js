const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const root=new URL('../',`file://${__filename}`).pathname;
const sql=fs.readFileSync(root+'supabase/migrations/20261004140000_canonical_conference_finance_foundation.sql','utf8');
const integration=fs.readFileSync(root+'js/platform-integration.js','utf8');
const accounts=fs.readFileSync(root+'js/conference/accounts.js','utf8');
const core=fs.readFileSync(root+'core.js','utf8');
const dispatcher=fs.readFileSync(root+'supabase/functions/platform-device-operation/index.ts','utf8');

test('canonical Finance model is normalized, protected, and reuses the shared replay ledger',()=>{
  for(const table of ['conference_finance_settings','conference_finance_items','conference_finance_adjustments'])assert.match(sql,new RegExp(`create table public\\.${table}`));
  assert.match(sql,/conference\.accounts\.view/);assert.match(sql,/conference\.accounts\.manage/);
  assert.match(sql,/validated_phase1c_device_authorization/);assert.match(sql,/PLATFORM_DEVICE_SESSION_DISPATCH/);
  assert.match(sql,/conference_participation_operations/);assert.match(sql,/finance_mutation/);assert.match(sql,/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
  assert.match(sql,/CONFERENCE_FINANCE_REVISION_CONFLICT/);assert.match(sql,/platform\.audit_events/);
  assert.doesNotMatch(sql,/create table public\.conference_finance_operations/);
  assert.match(sql,/force row level security/);assert.match(sql,/revoke all on table[\s\S]*authenticated,service_role/);
  assert.doesNotMatch(sql,/conference_members|has_conference_role|owner'|manager'|viewer'/);
});

test('Finance owns only independent facts and invoiceComparison is retired',()=>{
  assert.match(sql,/kind in\('EXPENSE','INCOME','SETTLEMENT'\)/);
  assert.match(sql,/type in\('addition','deduction'\)/);
  assert.match(sql,/calculation_method text not null check\(calculation_method in\('fixed','quantity_price','per_day','per_room','per_person','manual'\)\)/);
  assert.doesNotMatch(sql,/invoiceComparison|accommodationDefaults|mealsDefaults|airConditioningDefaults|roomTypePrices|meal_prices/i);
  assert.doesNotMatch(core,/invoiceComparison:/);assert.match(core,/delete financialV3\.invoiceComparison/);
});

test('linked Finance uses dispatcher operations and snapshot serialization has zero Finance authority',async()=>{
  assert.match(dispatcher,/conference\.add\('get_conference_finance'\)/);assert.match(dispatcher,/conference\.add\('mutate_conference_finance'\)/);
  assert.match(integration,/delete conference\.accounts;delete conference\.financialV3/);
  assert.match(integration,/get_conference_finance/);assert.match(integration,/mutate_conference_finance/);
  assert.match(accounts,/if\(getCanonicalConferenceFinance\(conference\)\)/);
  assert.equal((accounts.match(/if\(getCanonicalConferenceFinance\(conference\)\)\{[\s\S]*?return;\n  \}/g)||[]).length>=4,true);
  assert.doesNotMatch(integration,/mutate_conference_finance[\s\S]{0,500}\bsave\(\)/);
});

test('canonical read removes linked legacy state and canonical mutation carries no actor identity',async()=>{
  const calls=[],conference={id:'local',accounts:{financialItems:{items:[]}},financialV3:{adjustments:[]}};
  const response={conferenceId:'remote',settings:{currency:'EGP',rounding_precision:2,expenses_enabled:true,income_enabled:true,settlements_enabled:true,adjustments_enabled:true,revision:1},items:[],adjustments:[]};
  const c={window:null,console,Promise,JSON,Object,String,Array,Date,RegExp,Error,Uint8Array,Math,isFinite,navigator:{onLine:true},crypto:{randomUUID:()=> '20000000-0000-4000-8000-000000000001'},appData:{conferences:[conference]},ConferenceLinkStore:{get:()=>({linkStatus:'linked',remoteConferenceId:'remote'})},PlatformDeviceSession:{invokeModuleProtected(module,operation,args){calls.push({module,operation,args});return Promise.resolve(response)}},addEventListener(){},dispatchEvent(){},CustomEvent:function(){},document:{getElementById(){return null},addEventListener(){}}};c.window=c;
  vm.runInNewContext(integration,c);await c.CanonicalConferenceFinance.hydrate('local','remote');
  assert.equal('accounts' in conference,false);assert.equal('financialV3' in conference,false);
  await c.CanonicalConferenceFinance.mutate('local','EXPENSE','UPSERT','30000000-0000-4000-8000-000000000001',{});
  assert.deepEqual(calls.map(x=>x.operation),['get_conference_finance','mutate_conference_finance']);
  assert.equal(Object.keys(calls[1].args).some(key=>/actor|user|device/.test(key)),false);
});

test('source migration preserves stable IDs and active legacy facts without canonicalizing invoiceComparison',()=>{
  assert.match(sql,/conference_snapshots s/);assert.match(sql,/accounts,financialItems,items/);assert.match(sql,/accounts,incomeItems,items/);assert.match(sql,/accounts,settlements,items/);assert.match(sql,/financialV3,adjustments/);
  assert.doesNotMatch(sql,/invoiceComparison/);
});
