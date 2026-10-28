'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const integrationSource=fs.readFileSync('js/platform-integration.js','utf8');
const scriptSource=fs.readFileSync('script.js','utf8');

function functionSource(source,name,nextName){
  const start=source.indexOf('function '+name+'(');
  const end=source.indexOf('\n  function '+nextName+'(',start);
  assert.ok(start>=0&&end>start,name);
  return source.slice(start,end);
}

test('PlatformIntegration exports the canonical family draft function from the frozen API',()=>{
  const exportStart=integrationSource.indexOf('global.PlatformIntegration=Object.freeze({');
  const exported=integrationSource.slice(exportStart,integrationSource.indexOf('\n})(window);',exportStart));
  assert.match(exported,/saveConferenceFamilyAccommodationDraft:saveConferenceFamilyAccommodationDraft/);
  assert.equal((integrationSource.match(/global\.PlatformIntegration=Object\.freeze/g)||[]).length,1);
});

test('family integration locks source and target rooms in stable order and sends one protected request',async()=>{
  const calls=[],released=[];
  const context={
    accommodationRecord:()=>({remoteConferenceId:'conference-1'}),copy:value=>JSON.parse(JSON.stringify(value)),
    getOwnedResourceLease:()=>null,
    getResourceLease:()=>Promise.resolve(null),
    acquireResourceLease:(domain,type,roomId)=>{calls.push(['lease',roomId]);return Promise.resolve({owned:true,leaseToken:'token-'+roomId});},
    releaseResourceLease:(domain,type,roomId)=>{released.push(roomId);return Promise.resolve({status:'released'});},
    platformServices:()=>({invokeProtected:(domain,operation,args)=>{calls.push(['invoke',operation,args]);return Promise.resolve({status:'success'});}}),
    hydrateConferenceAccommodation:()=>Promise.resolve(),hydrateConferenceParticipations:()=>Promise.resolve(),
    operationId:()=>{throw new Error('operationId must be supplied');},Promise,Array,Set,String,JSON
  };
  vm.runInNewContext(functionSource(integrationSource,'saveConferenceFamilyAccommodationDraft','conferenceAccommodationState')+';this.save=saveConferenceFamilyAccommodationDraft;',context);
  await context.save('local',{operationId:'op-1',roomDraft:null,stays:[{operation:'move',sourceRoomId:'room-b',targetRoomId:'room-a',occupancyId:'stay-1',expectedRevision:7}]});
  assert.deepEqual(calls.slice(0,2).map(item=>item[1]),['room-a','room-b']);
  const invoke=calls.find(item=>item[0]==='invoke');
  assert.equal(invoke[1],'save_conference_family_accommodation_draft');
  assert.equal(invoke[2].p_operation_id,'op-1');
  assert.deepEqual(Array.from(invoke[2].p_payload.roomLeaseTokens,token=>token.roomId),['room-a','room-b']);
  assert.deepEqual(released,['room-a','room-b']);
});

test('room editor sends assignments updates replacements and staged children in one family draft',async()=>{
  const submitted=[];
  const context={
    window:{PlatformIntegration:{saveConferenceFamilyAccommodationDraft:(id,draft)=>{submitted.push({id,draft});return Promise.resolve({status:'success'});}}},
    Date,console,Promise,Object
  };
  const start=scriptSource.indexOf('function submitCanonicalAccommodationRoomDraft(');
  const end=scriptSource.indexOf('\nfunction saveCanonicalAccommodationRoomData(',start);
  vm.runInNewContext(scriptSource.slice(start,end)+';this.submit=submitCanonicalAccommodationRoomDraft;',context);
  const children=[{draftId:'child-1',guardianParticipationId:'guardian-1',participationId:null,personId:null,fullName:'طفل',targetRoomId:'room-2',arrivalDay:1,leaveDay:3,bedType:'base'}];
  await context.submit({id:'conference-1'},{operationId:'op-1',roomId:'room-1',revision:3,assignmentRevision:4,children},null,
    [{participationId:'p1',arrivalDay:1,leaveDay:3,bedType:'base',extraBedPersonType:null}],
    [{occupancyId:'o1',expectedRevision:8,arrivalDay:2,leaveDay:4,bedType:'extra',extraBedPersonType:'child'}],
    [{occupancyId:'o2',expectedRevision:9,participationId:'p2',effectiveDay:2,bedType:'base',extraBedPersonType:null}]);
  assert.equal(submitted.length,1);
  assert.deepEqual(Array.from(submitted[0].draft.stays,stay=>stay.operation),['assign','move','replace']);
  assert.equal(submitted[0].draft.stays[1].expectedRevision,8);
  assert.equal(submitted[0].draft.stays[1].sourceRoomId,'room-1');
  assert.equal(submitted[0].draft.stays[1].targetRoomId,'room-1');
  assert.deepEqual(submitted[0].draft.children,children);
});

test('family migration validates room revisions even without a structure change',()=>{
  const migration=fs.readFileSync('supabase/migrations/20261028113000_canonical_family_accommodation_lifecycle_cutover.sql','utf8');
  assert.match(migration,/draft_assignment\.revision<>\(room_draft->>'expectedAssignmentRevision'\)::bigint/);
  assert.match(migration,/draft_room\.revision<>\(room_draft->>'expectedRevision'\)::bigint/);
  assert.match(migration,/require_conference_family_accommodation_leases/);
  assert.match(migration,/conference\.accommodation\.family_draft_saved/);
});

test('new guardian and children remain staged until the single family draft save',()=>{
  assert.match(scriptSource,/function stageCanonicalAccommodationRoomGuardian\(/);
  assert.match(scriptSource,/draft\.guardian=\{draftId:draftId,participationId:null,personId:person\.personId\|\|null/);
  assert.match(scriptSource,/guardianDraftId:slot\.guardianDraftId\|\|null/);
  assert.match(scriptSource,/guardian:draft\.guardian\|\|null,children:draft\.children\|\|\[\]/);
  const migration=fs.readFileSync('supabase/migrations/20261028113000_canonical_family_accommodation_lifecycle_cutover.sql','utf8');
  assert.match(migration,/FAMILY_GUARDIAN_DRAFT_ASSIGNMENT_INVALID/);
  assert.match(migration,/insert into platform\.people\(full_name,phone,church,gender,date_of_birth/);
});
