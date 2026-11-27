let deferredInstallPrompt = null;
const installButton = document.getElementById('install-app-btn');
const updateButton = document.getElementById('update-now');
const updateMessage = document.getElementById('update-message');
const originalUpdateButtonText = updateButton ? updateButton.textContent : '';
const originalUpdateMessageText = updateMessage ? updateMessage.textContent : '';
const UPDATE_TIMEOUT_MS = 12000;
const UPDATE_CHECK_INTERVAL_MS = 5 * 60 * 1000;
let updateInProgress = false;
let reloadTriggered = false;
let updateTimeoutId = null;
let serviceWorkerRegistration = null;
let updateCheckInProgress = false;
let lastUpdateCheckAt = 0;
let versionRequestWorker = null;
let versionRequestPromise = null;
let displayedUpdateWorker = null;
let acceptedUpdateWorker = null;
const observedUpdateWorkers = new WeakSet();
const appShellRevision = window.APP_SHELL_REVISION || 'unknown';

function requestWorkerDiagnostics(worker) {
  if (!worker) return Promise.resolve(null);
  return new Promise(resolve => {
    const channel = new MessageChannel();
    const timeoutId = setTimeout(() => resolve(null), 2000);
    channel.port1.onmessage = event => {
      clearTimeout(timeoutId);
      resolve(event.data && event.data.action === 'updateDiagnostics'
        ? event.data : null);
    };
    try {
      worker.postMessage({ action: 'getUpdateDiagnostics' }, [channel.port2]);
    } catch (error) {
      clearTimeout(timeoutId);
      resolve(null);
    }
  });
}

function refreshPwaUpdateDiagnostics() {
  const target = document.getElementById('pwa-update-diagnostics');
  const registration = serviceWorkerRegistration;
  const controller = navigator.serviceWorker && navigator.serviceWorker.controller;
  return Promise.all([
    requestWorkerDiagnostics(registration && registration.active),
    requestWorkerDiagnostics(registration && registration.waiting),
    requestWorkerDiagnostics(registration && registration.installing)
  ]).then(values => {
      const diagnostic = {
      activeWorkerCacheRevision: values[0] && values[0].cacheRevision || null,
      waitingWorker: values[1] && values[1].cacheRevision || null,
      installingWorker: values[2] && values[2].cacheRevision || null,
      controllerScriptURL: controller && controller.scriptURL || null,
        appShellRevision: appShellRevision,
        startup: window.StartupAccessGate &&
          typeof window.StartupAccessGate.getState === 'function'
          ? window.StartupAccessGate.getState()
          : null
      };
    if (target) target.textContent = JSON.stringify(diagnostic, null, 2);
    return diagnostic;
  });
}

window.PWAUpdateDiagnostics = Object.freeze({getState:refreshPwaUpdateDiagnostics});

window.addEventListener('beforeinstallprompt', (e) => {
  // Prevent the mini-infobar from appearing on mobile
  e.preventDefault();
  // Stash the event so it can be triggered later.
  deferredInstallPrompt = e;
  // Update UI to notify the user they can install the PWA
  if (installButton && window.matchMedia('(display-mode: browser)').matches) {
    installButton.style.display = 'block';
  }
});

if (installButton) {
  installButton.addEventListener('click', async () => {
    if (!deferredInstallPrompt) {
      return;
    }
    // Show the install prompt
    deferredInstallPrompt.prompt();
    // Wait for the user to respond to the prompt
    await deferredInstallPrompt.userChoice;
    // We've used the prompt, and can't use it again, throw it away
    deferredInstallPrompt = null;
    // Hide the install button
    installButton.style.display = 'none';
  });
}

window.addEventListener('appinstalled', () => {
  deferredInstallPrompt = null;
  if (installButton) {
    installButton.style.display = 'none';
  }
});

