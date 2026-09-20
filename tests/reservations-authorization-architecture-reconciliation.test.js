const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');

const migration=fs.readFileSync(
  'supabase/migrations/20260915220000_reservations_authorization_architecture_reconciliation.sql','utf8'
);
const edge=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');
const bundleSource=fs.readFileSync(
  '../reservation-management-system/src/features/reservations/components/new-booking-form.tsx','utf8'
);
const runtimeSource=fs.readFileSync(
  '../reservation-management-system/src/features/reservations/reservations-runtime.tsx','utf8'
);
const moduleRootSource=fs.readFileSync(
  '../reservation-management-system/src/features/reservations/components/module-root.tsx','utf8'
);
function body(name){
  const match=migration.match(new RegExp(`function ${name.replaceAll('.','\\.')}[\\s\\S]*?\\$\\$;`,'i'));
  assert.ok(match,`missing ${name}`);
  return match[0];
}

test('catalog adds event.create and enables only Event-bound capabilities for Event resources',()=>{
  assert.match(migration,/'reservations\.event\.create'[\s\S]*'active','module',null,true/);
  assert.match(migration,/allowed_scope_mode='both',allowed_resource_type='event'/);
  assert.match(migration,/'reservations\.booking\.create'/);
  assert.doesNotMatch(migration,/reservations\.reports\.view[^\n]*allowed_resource_type/);
});

test('existing module Event managers retain create without conversion to resource grants',()=>{
  assert.match(migration,/permission_key='reservations\.event\.manage'[\s\S]*resource_type is null[\s\S]*'reservations\.event\.create',null,null/);
  assert.doesNotMatch(migration,/update public\.module_permission_grants[\s\S]*resource_type='event'/);
});

