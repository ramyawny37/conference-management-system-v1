const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('period create and update leave technical code ownership to the database', () => {
  const source = fs.readFileSync(path.join(__dirname, '../modules/reservations/reservations-module.js'), 'utf8');
  const marker = 'async savePeriod(t,a){';
  const start = source.indexOf(marker);
  assert.ok(start >= 0, 'savePeriod adapter exists');
  const end = source.indexOf('},deletePeriod(', start);
  assert.ok(end > start, 'savePeriod adapter boundary exists');
  const adapter = source.slice(start, end);
  assert.match(adapter, /const i=\\{p_label:a\\.label,p_starts_on:a\\.from,p_ends_on:a\\.to,p_display_order:a\\.displayOrder\\}/);
  assert.match(adapter, /update_event_period[^]*p_period_id:a\\.id,p_expected_revision/);
  assert.match(adapter, /create_event_period[^]*p_event_id:t/);
  assert.doesNotMatch(adapter, /p_kind/);
  assert.doesNotMatch(source, /الكود المركزي/);
});
