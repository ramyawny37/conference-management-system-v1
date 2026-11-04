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
const indexSource = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const workerSource = fs.readFileSync(path.join(root, 'service-worker.js'), 'utf8');

function extractFunction(source, name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `${name} must exist`);
  const body = source.indexOf('{', start);
  let depth = 0;
  for (let index = body; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}' && --depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Unterminated ${name}`);
}

function identityHookHarness(responses, chooseScope) {
  const calls = [];
  const slots = [];
  let cursor = 0;
  const x = {
    useState(initial) {
      const slot = cursor++;
      if (!(slot in slots)) slots[slot] = initial;
      return [slots[slot], (value) => { slots[slot] = value; }];
    },
    useRef(initial) {
      const slot = cursor++;
      if (!(slot in slots)) slots[slot] = { current: initial };
      return slots[slot];
    },
    useCallback(fn) { cursor += 1; return fn; },
  };
  const Me = {
    async createBooking(args) {
      calls.push({ ...args });
      const result = responses.shift();
      if (result instanceof Error) throw result;
      return result;
    },
  };
  const sb = (person, form) => Object.keys(form)
    .some((key) => String(person[key] ?? '').trim() !== String(form[key] ?? '').trim());
  const l = { jsx: (type, props) => ({ type, props }) };
  const context = { x, Me, sb, l, ManualPersonIdentityModal() {} };
  vm.runInNewContext(`${extractFunction(moduleSource, 'useManualPersonIdentityResolution')};this.hook=useManualPersonIdentityResolution`, context);
  return {
    calls,
    render() { cursor = 0; return context.hook(chooseScope); },
  };
}

const candidate = {
  personId: '11111111-1111-4111-8111-111111111111', fullName: 'Existing Person',
  phone: '0100', gender: 'male', dateOfBirth: '2000-01-01', church: 'Church',
  governorate: 'Cairo', cityOrVillage: 'City', serviceSector: 'widows',
  serviceSectorOther: null, revision: 7,
};
const challenge = {
  identityResolutionRequired: true,
  identityResolutionToken: '22222222-2222-4222-8222-222222222222',
  candidates: [candidate],
};
const draft = {
  p_operation_id: '33333333-3333-4333-8333-333333333333',
  p_full_name: candidate.fullName, p_phone: candidate.phone, p_gender: candidate.gender,
  p_date_of_birth: candidate.dateOfBirth, p_church: candidate.church,
  p_governorate: candidate.governorate, p_city_or_village: candidate.cityOrVillage,
  p_service_sector: candidate.serviceSector, p_service_sector_other: null,
};

test('manual identity UI is owned by the reservations module with no session interception', () => {
  assert.match(moduleSource, /function ManualPersonIdentityModal/);
  assert.match(moduleSource, /useManualPersonIdentityResolution\(r\)/);
  assert.match(moduleSource, /useManualPersonIdentityResolution\(X\)/);
  assert.doesNotMatch(indexSource + workerSource, /reservations-person-identity-resolution/);
  assert.equal(fs.existsSync(path.join(root, 'js/supabase/reservations-person-identity-resolution.js')), false);
  assert.equal((moduleSource.match(/function useReservationScopeDialog/g) || []).length, 1);
});

test('back from candidate resolution preserves the draft and performs no retry', async () => {
  const harness = identityHookHarness([challenge], async () => assert.fail('scope should not open'));
  const pending = harness.render().createBookingWithIdentityResolution({ ...draft });
  await new Promise((resolve) => setImmediate(resolve));
  harness.render().identityDialog.props.onCancel();
  assert.equal(await pending, null);
  assert.deepEqual(harness.calls, [draft]);
});

test('existing candidate reuses the original scope dialog and local scope omits canonical revision', async () => {
  let scopes = 0;
  const saved = { booking: { id: 'booking' }, participant: { id: 'participant' } };
  const harness = identityHookHarness([challenge, saved], async () => { scopes += 1; return 'save-local'; });
  const pending = harness.render().createBookingWithIdentityResolution({ ...draft, p_phone: '0111' });
  await new Promise((resolve) => setImmediate(resolve));
  harness.render().identityDialog.props.onChoose({ decision: 'existing', candidate });
  assert.equal(await pending, saved);
  assert.equal(scopes, 1);
  assert.equal(harness.calls[1].p_person_id, candidate.personId);
  assert.equal(harness.calls[1].p_identity_resolution_token, challenge.identityResolutionToken);
  assert.equal(harness.calls[1].p_operation_id, draft.p_operation_id);
  assert.equal('p_person_update_revision' in harness.calls[1], false);
});

test('canonical scope supplies expected revision and duplicate recovery carries the resolved person', async () => {
  const duplicate = Object.assign(new Error('RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT'), {
    code: 'RESERVATIONS_PERSON_ALREADY_REGISTERED_IN_EVENT',
  });
  const harness = identityHookHarness([challenge, duplicate], async () => 'update-canonical');
  const pending = harness.render().createBookingWithIdentityResolution({ ...draft, p_phone: '0111' });
  await new Promise((resolve) => setImmediate(resolve));
  harness.render().identityDialog.props.onChoose({ decision: 'existing', candidate });
  await assert.rejects(pending, (error) => {
    assert.equal(error.resolvedPersonId, candidate.personId);
    return true;
  });
  assert.equal(harness.calls[1].p_person_update_revision, candidate.revision);
  assert.match(moduleSource, /s\?\.personId\s*\|\|\s*qe\?\.resolvedPersonId/);
  assert.match(moduleSource, /E\.personId\s*\|\|\s*K\?\.resolvedPersonId/);
});

test('database guard stays bound to the original writer and revalidates candidates', () => {
  assert.match(migration, /manual_person_identity_challenges/);
  assert.match(migration, /operation_id=v_operation_id and device_id=p_device_id and event_id=v_event\.id/);
  assert.match(migration, /v_identity_challenge\.candidates<>v_identity_candidates/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /platform_private\.person_name_key/);
  assert.match(migration, /platform_private\.person_phone_key/);
  assert.doesNotMatch(migration, /unique\s*\([^)]*(?:full_name|phone)/i);
});

test('challenge storage and helper remain private from Data API roles', () => {
  assert.match(migration, /revoke all on reservations_private\.manual_person_identity_challenges\s+from public,anon,authenticated,service_role/i);
  assert.match(migration, /revoke all on function platform_private\.reservations_person_identity_candidates[\s\S]*from public,anon,authenticated,service_role/i);
  assert.match(migration, /revoke all on function reservations_private\.mutate_scoped[\s\S]*from public,anon,authenticated/i);
});
