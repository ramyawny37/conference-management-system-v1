const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root,
  'supabase/migrations/20261104104306_reservations_manual_person_identity_resolution.sql'), 'utf8');
const moduleSource = fs.readFileSync(path.join(root,
  'modules/reservations/reservations-module.js'), 'utf8');
const identityRuntime = fs.readFileSync(path.join(root,
  'js/supabase/reservations-person-identity-resolution.js'), 'utf8');

test('manual canonical person creation is guarded inside the original booking writer', () => {
  assert.match(migration, /pg_get_functiondef\('reservations_private\.mutate_scoped/);
  assert.match(migration, /manual_person_identity_challenges/);
  assert.match(migration, /operation_id=v_operation_id and device_id=p_device_id and event_id=v_event\.id/);
  assert.match(migration, /RESERVATIONS_PERSON_IDENTITY_RESOLUTION_STALE/);
  assert.match(migration, /p_identity_resolution_decision'='different'/);
  assert.match(migration, /p_identity_resolution_decision'='existing'/);
  assert.match(migration, /pg_advisory_xact_lock/);
});

test('candidate discovery reuses canonical normalization and never auto-merges', () => {
  assert.match(migration, /platform_private\.person_name_key/);
  assert.match(migration, /platform_private\.person_phone_key/);
  assert.match(migration, /person\.name_search=/);
  assert.match(migration, /person\.phone_search=/);
  assert.doesNotMatch(migration, /unique\s*\([^)]*(?:full_name|phone)/i);
  assert.doesNotMatch(migration, /update\s+platform\.people[\s\S]{0,200}person_name_key/i);
});

test('challenge data and helper are private from Data API roles', () => {
  assert.match(migration, /revoke all on reservations_private\.manual_person_identity_challenges\s+from public,anon,authenticated,service_role/i);
  assert.match(migration, /revoke all on function platform_private\.reservations_person_identity_candidates[\s\S]*from public,anon,authenticated,service_role/i);
  assert.match(migration, /revoke all on function reservations_private\.mutate_scoped[\s\S]*from public,anon,authenticated/i);
});

test('reservations UI handles the server-owned identity resolution outcome', () => {
  assert.match(identityRuntime, /identityResolutionRequired/);
  assert.match(identityRuntime, /identityResolutionToken/);
  assert.match(identityRuntime, /p_identity_resolution_token/);
  assert.match(identityRuntime, /p_identity_resolution_decision/);
  assert.match(identityRuntime, /PlatformDeviceSession=Object\.freeze/);
  assert.match(moduleSource, /async createBooking/);
});

test('manual resolution exposes all choices and all distinguishing profile fields', () => {
  assert.match(identityRuntime, /اختيار الشخص الموجود/);
  assert.match(identityRuntime, /هذا شخص مختلف/);
  assert.match(identityRuntime, /الرجوع للتعديل/);
  for (const key of ['fullName','phone','gender','dateOfBirth','church','governorate','cityOrVillage','serviceSector','serviceSectorOther'])
    assert.match(identityRuntime, new RegExp(key));
});

test('runtime retries the original protected operation with the same operation id after an explicit choice', async () => {
  const buttons = [];
  class Element {
    constructor(tag) { this.tag = tag; this.children = []; this.listeners = {}; this.textContent = ''; }
    appendChild(child) { this.children.push(child); if (child.tag === 'button') buttons.push(child); return child; }
    addEventListener(name, handler) { this.listeners[name] = handler; }
    setAttribute() {}
    remove() {}
  }
  const calls = [];
  const candidate = {
    personId: '11111111-1111-4111-8111-111111111111', fullName: 'Test Person',
    phone: '0100', gender: 'male', dateOfBirth: '2000-01-01', church: 'Test Church',
    governorate: 'Cairo', cityOrVillage: 'City', serviceSector: 'widows',
    serviceSectorOther: null, revision: 4,
  };
  const baseSession = {
    establish() {}, ensureValid() {}, validFor() {}, verify() {}, getSession() {}, clear() {},
    invokeProtected() {},
    async invokeModuleProtected(module, operation, args) {
      calls.push({ module, operation, args: { ...args } });
      if (calls.length === 1) return {
        identityResolutionRequired: true,
        identityResolutionToken: '22222222-2222-4222-8222-222222222222',
        candidates: [candidate],
      };
      return { booking: { id: 'booking' }, participant: { id: 'participant' } };
    },
  };
  const context = {
    window: null,
    document: { createElement: (tag) => new Element(tag), body: new Element('body') },
    PlatformDeviceSession: Object.freeze(baseSession), Promise, Object, Array, String,
  };
  context.window = context;
  vm.runInNewContext(identityRuntime, context);
  const operationId = '33333333-3333-4333-8333-333333333333';
  const pending = context.PlatformDeviceSession.invokeModuleProtected('reservations', 'create_booking', {
    p_operation_id: operationId, p_full_name: candidate.fullName, p_phone: candidate.phone,
    p_gender: candidate.gender, p_date_of_birth: candidate.dateOfBirth,
    p_church: candidate.church, p_governorate: candidate.governorate,
    p_city_or_village: candidate.cityOrVillage, p_service_sector: candidate.serviceSector,
    p_service_sector_other: null,
  });
  await new Promise((resolve) => setImmediate(resolve));
  buttons.find((button) => button.textContent === 'اختيار الشخص الموجود').listeners.click();
  await pending;
  assert.equal(calls.length, 2);
  assert.equal(calls[1].args.p_operation_id, operationId);
  assert.equal(calls[1].args.p_person_id, candidate.personId);
  assert.equal(calls[1].args.p_identity_resolution_decision, 'existing');
  assert.equal(calls[1].args.p_identity_resolution_token, '22222222-2222-4222-8222-222222222222');
});
