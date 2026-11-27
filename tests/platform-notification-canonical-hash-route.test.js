const fs=require('fs'),assert=require('assert');
const legacy=fs.readFileSync('supabase/migrations/20261126180000_platform_notification_canonical_hash_route.sql','utf8');
const canonical=fs.readFileSync('supabase/migrations/20261126181500_platform_registration_notification_requests_route.sql','utf8');
const routing=fs.readFileSync('js/application-routing.js','utf8');
const pwa=fs.readFileSync('pwa.js','utf8');
assert.ok(routing.includes("hash.indexOf('#/')===0"));
assert.ok(canonical.includes("'./#/reservations/registration-requests?eventId='||new.event_id::text"));
assert.ok(!canonical.includes("?tab=registration"));
assert.ok(canonical.includes("update platform.notification_events"));
assert.ok(canonical.includes("update platform.notification_outbox"));
assert.ok(canonical.includes("event_type='reservations.public_registration.submitted'"));
assert.ok(pwa.includes("function closePlatformNotificationPanel()"));
assert.ok(pwa.includes("closePlatformNotificationPanel();markPlatformNotificationRead"));
assert.ok(pwa.includes("setAttribute('aria-expanded','false')"));
assert.ok(legacy.includes("'./#/reservations/events/'||new.event_id::text||'?tab=registration'"));
console.log('platform notification canonical requests route: PASS');

const worker=fs.readFileSync('service-worker.js','utf8');
assert.ok(worker.includes("new URL(rawUrl,self.registration.scope)"));
assert.ok(!worker.includes("platformNotificationId"));assert.ok(!worker.includes("notificationOpen"));const edge=fs.readFileSync('supabase/functions/platform-notifications/index.ts','utf8');assert.ok(edge.includes("notificationOpen="));
assert.ok(!worker.includes("platformNotificationClick"));
assert.ok(!pwa.includes("consumePlatformNotificationClick"));
assert.ok(!pwa.includes("pendingPlatformNotificationClickId"));assert.ok(pwa.includes("consumePlatformNotificationOpen"));

assert.match(pwa,/visibilityState==='visible'\)\{refreshPlatformNotificationState\(\);refreshPlatformNotificationInbox\(\);\}/);assert.match(pwa,/window\.addEventListener\('focus',refreshPlatformNotificationInbox\)/);assert.match(pwa,/window\.addEventListener\('hashchange',refreshPlatformNotificationInbox\)/);
