const fs=require('fs'),assert=require('assert');
const pwa=fs.readFileSync('pwa.js','utf8');
assert.match(pwa,/function notificationPushEnvironmentAllowed\(\)/);
assert.match(pwa,/namespace\.environment==='development'/);
assert.match(pwa,/namespace\.projectRef==='gppwltrifgfxrkzvvxoe'/);
assert.match(pwa,/async function enablePlatformNotifications\(\)\{if\(!notificationPushEnvironmentAllowed\(\)\)throw new Error\('PUSH_ENVIRONMENT_MISMATCH'\)/);
assert.match(pwa,/async function platformNotificationState\(\)\{if\(!notificationPushEnvironmentAllowed\(\)\)return \{enabled:false,permission:'environment_mismatch',browserSubscribed:false,serverRegistered:false\}/);
assert.doesNotMatch(pwa,/app_base_path|appBasePath/);
console.log('platform notification environment boundary: PASS');