function restoreUpdateUi(message) {
  if (updateTimeoutId !== null) {
    clearTimeout(updateTimeoutId);
    updateTimeoutId = null;
  }
  updateInProgress = false;
  acceptedUpdateWorker = null;
  if (updateButton) {
    updateButton.disabled = false;
    updateButton.textContent = originalUpdateButtonText;
  }
  if (updateMessage) {
    updateMessage.textContent = message || originalUpdateMessageText;
    if (message) {
      setTimeout(() => {
        if (!updateInProgress && updateMessage.textContent === message) {
          updateMessage.textContent = originalUpdateMessageText;
        }
      }, 5000);
    }
  }
}

function getActionableWaitingWorker(registration) {
  const controller = navigator.serviceWorker && navigator.serviceWorker.controller;
  const worker = registration && registration.waiting;
  return controller && worker && worker.state === 'installed' ? worker : null;
}

function hideUpdateBar(preserveAcceptedUpdate) {
  const updateBar = document.getElementById('update-bar');
  displayedUpdateWorker = null;
  versionRequestWorker = null;
  versionRequestPromise = null;
  if (updateBar) updateBar.classList.remove('show');
  if (!preserveAcceptedUpdate) restoreUpdateUi();
  refreshPwaUpdateDiagnostics();
}

function reconcileUpdateBar(registration) {
  const worker = getActionableWaitingWorker(registration);
  if (worker) {
    observeUpdateWorker(worker, registration);
    showUpdateBar(worker);
    return worker;
  }
  const acceptedWorkerIsActivating = updateInProgress && acceptedUpdateWorker &&
    (acceptedUpdateWorker.state === 'activating' || acceptedUpdateWorker.state === 'activated');
  hideUpdateBar(acceptedWorkerIsActivating);
  return null;
}

function observeUpdateWorker(worker, registration) {
  if (!worker || observedUpdateWorkers.has(worker)) return;
  observedUpdateWorkers.add(worker);
  worker.addEventListener('statechange', () => {
    Promise.resolve().then(() => reconcileUpdateBar(registration));
  });
}

function checkForServiceWorkerUpdate() {
  if (!serviceWorkerRegistration) {
    return Promise.resolve();
  }
  if (getActionableWaitingWorker(serviceWorkerRegistration)) {
    reconcileUpdateBar(serviceWorkerRegistration);
    return Promise.resolve();
  }
  if (!navigator.onLine || updateCheckInProgress) {
    return Promise.resolve();
  }

  const now = Date.now();
  if (now - lastUpdateCheckAt < UPDATE_CHECK_INTERVAL_MS) {
    return Promise.resolve();
  }

  updateCheckInProgress = true;
  lastUpdateCheckAt = now;

  return Promise.resolve()
    .then(() => serviceWorkerRegistration.update())
    .catch(() => null)
    .then(() => {
      updateCheckInProgress = false;
    });
}

function getWorkerVersion(worker) {
  if (!worker) {
    return Promise.resolve('');
  }
  if (versionRequestWorker === worker && versionRequestPromise) {
    return versionRequestPromise;
  }

  versionRequestWorker = worker;
  versionRequestPromise = new Promise(resolve => {
    let channel;
    try {
      channel = new MessageChannel();
    } catch (error) {
      resolve('');
      return;
    }

    let settled = false;
    let timeoutId = null;

    const finish = version => {
      if (settled) return;
      settled = true;
      if (timeoutId !== null) {
        clearTimeout(timeoutId);
      }
      channel.port1.onmessage = null;
      channel.port1.close();
      resolve(version);
    };

    timeoutId = setTimeout(() => {
      finish('');
    }, 2500);

    channel.port1.onmessage = event => {
      const data = event.data;
      const version = data &&
        data.action === 'versionInfo' &&
        typeof data.version === 'string'
        ? data.version.trim()
        : '';
      finish(version);
    };

    try {
      worker.postMessage({ action: 'getVersion' }, [channel.port2]);
    } catch (error) {
      finish('');
    }
  });

  return versionRequestPromise;
}