test('Event resolution uses exact Event scope with canonical module fallback and tenant membership',()=>{
  assert.match(migration,/require_effective_module_permission\([\s\S]*p_permission,'event',p_event_id::text/);
  assert.match(migration,/public\.organization_members[\s\S]*om\.user_id=v_actor/);
});

test('booking creation context is minimal, capability filtered and shared by both scopes',()=>{
  const context=body('reservations_private.booking_creation_context');
  for(const field of ["'id',e.id","'name',e.name","'status',e.status","'bookingTypes'"])
    assert.ok(migration.includes(field),field);
  assert.doesNotMatch(context,/to_jsonb\(e\)/);
  assert.match(migration,/has_event_permission\(v_actor,'reservations\.booking\.create',e\.id\)/);
  assert.match(migration,/p_scope_type'<>'standalone'/);
  assert.match(migration,/p_conference_id/);
});

test('administrative reads do not inherit booking.create discovery authority',()=>{
  assert.match(migration,/p_operation in\('list_events','list_booking_types'\)[\s\S]*read_scoped/);
  assert.doesNotMatch(bundleSource,/\.listEvents\(\)|\.listBookingTypes\(/);
  assert.match(bundleSource,/useReservationsRuntime\(\)[\s\S]*runtime\.events/);
  assert.doesNotMatch(bundleSource,/\.bookingCreationContext\(\)/);
  assert.match(moduleRootSource,/<ReservationsRuntimeProvider>[\s\S]*<ReservationsModuleContent \/>/);
  assert.match(runtimeSource,/reservationsBackend\.bookingCreationContext\(\)/);
  assert.doesNotMatch(runtimeSource,/reservationsBackend\.(?:listEvents|listBookingTypes)\(/);
});

test('create Event has one capability and atomically grants only exact Event management',()=>{
  const primitive=body('platform_private.grant_deterministic_resource_permission');
  assert.match(migration,/create_event_authorized[\s\S]*'reservations\.event\.create',null,null/);
  assert.match(migration,/platform_private\.grant_deterministic_resource_permission\([\s\S]*v_context,v_operation_id,v_event_id/);
  assert.match(primitive,/'reservations','reservations\.event\.manage','event',p_created_resource_id::text/);
  assert.doesNotMatch(primitive,/permission_key='module\.manage'|reservations\.(?:booking|payment|attendance|operations|reports)\./);
  assert.doesNotMatch(migration,/function reservations_private\.grant_created_event_manager/);
  assert.doesNotMatch(body('reservations_private.create_event_authorized'),/insert into public\.module_permission_grants/);
});

test('deterministic ownership is Foundation-owned and has one fixed non-browser mapping',()=>{
  const primitive=body('platform_private.grant_deterministic_resource_permission');
  assert.match(primitive,/p_authorization_context jsonb,p_operation_id uuid,p_created_resource_id uuid/);
  assert.match(primitive,/p_authorization_context->>'moduleKey'<>'reservations'/);
  assert.match(primitive,/p_authorization_context->>'permissionKey'<>'reservations\.event\.create'/);
  assert.match(primitive,/DETERMINISTIC_RESOURCE_GRANT_RULE_INVALID/);
  assert.match(primitive,/'permissionKey','reservations\.event\.manage','resourceType','event'/);
  assert.doesNotMatch(primitive,/p_target_user_id|p_module_key|p_permission_key|p_resource_type/);
  assert.match(migration,/revoke all on function platform_private\.grant_deterministic_resource_permission\(jsonb,uuid,uuid\) from public,anon,authenticated,service_role/);
});

test('deterministic ownership cannot cross users and administrative self-grant remains prohibited',()=>{
  const primitive=body('platform_private.grant_deterministic_resource_permission');
  assert.match(primitive,/v_actor:=nullif\(p_authorization_context->>'actorUserId',''\)::uuid/);
  assert.match(primitive,/'targetUserId',v_actor/);
  assert.match(primitive,/p_operation_id,'grant',v_actor,v_device,v_actor/);
  const administration=fs.readFileSync(
    'supabase/migrations/20260829130000_module_permission_catalog_and_grant_adapter.sql','utf8'
  );
  assert.match(administration,/p_action = 'grant' and actor_id = p_target_user_id[\s\S]*MODULE_GRANT_SELF_GRANT_PROHIBITED/);
});

test('deterministic grant uses canonical operation replay and audit provenance',()=>{
  const primitive=body('platform_private.grant_deterministic_resource_permission');
  assert.match(migration,/authority_source in \('system_owner','module_grant','business_rule'\)/);
  assert.match(primitive,/from public\.module_grant_operations where operation_id=p_operation_id/);
  assert.match(primitive,/if v_prior\.intent_hash=v_intent then return v_prior\.stored_result/);
  assert.match(primitive,/MODULE_GRANT_OPERATION_MISMATCH/);
  assert.match(primitive,/insert into public\.module_grant_operations/);
  assert.match(primitive,/insert into public\.module_grant_audit_log/);
  assert.match(primitive,/'business_rule',null,p_operation_id/);
});

test('Event insert and deterministic grant remain in one create transaction',()=>{
  const create=body('reservations_private.create_event_authorized');
  const insertAt=create.indexOf('insert into reservations.events');
  const grantAt=create.indexOf('platform_private.grant_deterministic_resource_permission');
  const completeAt=create.indexOf('complete_operation');
  assert.ok(insertAt>=0&&grantAt>insertAt&&completeAt>grantAt);
});

test('canonical protected dispatcher and Edge allow exactly the new operation',()=>{
  assert.match(edge,/'get_booking_creation_context'/);
  assert.match(migration,/p_operation<>'get_booking_creation_context'[\s\S]*DEVICE_SESSION_INVALID/);
  assert.match(migration,/return reservations\.read\(v_session\.device_id,p_operation,p_args\)/);
});

test('retired permissions and legacy dispatchers are not revived',()=>{
  for(const permission of ['reservations.booking.cancel','reservations.assignment.manage','reservations.stay.check_in','reservations.stay.check_out'])
    assert.doesNotMatch(migration,new RegExp(permission.replaceAll('.','\\.')));
  assert.doesNotMatch(migration,/create_(?:legacy_)?reservations_dispatch|LEGACY_RESERVATIONS_DISPATCH_RETIRED/);
});

test('create_booking still rechecks exact Event booking.create server-side',()=>{
  const scoped=fs.readFileSync(
    'supabase/migrations/20260911120000_reservations_scope_partition_integrity.sql','utf8'
  );
  assert.match(scoped,/p_operation='create_booking'[\s\S]*resolve_event_scope\(p_device_id,\(p_args->>'p_event_id'\)::uuid,'reservations\.booking\.create'\)/);
  assert.match(migration,/return reservations\.mutate_pre_authorization_architecture_reconciliation\(p_device_id,p_operation,p_args\)/);
});
