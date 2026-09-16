'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const vm=require('node:vm');
const {JSDOM}=require('jsdom');

const serviceSource=fs.readFileSync('js/sync/module-permission-administration-service.js','utf8');
const uiSource=fs.readFileSync('js/sync/module-permission-administration-ui.js','utf8');
const migration=fs.readFileSync('supabase/migrations/20260916120000_generic_module_permission_resource_administration.sql','utf8');
const canonicalGrantMigration=fs.readFileSync('supabase/migrations/20260829130000_module_permission_catalog_and_grant_adapter.sql','utf8');
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');

function uiRuntime(scopeMode,grant){
  const dom=new JSDOM('<div id="module_permission_administration_screen"></div>');
  const calls=[];
  const target='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const event='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const api={
    isSupportedModule:(key)=>['warehouse','reservations'].includes(key),
    probeAvailability:(moduleKey)=>Promise.resolve({ok:true,data:{ownerConfirmed:true,catalog:[{permissionKey:moduleKey+'.booking.view',displayName:'View',description:'',allowedScopeMode:scopeMode,allowedResourceType:moduleKey==='warehouse'?'store':'event',sensitiveMutation:false}]}}),
    listResources:(moduleKey,type)=>Promise.resolve({ok:true,data:{resources:[{resourceId:event,resourceType:type,code:type==='store'?'S1':null,name:type==='store'?'المخزن الرئيسي':'فعالية سبتمبر',displayName:type==='store'?'المخزن الرئيسي':'فعالية سبتمبر'}]}}),
    searchCandidates:()=>Promise.resolve({ok:true,data:{candidates:[{userId:target,displayName:'User',email:'user@example.invalid',accountStatus:'approved'}]}}),
    listGrants:()=>Promise.resolve({ok:true,data:{grants:grant?[grant]:[]}}),
    foundationMutation:()=>Promise.resolve({ok:false}),
    catalogMutation:(moduleKey,input)=>{calls.push({moduleKey,input});return Promise.resolve({ok:true});}
  };
  dom.window.ModulePermissionAdministrationService=api;
  dom.window.confirm=()=>true;
  vm.runInContext(uiSource,vm.createContext(dom.window));
  return {ui:dom.window.ModulePermissionAdministrationUI,document:dom.window.document,calls,target,event};
}

async function openReservations(runtime){
  await runtime.ui.initialize();
  await runtime.ui.selectModule('reservations');
  await runtime.ui.search('User');
  await runtime.ui.select(runtime.target);
}

test('backend discovery is protected, catalog-authorized, normalized, and supports store plus event',()=>{
  assert.match(migration,/require_current_approved_device\(p_actor_device_id\)/);
  assert.match(migration,/require_module_permission[\s\S]*'module\.manage'/);
  assert.match(migration,/allowed_resource_type=p_resource_type[\s\S]*allowed_scope_mode in\('resource','both'\)/);
  assert.match(migration,/p_module_key='warehouse' and p_resource_type='store'/);
  assert.match(migration,/p_module_key='reservations' and p_resource_type='event'/);
  assert.match(migration,/'resourceId'[\s\S]*'resourceType'[\s\S]*'displayName'/);
  assert.doesNotMatch(migration,/booking_creation_context/);
  assert.match(edge,/list_module_permission_resources_for_administration/);
});

test('Reservations Event discovery uses canonical event-manage and partition authority',()=>{
  assert.match(migration,/has_event_permission\(\s*actor_id,'reservations\.event\.manage',events\.id\s*\)/);
  assert.match(migration,/events\.scope_type='conference'[\s\S]*public\.conferences[\s\S]*public\.organizations[\s\S]*organizations\.status='active'[\s\S]*public\.organization_members[\s\S]*members\.user_id=actor_id/);
  assert.match(migration,/conferences\.id=events\.conference_id[\s\S]*conferences\.organization_id=events\.organization_id[\s\S]*conferences\.deleted_at is null/);
  assert.match(migration,/events\.scope_type='standalone'[\s\S]*events\.conference_id is null[\s\S]*events\.organization_id is null/);
  assert.doesNotMatch(migration,/booking_creation_context|reservations\.booking\.create/);
});

