const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

const source = fs.readFileSync('js/reservations-route-accessibility.js', 'utf8');

function button(route) {
  const attrs = new Map([['data-platform-route', route]]);
  const classes = new Set();
  return {
    disabled: false,
    getAttribute(name) { return attrs.get(name) || null; },
    setAttribute(name, value) { attrs.set(name, String(value)); },
    removeAttribute(name) { attrs.delete(name); },
    classList: { add(name) { classes.add(name); }, remove(name) { classes.delete(name); } },
    closest(selector) { return selector === '[data-platform-route]' ? this : null; },
    attr(name) { return attrs.get(name); },
  };
}

function load(items) {
  let guard;
  const document = {
    querySelectorAll(selector) { return selector === '[data-platform-route]' ? items : []; },
    addEventListener(name, fn, capture) { if (name === 'click' && capture === true) guard = fn; },
  };
  const window = { document };
  vm.runInNewContext(source, { window });
  return { api: window.ReservationsRouteAccessibility, guard };
}

test('denied reservations routes remain present and become disabled', () => {
  const dashboard = button('/reservations');
  const create = button('/reservations/bookings/new');
  const warehouse = button('/warehouse');
  const { api } = load([dashboard, create, warehouse]);
  api.setRouteAccessibility([
    { route: '/reservations', enabled: false },
    { route: '/reservations/bookings/new', enabled: true },
  ]);
  assert.equal(dashboard.disabled, true);
  assert.equal(dashboard.attr('aria-disabled'), 'true');
  assert.equal(create.disabled, false);
  assert.equal(create.attr('aria-disabled'), undefined);
  assert.equal(warehouse.disabled, false);
});

test('empty snapshot clears stale disabled state', () => {
  const events = button('/reservations/events');
  const { api } = load([events]);
  api.setRouteAccessibility([{ route: '/reservations/events', enabled: false }]);
  assert.equal(events.disabled, true);
  api.setRouteAccessibility([]);
  assert.equal(events.disabled, false);
  assert.equal(events.attr('aria-disabled'), undefined);
});

test('capture guard blocks denied route before platform click handler', () => {
  const events = button('/reservations/events');
  const { api, guard } = load([events]);
  api.setRouteAccessibility([{ route: '/reservations/events', enabled: false }]);
  let prevented = false;
  let stopped = false;
  guard({ target: events, preventDefault() { prevented = true; }, stopImmediatePropagation() { stopped = true; } });
  assert.equal(prevented, true);
  assert.equal(stopped, true);
});

test('subsequent snapshot can re-enable a previously denied route', () => {
  const reports = button('/reservations/reports');
  const { api } = load([reports]);
  api.setRouteAccessibility([{ route: '/reservations/reports', enabled: false }]);
  assert.equal(reports.disabled, true);
  api.setRouteAccessibility([{ route: '/reservations/reports', enabled: true }]);
  assert.equal(reports.disabled, false);
});