function showUpdateBar(worker) {
  const updateBar = document.getElementById('update-bar');
  if (updateBar && worker === getActionableWaitingWorker(serviceWorkerRegistration)) {
    updateBar.classList.add('show');
    if (!updateInProgress && updateMessage) {
      updateMessage.textContent = originalUpdateMessageText;
    }
    if (worker) {
      displayedUpdateWorker = worker;
      getWorkerVersion(worker).then(version => {
        if (
          version &&
          displayedUpdateWorker === worker &&
          updateBar.classList.contains('show') &&
          updateMessage
        ) {
          updateMessage.textContent = 'يتوفر الإصدار ' + version + ' من البرنامج';
        }
      });
    }
    refreshPwaUpdateDiagnostics();
    updateButton.onclick = () => {
      if (updateInProgress) return;
      updateInProgress = true;
      updateButton.disabled = true;
      updateButton.textContent = 'جارٍ التحديث…';

      Promise.resolve(serviceWorkerRegistration).then(reg => {
        const waitingWorker = getActionableWaitingWorker(reg);
        if (!waitingWorker || waitingWorker !== displayedUpdateWorker) {
          hideUpdateBar();
          return;
        }
        acceptedUpdateWorker = waitingWorker;
        waitingWorker.postMessage({ action: 'skipWaiting' });
        updateTimeoutId = setTimeout(() => {
          restoreUpdateUi('لم يكتمل التحديث. يرجى المحاولة مرة أخرى.');
        }, UPDATE_TIMEOUT_MS);
      }).catch(() => {
        restoreUpdateUi('تعذر بدء التحديث. يرجى المحاولة مرة أخرى.');
      });
    };
    document.getElementById('update-later').onclick = () => {
      if (updateInProgress) return;
      updateBar.classList.remove('show');
      displayedUpdateWorker = null;
    };
  }
}

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./service-worker.js',{
      updateViaCache:'none'
    }).then(registration => {
      serviceWorkerRegistration = registration;
      console.log('ServiceWorker registration successful with scope: ', registration.scope);

      reconcileUpdateBar(registration);

      registration.addEventListener('updatefound', () => {
        const newWorker = registration.installing;
        observeUpdateWorker(newWorker, registration);
        reconcileUpdateBar(registration);
      });

      checkForServiceWorkerUpdate();
      refreshPwaUpdateDiagnostics();
    }).catch(err => {
      console.log('ServiceWorker registration failed: ', err);
    });

    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (!updateInProgress || reloadTriggered) return;
      reloadTriggered = true;
      displayedUpdateWorker = null;
      acceptedUpdateWorker = null;
      if (updateTimeoutId !== null) {
        clearTimeout(updateTimeoutId);
        updateTimeoutId = null;
      }
      window.location.reload();
    });
  });

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      checkForServiceWorkerUpdate();
    }
  });

  window.addEventListener('online', () => {
    checkForServiceWorkerUpdate();
  });
}