test('module.manage alone cannot discover an Event resource',()=>{
  const eventBranch=migration.match(/elsif p_module_key='reservations'[\s\S]*?raise exception 'MODULE_PERMISSION_RESOURCE_DISCOVERY_UNSUPPORTED'/)[0];
  assert.match(eventBranch,/has_event_permission[\s\S]*reservations\.event\.manage/);
  assert.doesNotMatch(migration,/create function public\.manage_catalog_module_grant|alter function public\.manage_catalog_module_grant|resolve_event_scope/);
});

test('System Owner and non-owner behavior are delegated to canonical Reservations policy',()=>{
  const canonical=fs.readFileSync('supabase/migrations/20260915220000_reservations_authorization_architecture_reconciliation.sql','utf8');
  assert.match(canonical,/has_event_permission[\s\S]*public\.is_system_owner\(p_actor\)/);
  assert.match(canonical,/resolve_event_scope[\s\S]*require_effective_module_permission[\s\S]*scope_type='conference'[\s\S]*organization_members/);
  assert.match(migration,/has_event_permission\(/);
});

test('Warehouse store discovery retains active-store semantics and no Reservations predicates',()=>{
  const storeBranch=migration.match(/if p_module_key='warehouse'[\s\S]*?elsif p_module_key='reservations'/)[0];
  assert.match(storeBranch,/from warehouse\.stores stores[\s\S]*stores\.status='active'/);
  assert.doesNotMatch(storeBranch,/organization_members|conference_id|has_event_permission/);
});

function canonicalCatalogGrantBody(){
  return canonicalGrantMigration.match(/create function public\.manage_catalog_module_grant\([\s\S]*?\nend;\n\$\$;/)[0];
}

test('event grant uses canonical delegation authority without an invented event-manage precondition',()=>{
  const body=canonicalCatalogGrantBody();
  assert.match(body,/if public\.is_system_owner\(actor_id\)[\s\S]*require_module_permission\(\s*p_actor_device_id, p_module_key, 'module\.manage', null, null/);
  assert.match(body,/validate_module_permission_catalog\(\s*p_module_key, p_permission_key, p_resource_type, p_resource_id/);
  assert.doesNotMatch(body,/reservations\.event\.manage|resolve_event_scope|organization_members|conference_members/);
});

test('event grant outside canonical delegation authority is rejected',()=>{
  const body=canonicalCatalogGrantBody();
  assert.match(body,/require_module_permission\([\s\S]*'module\.manage'/);
  assert.match(body,/authority_grant_id[\s\S]*permission_key = 'module\.manage'[\s\S]*resource_type is null[\s\S]*resource_id is null[\s\S]*revoked_at is null/);
});

test('revoke is grantId-led, exact-resource, and independent of current Event authority',()=>{
  const body=canonicalCatalogGrantBody();
  assert.match(body,/select \* into target_grant[\s\S]*where grants\.grant_id = p_grant_id[\s\S]*for update/);
  assert.match(body,/target_grant\.resource_type is distinct from p_resource_type[\s\S]*target_grant\.resource_id is distinct from p_resource_id[\s\S]*MODULE_GRANT_NOT_FOUND_OR_STALE/);
  assert.doesNotMatch(body,/resolve_event_scope|has_event_permission|organization_members|conference_members/);
});

test('System Owner revoke and recovery policies remain canonical',()=>{
  const body=canonicalCatalogGrantBody();
  const recovery=canonicalGrantMigration.match(/create function public\.recover_revoke_final_module_manager\([\s\S]*?\nend;\n\$\$;/)[0];
  assert.match(body,/authority_source := 'system_owner'/);
  assert.match(body,/if authority_source = 'system_owner'[\s\S]*public\.is_system_owner\(actor_id\)/);
  assert.match(recovery,/if not public\.is_system_owner\(actor_id\)[\s\S]*SYSTEM_OWNER_REQUIRED/);
});

test('module-wide Reservations and Warehouse grant/revoke remain generic and unaffected',()=>{
  const body=canonicalCatalogGrantBody();
  assert.match(body,/p_module_key, p_permission_key, p_resource_type, p_resource_id/);
  assert.match(body,/p_resource_type is null[\s\S]*p_resource_id is null|coalesce\(p_resource_type, '<module>'\)/);
  assert.doesNotMatch(body,/p_module_key\s*=\s*'reservations'|p_module_key\s*=\s*'warehouse'/);
  assert.doesNotMatch(migration,/manage_catalog_module_grant_pre_generic/);
});

test('service discovers normalized generic resources through protected session only',async()=>{
  const calls=[];
  const sandbox={window:{PlatformDeviceSession:{invokeProtected:(operation,args)=>{calls.push({operation,args});return Promise.resolve([{resourceId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',resourceType:'store',code:'S1',name:'Store'}]);}}}};
  vm.runInNewContext(serviceSource,sandbox);
  const response=await sandbox.window.ModulePermissionAdministrationService.listResources('warehouse','store');
  assert.equal(response.ok,true);
  assert.equal(response.data.resources[0].resourceId,'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
  assert.equal(calls[0].operation,'list_module_permission_resources_for_administration');
  assert.equal(calls[0].args.p_module_key,'warehouse');
  assert.equal(calls[0].args.p_resource_type,'store');
  assert.doesNotMatch(serviceSource,/WarehouseTransport|listStores|listEvents/);
});

test('both scope renders module and event grants, sends exact event scope, and resolves history name',async()=>{
  const grant={grantId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',permissionKey:'reservations.booking.view',resourceType:'event',resourceId:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',revokedAt:null,active:true};
  const runtime=uiRuntime('both',grant);
  await openReservations(runtime);
  const html=runtime.ui.renderSection();
  assert.match(html,/data-business-grant/);
  assert.match(html,/فعالية حجز محددة/);
  assert.match(html,/اختر فعالية/);
  assert.match(html,/منح للفعالية/);
  assert.match(html,/فعالية سبتمبر/);
  assert.doesNotMatch(html,/>eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee</);
  const select=runtime.document.querySelector('[data-resource-for="reservations.booking.view"]');
  select.value=runtime.event;
  runtime.document.querySelector('[data-resource-grant]').click();
  await new Promise((resolve)=>setImmediate(resolve));
  assert.equal(runtime.calls[0].input.resourceType,'event');
  assert.equal(runtime.calls[0].input.resourceId,runtime.event);
});

test('resource-only scope suppresses module-wide grant while preserving event selector',async()=>{
  const runtime=uiRuntime('resource',null);
  await openReservations(runtime);
  const html=runtime.ui.renderSection();
  assert.doesNotMatch(html,/data-business-grant/);
  assert.match(html,/data-resource-grant/);
});

test('module-only Reservations permission grants and revokes without resource',async()=>{
  const runtime=uiRuntime('module',null);
  await openReservations(runtime);
  const button=runtime.document.querySelector('[data-business-grant]');
  assert.ok(button);
  assert.equal(runtime.document.querySelector('[data-resource-grant]'),null);
  button.click();
  await new Promise((resolve)=>setImmediate(resolve));
  assert.equal(runtime.calls[0].input.resourceType,null);
  assert.equal(runtime.calls[0].input.resourceId,null);
});

test('Warehouse store-scoped controls remain metadata-driven',async()=>{
  const runtime=uiRuntime('resource',null);
  await runtime.ui.initialize();
  await runtime.ui.search('User');
  await runtime.ui.select(runtime.target);
  const html=runtime.ui.renderSection();
  assert.match(html,/مخزن محدد/);
  assert.match(html,/اختر مخزنًا/);
  assert.match(html,/منح للمخزن/);
});
