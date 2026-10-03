'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const test=require('node:test');

const read=file=>fs.readFileSync(file,'utf8');
const integration=read('js/platform-integration.js');
const script=read('script.js');
const cards=read('cards.js');
const accounts=read('js/conference/accounts.js');
const migration=read('supabase/migrations/20261007120000_linked_conference_activity_projection.sql');

function environment(){
  const calls=[],remote='51000000-0000-4000-8000-000000000001';
  const responses={
    get_conference_core:{conferenceId:remote,organizationId:'o',name:'Canonical',place:'Canonical place',startDate:'2026-10-01',endDate:'2026-10-03',status:'active',revision:1,days:3,nights:2,schedule:[]},
    get_conference_branding:{conferenceId:remote,banner:'data:image/jpeg;base64,YQ==',serviceLogo:'',autoColors:false,bannerPosition:'center',cardTheme:'classic',primaryColor:'#111111',secondaryColor:'#222222',textColor:'#333333',revision:1},
    get_conference_accommodation:{conferenceId:remote,houses:[{houseId:'h',name:'H',position:0,revision:1,floors:[{floorId:'f',name:'F',position:0,revision:1,rooms:[{roomId:'included',roomNumber:'1',baseCapacity:2,extraBedCapacity:0,isClosed:false,includedInPricing:true,position:0,revision:1,occupancies:[]},{roomId:'excluded',roomNumber:'2',baseCapacity:2,extraBedCapacity:0,isClosed:false,includedInPricing:false,position:1,revision:1,occupancies:[]}]}]}],pricing:{enabled:true,pricingMode:'per_room_day',prices:{roomDay:10},roomTypePrices:{},revision:1}},
    list_conference_activity:{conferenceId:remote,items:[{eventId:'e',action:'conference.branding.changed',section:'settings',title:'T',createdAt:'2026-10-01'}]}
  };
  const sandbox={window:null,console,Promise,JSON,Object,String,Array,Date,RegExp,Error,Uint8Array,Math,isFinite,crypto:{randomUUID:()=> '51000000-0000-4000-8000-000000000099'},navigator:{onLine:true},appData:{conferences:[{id:'local',conf:{place:'Legacy'},branding:{banner:'legacy'},accommodationDisplayedRoomIds:['excluded'],activityLog:[{title:'legacy'}],peopleDb:{},houses:[]}]},ConferenceLinkStore:{get:()=>({linkStatus:'linked',remoteConferenceId:remote})},PlatformDeviceSession:{invokeModuleProtected(module,operation,args){calls.push({operation,args});if(operation==='mutate_conference_branding')return Promise.resolve(Object.assign({},responses.get_conference_branding,{revision:2}));return Promise.resolve(responses[operation]||responses.get_conference_accommodation)}},addEventListener(){},dispatchEvent(){},CustomEvent:function(){},document:{getElementById(){return null},addEventListener(){}}};
  sandbox.window=sandbox;vm.runInNewContext(integration,sandbox);return {sandbox,calls,remote};
}

test('linked canonical state never projects back into the legacy Conference document',async()=>{
  const env=environment(),api=env.sandbox.PlatformIntegration;
  await api.hydrateConferenceCore('local',env.remote);
  await api.hydrateConferenceBranding('local',env.remote);
  await api.hydrateConferenceAccommodation('local',env.remote);
  await api.hydrateConferenceActivity('local',env.remote);
  const legacy=env.sandbox.appData.conferences[0];
  assert.equal(legacy.conf.place,'Legacy');
  assert.equal(legacy.branding.banner,'legacy');
  assert.equal(api.getConferenceCoreState('local').core.place,'Canonical place');
  assert.equal(api.getConferenceBrandingState('local').branding.banner,'data:image/jpeg;base64,YQ==');
  assert.equal(api.getConferenceAccommodationState('local').houses[0].floors[0].rooms[1].includedInPricing,false);
  assert.equal(api.getConferenceActivityState('local').items[0].title,'T');
  assert.equal(api.prepareLegacyConferenceSerialization,undefined);
});

test('linked Branding and room inclusion mutate only protected canonical operations',async()=>{
  const env=environment(),api=env.sandbox.PlatformIntegration;
  await api.hydrateConferenceBranding('local',env.remote);
  await api.hydrateConferenceAccommodation('local',env.remote);
  await api.mutateConferenceBranding('local','SETTINGS_UPDATE',{autoColors:false,bannerPosition:'center',cardTheme:'classic',primaryColor:'#111111',secondaryColor:'#222222',textColor:'#333333'});
  await api.setConferenceAccommodationRoomInclusion('local','excluded',true);
  assert.ok(env.calls.some(call=>call.operation==='mutate_conference_branding'));
  assert.equal(env.calls.at(-1).operation,'get_conference_accommodation');
  const mutation=env.calls.find(call=>call.operation==='mutate_conference_accommodation_pricing');
  assert.deepEqual(mutation.args.p_payload,{action:'REMOVE_ROOM_EXCLUSION',roomId:'excluded'});
});

test('linked consumers use canonical Branding, inclusion, history, and best-effort output audit',()=>{
  assert.match(cards,/brandingState[\s\S]*copyBranding\(brandingState&&brandingState\.branding\)/);
  assert.match(accounts,/var selectedRooms=linked\?\(context\.rooms\|\|\[\]\)\.filter/);
  assert.doesNotMatch(accounts,/linked\?[^:\n]*accommodationDisplayedRoomIds/);
  assert.match(accounts,/displayed=linked\?room\.includedInPricing!==false/);
  assert.match(script,/var entries=linked\?\(activityState&&activityState\.items\|\|\[\]\)/);
  assert.match(script,/recordConferenceOutputEvent\(current\.id,eventName\)\.catch\(function\(\)\{\}\)/);
  assert.match(migration,/action in\('conference\.core\.updated'[\s\S]*conference\.output\.cards_printed/);
  assert.doesNotMatch(migration,/old_values|new_values[^,)]/);
});

test('linked save paths retain explicit local-only boundaries without old-data migration',()=>{
  assert.doesNotMatch(read('core.js'),/migrateToV3|convertLegacyRoomsToHouses/);
  assert.match(script,/if\(!current\|\|!getCanonicalConferenceCoreLink\(current\.id\)\)addActivityLog\('card_printed'/);
  assert.match(script,/if\(getCanonicalConferenceCoreLink\(conference\.id\)\)return false/);
  assert.doesNotMatch(integration,/projectConferenceCore|legacyCoreCache/);
});
