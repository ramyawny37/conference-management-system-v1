'use strict';const fs=require('node:fs'),assert=require('node:assert/strict'),test=require('node:test');const m=fs.readFileSync('supabase/migrations/20261127170000_public_registration_applicant_push.sql','utf8'),stateMigration=fs.readFileSync('supabase/migrations/20261128190000_public_registration_push_subscription_state.sql','utf8'),pub=fs.readFileSync('public-registration.js','utf8'),edge=fs.readFileSync('supabase/functions/public-registration/index.ts','utf8'),delivery=fs.readFileSync('supabase/functions/platform-notifications/index.ts','utf8');test('applicant push is request-owned and shares canonical delivery graph',()=>{assert.match(m,/notification_applicant_push_subscriptions/);assert.match(m,/tracking_secret_digest=p_tracking_secret_digest/);assert.match(m,/applicant_push_subscription/);assert.match(m,/public_registration\.decision/);assert.match(m,/notification_channel_deliveries/);assert.doesNotMatch(m,/notification_recipients\([^)]*applicant/i)});test('public tracking page opts in explicitly with tracking capability',()=>{assert.match(pub,/أبلغني عند تحديث حالة الطلب/);assert.match(pub,/Notification\.requestPermission/);assert.match(pub,/subscribe_push/);assert.match(edge,/upsert_push_subscription/);assert.match(edge,/PLATFORM_WEB_PUSH_VAPID_PUBLIC_KEY/)});test('applicant delivery never receives authenticated platform read receipt',()=>{assert.match(m,/'audience',case when nd\.destination_kind='applicant_push_subscription' then 'applicant' else 'platform' end/);assert.match(delivery,/if\(item\.audience==='applicant'\)return target/);assert.match(delivery,/notificationOpen/)});
test('applicant notification state is read-only until the user explicitly opts in',()=>{
 const start=pub.indexOf('async function refreshStatusNotificationState');
 const end=pub.indexOf('async function enableStatusNotifications',start);
 const refresh=pub.slice(start,end);
 assert.ok(refresh.includes("call('push_state'"));
 assert.equal(refresh.includes('subscribe_push'),false);
 assert.ok(refresh.includes('button.hidden=enabled'));
 const enable=pub.slice(end,pub.indexOf('function statusLabel',end));
 assert.ok(enable.includes("call('subscribe_push'"));
 assert.ok(edge.includes("operation==='push_state'"));
 assert.ok(edge.includes("p_operation:'push_subscription_state'"));
 assert.ok(stateMigration.includes('public_registration_get_push_subscription_state'));
 assert.ok(stateMigration.includes("return jsonb_build_object('active',v_active)"));
});
