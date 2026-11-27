const fs=require('fs'),assert=require('assert');
const pwa=fs.readFileSync('pwa.js','utf8');
assert.match(pwa,/function notificationPushEnvironmentAllowed\(\)/);
assert.match(pwa,/namespace\.environment==='development'/);
assert.match(pwa,/namespace\.projectRef==='gppwltrifgfxrkzvvxoe'/);
assert.match(pwa,/PUSH_ENVIRONMENT_MISMATCH/);
assert.match(pwa,/serverPushState\(subscription\).*notificationPushEnvironmentAllowed/s);
assert.doesNotMatch(pwa,/app_base_path|appBasePath/);
console.log('platform notification environment boundary: PASS');