(function(){
function b64key(value){var pad='='.repeat((4-value.length%4)%4),raw=atob((value+pad).replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(raw,function(ch){return ch.charCodeAt(0);});}
async function accessibleModules(){var modules=['conference','reservations','warehouse'],allowed=['platform'];if(!window.PlatformDeviceSession||typeof window.PlatformDeviceSession.invokeModuleProtected!=='function')throw new Error('DEVICE_SESSION_RUNTIME_REQUIRED');for(var i=0;i<modules.length;i++){try{await window.PlatformDeviceSession.invokeModuleProtected(modules[i],'check_module_access',{});allowed.push(modules[i]);}catch(error){}}return allowed.sort();}
async function enablePlatformNotifications(){if(!('Notification' in window)||!('PushManager' in window)||!('serviceWorker' in navigator))throw new Error('PUSH_NOT_SUPPORTED');var permission=Notification.permission;if(permission!=='granted')permission=await Notification.requestPermission();if(permission!=='granted')throw new Error('PUSH_PERMISSION_DENIED');var config=window.SUPABASE_RUNTIME_CONFIG||{},url=String(config.url||'');if(!url)throw new Error('SUPABASE_CONFIG_MISSING');var response=await fetch(url+'/functions/v1/platform-notifications',{method:'GET',headers:{'Accept':'application/json'}}),body=await response.json();if(!response.ok||!body||!body.ok||!body.data||!body.data.vapidPublicKey)throw new Error(body&&body.error&&body.error.code||'PUSH_CONFIG_UNAVAILABLE');var registration=await navigator.serviceWorker.ready,existing=await registration.pushManager.getSubscription(),subscription=existing||await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:b64key(body.data.vapidPublicKey)});try{var serialized=subscription.toJSON(),modules=await accessibleModules();await window.PlatformDeviceSession.invokeModuleProtected('platform','upsert_notification_push_subscription',{p_endpoint:subscription.endpoint,p_p256dh:serialized.keys&&serialized.keys.p256dh||'',p_auth:serialized.keys&&serialized.keys.auth||'',p_module_keys:modules,p_user_agent:navigator.userAgent});return {enabled:true,moduleKeys:modules};}catch(error){if(!existing)try{await subscription.unsubscribe();}catch(_cleanupError){}throw error;}}
async function disablePlatformNotifications(){if(!('serviceWorker' in navigator))return {enabled:false};var registration=await navigator.serviceWorker.ready,subscription=await registration.pushManager.getSubscription();if(!subscription)return {enabled:false};await window.PlatformDeviceSession.invokeModuleProtected('platform','disable_notification_push_subscription',{p_endpoint:subscription.endpoint});await subscription.unsubscribe();return {enabled:false};}
async function platformNotificationState(){if(!('Notification' in window)||!('serviceWorker' in navigator))return {enabled:false,permission:'unsupported',browserSubscribed:false,serverRegistered:false};if(Notification.permission!=='granted'){var revokedRegistration=await navigator.serviceWorker.ready,revokedSubscription=await revokedRegistration.pushManager.getSubscription();if(revokedSubscription){try{await window.PlatformDeviceSession.invokeModuleProtected('platform','disable_notification_push_subscription',{p_endpoint:revokedSubscription.endpoint});}catch(_serverDisableError){}try{await revokedSubscription.unsubscribe();}catch(_unsubscribeError){}}return {enabled:false,permission:Notification.permission,browserSubscribed:false,serverRegistered:false};}var registration=await navigator.serviceWorker.ready,subscription=await registration.pushManager.getSubscription();if(!subscription)return {enabled:false,permission:Notification.permission,browserSubscribed:false,serverRegistered:false};if(!window.PlatformDeviceSession||typeof window.PlatformDeviceSession.invokeModuleProtected!=='function')return {enabled:false,permission:Notification.permission,browserSubscribed:true,serverRegistered:false};var state=await window.PlatformDeviceSession.invokeModuleProtected('platform','get_notification_push_subscription_state',{p_endpoint:subscription.endpoint});return {enabled:!!(state&&state.active),permission:Notification.permission,browserSubscribed:true,serverRegistered:!!(state&&state.registered),moduleKeys:state&&Array.isArray(state.moduleKeys)?state.moduleKeys:[]};}
var platformNotificationChannel=null;
async function listPlatformNotifications(limit){if(!window.PlatformDeviceSession||typeof window.PlatformDeviceSession.invokeModuleProtected!=='function')throw new Error('DEVICE_SESSION_RUNTIME_REQUIRED');return window.PlatformDeviceSession.invokeModuleProtected('platform','list_my_notifications',{p_limit:Math.max(1,Math.min(Number(limit)||50,100))});}
async function markPlatformNotificationRead(id){if(!window.PlatformDeviceSession||typeof window.PlatformDeviceSession.invokeModuleProtected!=='function')throw new Error('DEVICE_SESSION_RUNTIME_REQUIRED');return window.PlatformDeviceSession.invokeModuleProtected('platform','mark_my_notification_read',{p_notification_event_id:String(id||'')});}
async function startPlatformNotificationRealtime(){if(platformNotificationChannel)return true;var layer=window.SupabaseClientLayer,client=layer&&typeof layer.getClient==='function'?layer.getClient():null,auth=window.SupabaseAuth,identity=auth&&typeof auth.getAccountIdentity==='function'?auth.getAccountIdentity():null;if(!client||!identity||!identity.authenticated||!identity.userId)return false;if(client.realtime&&typeof client.realtime.setAuth==='function')await client.realtime.setAuth();var topic='user:'+identity.userId+':notifications';platformNotificationChannel=client.channel(topic,{config:{private:true}}).on('broadcast',{event:'notification_created'},function(message){listPlatformNotifications(1).then(function(){window.dispatchEvent(new CustomEvent('platform-notification',{detail:message&&message.payload||message}));}).catch(function(){stopPlatformNotificationRealtime();renderPlatformNotificationInbox({items:[],unreadCount:0});});}).on('broadcast',{event:'notification_read'},function(message){listPlatformNotifications(1).then(function(){window.dispatchEvent(new CustomEvent('platform-notification-read',{detail:message&&message.payload||message}));}).catch(function(){stopPlatformNotificationRealtime();renderPlatformNotificationInbox({items:[],unreadCount:0});});}).subscribe(function(status){if(status==='CHANNEL_ERROR'||status==='TIMED_OUT'||status==='CLOSED'){try{client.removeChannel(platformNotificationChannel);}catch(_error){}platformNotificationChannel=null;}});return true;}
function stopPlatformNotificationRealtime(){var layer=window.SupabaseClientLayer,client=layer&&typeof layer.getClient==='function'?layer.getClient():null;if(client&&platformNotificationChannel)try{client.removeChannel(platformNotificationChannel);}catch(_error){}platformNotificationChannel=null;}
window.PlatformNotifications=Object.freeze({enable:enablePlatformNotifications,disable:disablePlatformNotifications,getState:platformNotificationState,list:listPlatformNotifications,markRead:markPlatformNotificationRead,startRealtime:startPlatformNotificationRealtime,stopRealtime:stopPlatformNotificationRealtime});
(function connectNotificationRealtime(attempt){startPlatformNotificationRealtime().then(function(ok){if(!ok&&attempt<20)setTimeout(function(){connectNotificationRealtime(attempt+1);},500);}).catch(function(error){console.error('Platform notification realtime failed',error);});})(0);
window.addEventListener('platform-session-reset',stopPlatformNotificationRealtime);
document.addEventListener('visibilitychange',function(){if(document.visibilityState==='visible')platformNotificationState().catch(function(){stopPlatformNotificationRealtime();renderPlatformNotificationInbox({items:[],unreadCount:0});});});
function renderPlatformNotificationInbox(data){var count=document.getElementById('platform-notifications-count'),list=document.getElementById('platform-notifications-list'),status=document.getElementById('platform-notifications-status');if(!count||!list)return;var items=data&&Array.isArray(data.items)?data.items:[],unread=Number(data&&data.unreadCount||0);count.textContent=unread>99?'99+':String(unread);count.hidden=unread<1;if(status)status.textContent=unread?unread+' غير مقروء':'';list.innerHTML=items.length?items.map(function(item){return '<button type="button" class="platform-notification-item'+(item.readAt?'':' is-unread')+'" data-platform-notification-id="'+String(item.id).replace(/"/g,'&quot;')+'" data-platform-notification-url="'+String(item.targetUrl||'').replace(/"/g,'&quot;')+'"><strong>'+String(item.title||'تنبيه').replace(/</g,'&lt;')+'</strong><span>'+String(item.body||'').replace(/</g,'&lt;')+'</span><small>'+new Date(item.createdAt).toLocaleString('ar-EG')+'</small></button>';}).join(''):'<div class="platform-notification-empty">لا توجد تنبيهات.</div>';}
async function refreshPlatformNotificationInbox(){try{var data=await listPlatformNotifications(50);renderPlatformNotificationInbox(data);return data;}catch(error){var status=document.getElementById('platform-notifications-status');if(status)status.textContent='تعذر التحديث';return null;}}
function closePlatformNotificationPanel(){var panel=document.getElementById('platform-notifications-panel'),bell=document.getElementById('platform-notifications-inbox');if(panel)panel.hidden=true;if(bell)bell.setAttribute('aria-expanded','false');}
document.addEventListener('click',function(event){var bell=event.target&&event.target.closest?event.target.closest('#platform-notifications-inbox'):null;if(bell){var panel=document.getElementById('platform-notifications-panel'),open=panel&&panel.hidden;if(panel)panel.hidden=!open;bell.setAttribute('aria-expanded',open?'true':'false');if(open)refreshPlatformNotificationInbox();return;}var item=event.target&&event.target.closest?event.target.closest('[data-platform-notification-id]'):null;if(item){var url=item.getAttribute('data-platform-notification-url');closePlatformNotificationPanel();markPlatformNotificationRead(item.getAttribute('data-platform-notification-id')).then(function(){return refreshPlatformNotificationInbox();}).then(function(){if(url)window.location.href=url;});return;}var panel=document.getElementById('platform-notifications-panel');if(panel&&!panel.hidden&&!event.target.closest('.platform-notification-center'))closePlatformNotificationPanel();});
window.addEventListener('platform-notification',refreshPlatformNotificationInbox);window.addEventListener('platform-notification-read',refreshPlatformNotificationInbox);
setTimeout(refreshPlatformNotificationInbox,1200);
async function consumePlatformNotificationClick(id){id=String(id||'').trim();if(!id)return false;try{await markPlatformNotificationRead(id);await refreshPlatformNotificationInbox();return true;}catch(error){console.error('Platform notification click read failed',error);return false;}}\nfunction consumePlatformNotificationClickFromUrl(){var url=new URL(window.location.href),id=String(url.searchParams.get('platformNotificationId')||'').trim();if(!id)return;url.searchParams.delete('platformNotificationId');window.history.replaceState(window.history.state,'',url.href);consumePlatformNotificationClick(id);}\nif('serviceWorker' in navigator)navigator.serviceWorker.addEventListener('message',function(event){if(!event.data)return;if(event.data.action==='platformNotification')window.dispatchEvent(new CustomEvent('platform-notification',{detail:event.data}));if(event.data.action==='platformNotificationClick')consumePlatformNotificationClick(event.data.notificationEventId);});\nsetTimeout(consumePlatformNotificationClickFromUrl,1200);
function renderPlatformNotificationState(state){var button=document.getElementById('platform-notifications-enable');if(!button)return;var enabled=!!(state&&state.enabled&&state.browserSubscribed&&state.serverRegistered);button.textContent=enabled?'التنبيهات مفعلة':'تفعيل التنبيهات';button.disabled=enabled;button.setAttribute('aria-pressed',enabled?'true':'false');}\nasync function refreshPlatformNotificationState(){try{var state=await platformNotificationState();renderPlatformNotificationState(state);return state;}catch(error){console.error('Platform notification state refresh failed',error);renderPlatformNotificationState(null);return null;}}\nsetTimeout(refreshPlatformNotificationState,1400);\ndocument.addEventListener('visibilitychange',function(){if(document.visibilityState==='visible')refreshPlatformNotificationState();});\ndocument.addEventListener('click',function(event){var button=event.target&&event.target.closest?event.target.closest('#platform-notifications-enable'):null;if(!button||button.disabled)return;button.disabled=true;var original=button.textContent;button.textContent='جارٍ التفعيل…';enablePlatformNotifications().then(function(){return refreshPlatformNotificationState();}).catch(function(error){console.error('Platform notification opt-in failed',error);button.textContent=original;button.disabled=false;window.alert('تعذر تفعيل التنبيهات: '+String(error&&error.message||'PUSH_ACTIVATION_FAILED'));});});
})();
