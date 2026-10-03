const CACHE_NAME='cms-platform-auth-cutover-v1';
const CORE_ASSETS=[
  './',
  './index.html',
  './manifest.json',
  './shared-design-tokens.css?rev=platform-shell-phase2b-v1',
  './style.css?rev=item-unit-dialog-v1',
  './canonical-platform-shell.css?rev=reservations-workspace-v6',
  './js/sync/conference-activation-authorization.js?rev=runtime-authorization-phase1-v1'
];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(CORE_ASSETS)));self.skipWaiting();});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE_NAME).map(key=>caches.delete(key)))));self.clients.claim();});
self.addEventListener('fetch',event=>{if(event.request.method!=='GET')return;event.respondWith(fetch(event.request).catch(()=>caches.match(event.request).then(response=>response||caches.match('./index.html'))));});
