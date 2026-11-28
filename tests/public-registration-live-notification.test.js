'use strict';const assert=require('node:assert/strict'),fs=require('node:fs'),test=require('node:test');const moduleJs=fs.readFileSync('modules/reservations/reservations-module.js','utf8'),pwa=fs.readFileSync('pwa.js','utf8'),sw=fs.readFileSync('service-worker.js','utf8'),edge=fs.readFileSync('supabase/functions/public-registration/index.ts','utf8');test('public registration requests refresh without polling through canonical notification events',()=>{assert.doesNotMatch(moduleJs,/setInterval\([^,]+,15000\)/);assert.match(moduleJs,/platform-notification/);assert.match(pwa,/platformNotification/);assert.match(sw,/postMessage\(\{action:'platformNotification'/)});test('public submission persists notification transactionally and only asks delivery edge to flush',()=>{const migration=fs.readFileSync('supabase/migrations/20261126124500_platform_notification_transactional_outbox_dispatch.sql','utf8');assert.match(migration,/public_registration_request_notification_outbox/);assert.match(migration,/stage_public_registration_submitted_notification/);assert.match(edge,/fetch\(serviceUrl\+'\/functions\/v1\/platform-notifications'/);assert.match(edge,/'apikey':serviceKey/);assert.doesNotMatch(edge,/service\.functions\.invoke\('platform-notifications'/);assert.doesNotMatch(edge,/operation:'emit'/);assert.doesNotMatch(edge,/PLATFORM_NOTIFICATION_EMIT_FAILED/)});

test('registration settings stay event-scoped inside the dedicated requests workspace',()=>{assert.match(moduleJs,/title:"طلبات التسجيل",href:"\/registration-requests"/);assert.match(moduleJs,/"data-ui":"public-registration-requests-workspace"/);assert.match(moduleJs,/"data-ui":"public-registration-settings"/);assert.ok(moduleJs.includes("getPublicRegistrationSettings"))assert.match(moduleJs,/updatePublicRegistrationSettings/);assert.match(moduleJs,/window\.addEventListener\("platform-notification"/)});

test('canonical Platform reservations subnav exposes registration requests before participants',()=>{const indexHtml=fs.readFileSync('index.html','utf8');const requests=indexHtml.indexOf('data-platform-route="/reservations/registration-requests"');const participants=indexHtml.indexOf('data-platform-route="/reservations/participants"');assert.ok(requests>=0);assert.ok(participants>requests);});

test('registration requests workspace requires explicit event selection',()=>{assert.match(moduleJs,/"data-ui":"public-registration-requests-workspace"/);assert.match(moduleJs,/"aria-label":"اختيار الفعالية لطلبات التسجيل"/);assert.match(moduleJs,/value:"",children:"اختر الفعالية"/);assert.doesNotMatch(moduleJs,/\.length&&[^;]{0,120}\[0\]\.id/);});

test('global registration requests route owns scope discovery and bypasses conference-only gates',()=>{assert.match(moduleJs,/title:"طلبات التسجيل",href:"\/registration-requests"/);assert.match(moduleJs,/==="\/registration-requests"/);assert.match(moduleJs,/listPublicRegistrationEventOptions\(\)/);assert.match(moduleJs,/p_scope_type:"standalone"/);assert.match(moduleJs,/scopeLabel:"فعاليات مستقلة"/);assert.match(moduleJs,/p_conference_id:s\.conferenceId/);});

test('registration requests runtime asset is cache coherent',()=>{const html=fs.readFileSync('index.html','utf8');const sw=fs.readFileSync('service-worker.js','utf8');const revision=JSON.parse(fs.readFileSync('tools/reservations-artifact-policy.json','utf8')).currentRuntime.revision;const asset='modules/reservations/reservations-module.js?rev='+revision;assert.ok(html.includes(asset));assert.ok(sw.includes(asset));});

test('notification browser origin guard is confined to GET and emit requires backend authentication',()=>{const source=fs.readFileSync('supabase/functions/platform-notifications/index.ts','utf8');assert.ok(source.includes("if(req.method==='GET'){if(req.headers.get('Origin')!==ORIGIN)"));assert.ok(source.includes("if(apiKey!==serviceKey)throw new Error('PLATFORM_NOTIFICATION_BACKEND_REQUIRED')"));assert.match(source,/\['emit','flush'\]/)});

test('notification delivery edge uses canonical secret-api-key auth without legacy jwt gateway verification',()=>{const source=fs.readFileSync('supabase/functions/platform-notifications/index.ts','utf8'),publicRegistration=fs.readFileSync('supabase/functions/public-registration/index.ts','utf8'),config=fs.readFileSync('supabase/config.toml','utf8');assert.match(config,/\[functions\.platform-notifications\]\s*verify_jwt = false/);for(const backend of [source,publicRegistration]){assert.match(backend,/SUPABASE_SECRET_KEYS/);assert.doesNotMatch(backend,/PLATFORM_NOTIFICATION_WORKER_TOKEN/)}assert.match(publicRegistration,/fetch\(serviceUrl\+'\/functions\/v1\/platform-notifications'/);assert.match(publicRegistration,/'apikey':serviceKey/);assert.doesNotMatch(publicRegistration,/service\.functions\.invoke\('platform-notifications'/);assert.match(source,/req\.headers\.get\('apikey'\)/);assert.match(source,/createClient\(required\('SUPABASE_URL'\),required\('SUPABASE_SERVICE_ROLE_KEY'\)/);assert.doesNotMatch(source,/createClient\(required\('SUPABASE_URL'\),serviceKey/);assert.doesNotMatch(source,/bearer\(/);assert.doesNotMatch(source,/Authorization/)});

test('failed server push activation rolls back a newly-created browser subscription',()=>{assert.match(pwa,/existing=await registration\.pushManager\.getSubscription\(\)/);assert.match(pwa,/if\(!existing\)try\{await subscription\.unsubscribe\(\)/);assert.match(pwa,/upsert_notification_push_subscription/);});

test('notification lifecycle PWA asset revision is coherent',()=>{const html=fs.readFileSync('index.html','utf8'),worker=fs.readFileSync('service-worker.js','utf8'),asset='pwa.js?rev=notification-inbox-route-closure-v1';assert.ok(html.includes(asset));assert.ok(worker.includes(asset));});

test('notification lifecycle reconciles permission and remote device revocation without polling',()=>{
  const pwa=fs.readFileSync('pwa.js','utf8');
  assert.match(pwa,/Notification\.permission!=='granted'/);
  assert.match(pwa,/disable_notification_push_subscription/);
  assert.match(pwa,/revokedSubscription\.unsubscribe\(\)/);
  assert.match(pwa,/visibilitychange/);
  assert.match(pwa,/listPlatformNotifications\(1\)/);
  assert.match(pwa,/stopPlatformNotificationRealtime\(\)/);
  assert.doesNotMatch(pwa,/setInterval\(/);
});



test('notification click durably marks read, refreshes unread count, then navigates',()=>{
  const inboxSql=fs.readFileSync('supabase/migrations/20261126113000_platform_notification_durable_inbox.sql','utf8');
  assert.match(inboxSql,/read_at=coalesce\(r\.read_at,statement_timestamp\(\)\)/);
  assert.match(inboxSql,/r\.read_at is null[\s\S]*notification_user_is_authorized/);
  assert.match(pwa,/markPlatformNotificationRead\(item\.getAttribute\('data-platform-notification-id'\)\)\.then\(function\(\)\{return refreshPlatformNotificationInbox\(\);\}\)\.then\(function\(\)\{if\(url\)window\.location\.href=url;\}\)/);
  assert.match(pwa,/count\.textContent=unread>99\?'99\+':String\(unread\);count\.hidden=unread<1/);
});

test('platform device edge admits the complete canonical notification lifecycle',()=>{const source=fs.readFileSync('supabase/functions/platform-device-operation/index.ts','utf8');for(const operation of ['list_my_notifications','mark_my_notification_read','get_notification_push_subscription_state','upsert_notification_push_subscription','disable_notification_push_subscription'])assert.ok(source.includes("platform.add('"+operation+"')"),operation+' missing from platform device edge allowlist');});
