const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.join(__dirname,'..');
const sql=fs.readFileSync(path.join(root,'supabase/migrations/20261003180000_canonical_conference_accommodation_pricing.sql'),'utf8');
const integration=fs.readFileSync(path.join(root,'js/platform-integration.js'),'utf8');
const core=fs.readFileSync(path.join(root,'core.js'),'utf8');
const script=fs.readFileSync(path.join(root,'script.js'),'utf8');
const edge=fs.readFileSync(path.join(root,'supabase/functions/conference-device-operation/index.ts'),'utf8')+fs.readFileSync(path.join(root,'supabase/functions/platform-device-operation/index.ts'),'utf8');

test('B4A uses normalized Accommodation-owned facts and excludes derived totals and air conditioning',()=>{
  assert.match(sql,/create table public\.conference_accommodation_pricing/);
  for(const fact of ['pricing_mode','person_night','room_night','person_day','room_day','package_price','package_day_price','single_price','double_price','triple_price','quadruple_price','quintuple_price','sextuple_price','seven_plus_price'])assert.match(sql,new RegExp(fact));
  assert.doesNotMatch(sql,/total_amount|calculated_total|air_condition/i);
});

test('B4A read and mutation reuse Accommodation permission and protected dispatcher',()=>{
  assert.match(sql,/conference\.accommodation\.view/);
  assert.match(sql,/conference\.accommodation\.manage/);
  assert.match(sql,/APPROVED_DEVICE_SESSION_REQUIRED/);
  assert.match(sql,/mutate_conference_accommodation_pricing/);
  assert.match(edge,/mutate_conference_accommodation_pricing/);
});

test('B4A has replay, revision, audit and explicit ACL protection',()=>{
  assert.match(sql,/accommodation_pricing_mutation/);
  assert.match(sql,/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
  assert.match(sql,/CONFERENCE_ACCOMMODATION_PRICING_REVISION_CONFLICT/);
  assert.match(sql,/conference\.accommodation\.pricing_updated/);
  assert.match(sql,/force row level security/);
  assert.match(sql,/revoke all on table public\.conference_accommodation_pricing from public,anon,authenticated,service_role/);
  assert.match(sql,/revoke all on function[\s\S]*public\.mutate_conference_accommodation_pricing[\s\S]*from public,anon,authenticated,service_role/);
});

test('linked persistence has no legacy Accommodation serializer while local normalization remains',()=>{
  assert.doesNotMatch(integration,/prepareLegacyConferenceSerialization|delete conference\.accommodationV3/);
  assert.match(core,/state&&state\.pricing\?state\.pricing:createDefaultAccommodationV3\(\)/);
  assert.match(core,/conference\.accommodationV3=normalizeAccommodationV3/);
});

test('linked pricing mutation invokes canonical operation then rehydrates canonical Accommodation',async()=>{
  const calls=[];
  const remote='10000000-0000-4000-8000-000000000001';
  const response={conferenceId:remote,houses:[],pricing:{enabled:true,pricingMode:'per_person_night',prices:{personNight:1,roomNight:2,personDay:3,roomDay:4,packagePrice:5,packageDayPrice:6},roomTypePrices:{single:7,double:8,triple:9,quadruple:10,quintuple:11,sextuple:12,sevenPlus:13},revision:1}};
  const context={window:null,console,Promise,JSON,Object,String,Array,Date,RegExp,Error,Uint8Array,Math,isFinite,navigator:{onLine:true},crypto:{randomUUID:()=> '20000000-0000-4000-8000-000000000001'},appData:{conferences:[{id:'local'}]},ConferenceLinkStore:{get:()=>({linkStatus:'linked',remoteConferenceId:remote})},PlatformDeviceSession:{invokeModuleProtected(module,operation,args){calls.push({module,operation,args:JSON.parse(JSON.stringify(args))});return Promise.resolve(response);}},addEventListener(){},dispatchEvent(){},CustomEvent:function(){},document:{getElementById(){return null;},addEventListener(){}}};context.window=context;
  vm.runInNewContext(integration,context);
  await context.PlatformIntegration.hydrateConferenceAccommodation('local',remote);
  await context.PlatformIntegration.mutateConferenceAccommodationPricing('local',response.pricing);
  assert.equal(calls[1].operation,'mutate_conference_accommodation_pricing');
  assert.equal(calls[1].args.p_expected_revision,1);
  assert.deepEqual(Object.keys(calls[1].args.p_payload).sort(),['enabled','prices','pricingMode','roomTypePrices'].sort());
  assert.equal(calls[2].operation,'get_conference_accommodation');
});

test('active UI cutover calls canonical pricing API without restoring membership authority',()=>{
  assert.match(script,/mutateConferenceAccommodationPricing\(current\.id,plan\)/);
  assert.doesNotMatch(script.slice(script.indexOf('function updateAccommodationV3Setting'),script.indexOf('function renderAccommodationV3Settings')),/conference_members|owner|manager|viewer/);
});
