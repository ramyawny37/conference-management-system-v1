const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..', 'supabase', 'migrations');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const write = read('20261027114000_reservations_canonical_booking_write_cutover.sql');
const accommodation = read('20261027114500_reservations_canonical_accommodation_read_cutover.sql');
const retirement = read('20261027115000_reservations_remove_obsolete_snapshot_projection.sql');

test('active booking mutation routes to canonical participation without a second person', () => {
 assert.match(write, /link_booking_to_canonical_participation/);
 assert.match(write, /project_booking_to_conference/);
 assert.doesNotMatch(write, /create_conference_participation_with_person|insert into platform\.people/i);
});
test('accommodation read uses central participation and actual occupancy', () => {
 assert.match(accommodation, /conference_participations/);
 assert.match(accommodation, /conference_accommodation_occupancies/);
 assert.match(accommodation, /conference_accommodation_rooms/);
 assert.match(accommodation, /conference_accommodation_floors/);
 assert.match(accommodation, /conference_accommodation_houses/);
 assert.doesNotMatch(accommodation, /from public\.conference_snapshots/i);
});
test('legacy snapshot projection is removed after cutover with guard', () => {
 assert.match(retirement, /drop function reservations_private\.project_booking_to_conference/);
 assert.match(retirement, /RESERVATIONS_LEGACY_SNAPSHOT_REMAINS/);
});
