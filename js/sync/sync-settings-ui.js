(function(global){
  'use strict';
  var RUNTIME_BUILD_REVISION='debug-binding-report-ui-v2';

  var busy=false;
  var explicitConnectivity='unknown';

  function escapeHtml(value){
    return String(value==null?'':value)
      .replace(/&/g,'&amp;')
      .replace(/</g,'&lt;')
      .replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;')
      .replace(/'/g,'&#39;');
  }

  function getConfigState(){
    var api=global.SupabaseRuntimeConfig;
    return api&&typeof api.getPublicState==='function'
      ?api.getPublicState()
      :{configured:false,url:'',maskedKey:''};
  }

  function getAuthState(){
    var api=global.SupabaseAuth;
    return api&&typeof api.getState==='function'
      ?api.getState()
      :{initialized:false,authenticated:false,user:null};
  }


  function getDevice(){
    var api=global.SupabaseDeviceIdentity;
    try{
      return api&&typeof api.getOrCreate==='function'
        ?api.getOrCreate()
        :null;
    }catch(error){
      return null;
    }
  }

  function shortDeviceId(value){
    var id=String(value||'');
    return id?id.slice(0,8)+'…'+id.slice(-4):'غير متاح';
  }

  function statusBadge(text,positive){
    return '<span class="sync-settings-badge '+
      (positive?'sync-settings-ok':'sync-settings-muted')+'">'+
      escapeHtml(text)+'</span>';
  }
  function renderTemplateDiagnosticExport(){
    return '<section class="settings-section sync-settings-section">'+
      '<div class="settings-section-title">تشخيص القوالب المحلية</div>'+
      '<div class="sync-settings-panel">'+
      '<div class="sync-settings-message">يُصدّر بيانات القوالب وعملياتها فقط دون أي تعديل أو مزامنة.</div>'+
      '<div class="sync-settings-actions"><button type="button" class="btn btn-blue btn-sm" '+
      'onclick="SyncSettingsUI.exportTemplateDiagnostics()">'+
      'تصدير تشخيص القوالب والعمليات</button></div></div></section>';
  }

  function exportTemplateDiagnostics(){
    var service=global.TemplateDiagnosticExport;
    if(!service||typeof service.exportBundle!=='function'){
      if(typeof global.showToast==='function'){
        global.showToast('تعذر تشغيل تصدير تشخيص القوالب.','#E74C3C');
      }
      return Promise.resolve(false);
    }
    return service.exportBundle().then(function(result){
      if(typeof global.showToast==='function'){
        global.showToast('تم تصدير تشخيص القوالب والعمليات: '+result.fileName);
      }
      return result;
    }).catch(function(){
      if(typeof global.showToast==='function'){
        global.showToast('تعذر تصدير تشخيص القوالب.','#E74C3C');
      }
      return false;
    });
  }

  function refreshAccommodationLockDiagnostics(){
    var manager=global.ConferenceEditLockManager;
    if(!manager||typeof manager.refreshDiagnostics!=='function')return Promise.resolve(false);
    return manager.refreshDiagnostics().then(function(result){rerender();return result;});
  }

  function releaseOwnedAccommodationLock(){
    var manager=global.ConferenceEditLockManager;
    if(!manager||typeof manager.endAccommodationEdit!=='function')return Promise.resolve(false);
    var state=manager.getState();
    if(!state.canWrite){message('sync_settings_message','هذا الجهاز لا يملك قفل تعديل التسكين.',true);return Promise.resolve({ok:false,status:'not_owner'});}
    return manager.endAccommodationEdit().then(function(result){
      message('sync_settings_message',result&&result.status==='released'?'تم تحرير قفل التسكين المملوك لهذا الجهاز.':'تعذر تحرير القفل: '+String(result&&result.status||'error'),!(result&&result.status==='released'));
      rerender();return result;
    });
  }

  function renderSection(){
    var config=getConfigState();
    var auth=getAuthState();
    var device=getDevice();
    var identity=global.SupabaseAuth&&
      typeof global.SupabaseAuth.getAccountIdentity==='function'
      ?global.SupabaseAuth.getAccountIdentity()
      :{authenticated:false,displayName:'',email:'',label:''};
    var email=identity.email;
    var accountName=identity.label;
    var html=renderTemplateDiagnosticExport();
    html+='<section class="settings-section sync-settings-section">';
    html+='<div class="settings-section-title">المزامنة والأجهزة</div>';
    html+='<div class="sync-settings-status">';
    html+=statusBadge('الوضع المحلي متاح دائمًا',true);
    html+=statusBadge(config.configured?'Supabase مهيأ':'Supabase غير مهيأ',
      config.configured);
    html+=statusBadge(identity.authenticated?'تم تسجيل الدخول':'غير مسجل',
      identity.authenticated);
    html+=statusBadge(
      explicitConnectivity==='online'?'متصل بالإنترنت':
      explicitConnectivity==='offline'?'غير متصل بالإنترنت':
      'حالة الإنترنت غير محددة',
      explicitConnectivity==='online'
    );
    html+='</div>';
    html+='<div class="sync-settings-grid">';
    html+='<div class="sync-settings-panel"><h3>إعداد الاتصال</h3>';
    html+='<label class="lbl" for="sync_supabase_url">Supabase URL</label>';
    html+='<input id="sync_supabase_url" type="url" dir="ltr" autocomplete="off" value="'+
      escapeHtml(config.url)+'" placeholder="https://project.supabase.co">';
    html+='<label class="lbl" for="sync_supabase_key">Supabase Anon Key</label>';
    html+='<input id="sync_supabase_key" type="password" dir="ltr" autocomplete="new-password" value="" placeholder="'+
      escapeHtml(config.maskedKey||'أدخل المفتاح العام')+'">';
    html+='<label class="lbl" for="sync_auth_redirect_url">Email Redirect URL</label>';
    html+='<input id="sync_auth_redirect_url" type="url" dir="ltr" autocomplete="off" value="'+
      escapeHtml(config.emailRedirectTo||'')+'" placeholder="'+
      escapeHtml(global.location&&global.location.origin||'https://example.com')+'">';
    html+='<div class="sync-settings-actions"><button class="btn btn-green btn-sm" onclick="SyncSettingsUI.saveRuntimeConfig()">حفظ الإعداد</button>';
    html+='<button class="btn btn-gray btn-sm" onclick="SyncSettingsUI.clearRuntimeConfig()">إزالة الإعداد</button></div>';
    html+='<div id="sync_config_message" class="sync-settings-message"></div></div>';
    html+='<div id="sync_account_panel" class="sync-settings-panel"><h3>الحساب</h3>';
    if(identity.authenticated){
      html+='<div class="sync-settings-user sync-settings-account-identity">'+
        '<div class="sync-settings-account-name">'+escapeHtml(accountName)+'</div>'+
        (email&&email!==accountName
          ?'<div class="sync-settings-account-email" dir="ltr">'+escapeHtml(email)+'</div>'
          :'')+
        '</div>';
      html+='<button class="btn btn-red btn-sm" onclick="SyncSettingsUI.signOut()">تسجيل الخروج</button>';
    }else{
      html+='<div class="sync-auth-landing"><div class="sync-auth-card"><h4>تسجيل الدخول</h4>';
      html+='<label class="lbl" for="sync_auth_email">البريد الإلكتروني</label>';
      html+='<input id="sync_auth_email" type="email" dir="ltr" autocomplete="username">';
      html+='<label class="lbl" for="sync_auth_password">كلمة المرور</label>';
      html+='<input id="sync_auth_password" type="password" dir="ltr" autocomplete="current-password">';
      html+='<button class="btn btn-blue btn-sm" onclick="SyncSettingsUI.signIn()">تسجيل الدخول</button></div>';
      html+='<div class="sync-auth-card"><h4>إنشاء حساب جديد</h4>';
      html+='<label class="lbl" for="sync_signup_display_name">الاسم الظاهر</label><input id="sync_signup_display_name" type="text" maxlength="120" autocomplete="name">';
      html+='<label class="lbl" for="sync_signup_email">البريد الإلكتروني</label><input id="sync_signup_email" type="email" dir="ltr" autocomplete="email">';
      html+='<label class="lbl" for="sync_signup_password">كلمة المرور</label><input id="sync_signup_password" type="password" dir="ltr" autocomplete="new-password">';
      html+='<label class="lbl" for="sync_signup_password_confirm">تأكيد كلمة المرور</label><input id="sync_signup_password_confirm" type="password" dir="ltr" autocomplete="new-password">';
      html+='<button class="btn btn-purple btn-sm" onclick="SyncSettingsUI.signUp()">إنشاء الحساب</button></div></div>';
      html+='<div class="sync-settings-actions">';
      html+='<button class="btn btn-gray btn-sm" onclick="SyncSettingsUI.refreshAuthState()">قراءة حالة الحساب</button></div>';
    }
    html+='<div id="sync_auth_message" class="sync-settings-message" '+
      'aria-live="polite" aria-atomic="true"></div>';
    html+='<pre id="sync_signup_diagnostics" class="sync-settings-message" '+
      'dir="ltr" style="display:none;white-space:pre-wrap"></pre></div>';
    html+='<div class="sync-settings-panel"><h3>هذا الجهاز</h3>';
    html+='<div class="sync-settings-device-id">Device ID: <strong dir="ltr">'+
      escapeHtml(shortDeviceId(device&&device.id))+'</strong></div>';
    html+='<label class="lbl" for="sync_device_name">اسم الجهاز المحلي</label>';
    html+='<input id="sync_device_name" type="text" maxlength="80" value="'+
      escapeHtml(device&&device.deviceName||'')+'" placeholder="جهاز المكتب">';
    html+='<button class="btn btn-green btn-sm" onclick="SyncSettingsUI.saveDeviceName()">حفظ اسم الجهاز</button>';
    html+='<div id="sync_device_message" class="sync-settings-message"></div></div>';
    html+='</div>';
    html+='</section>';
    return html;
  }

  function element(id){
    return global.document?global.document.getElementById(id):null;
  }

  function authMessageTarget(){
    var gateState=global.StartupAccessGate&&
      typeof global.StartupAccessGate.getState==='function'
      ?global.StartupAccessGate.getState():null;
    var gate=element('startupAccessGate');
    var target=null;
    if(gateState&&gateState.gateState==='auth'&&gate&&
      typeof gate.querySelector==='function'){
      target=gate.querySelector('#sync_auth_message');
      if(target)return target;
    }
    var settings=element('tab6');
    var settingsSection=settings&&
      typeof settings.querySelector==='function'
      ?settings.querySelector('.sync-settings-section'):null;
    if(settingsSection&&typeof settingsSection.querySelector==='function'){
      target=settingsSection.querySelector('#sync_auth_message');
      if(target)return target;
    }
    return element('sync_auth_message');
  }

  function message(id,text,isError){
    var target=id==='sync_auth_message'?authMessageTarget():element(id);
    if(!target)return;
    target.textContent=text||'';
    target.className='sync-settings-message'+
      (isError?' sync-settings-error':' sync-settings-success');
  }

  function safeAuthErrorCode(value){
    var code=String(value||'').trim();
    return /^[A-Za-z0-9_.-]{1,80}$/.test(code)?code:'';
  }

  function showSignUpDiagnostics(diagnostic){
    var target=element('sync_signup_diagnostics');
    if(!target)return;
    if(!diagnostic||diagnostic.authStage!=='AUTH_SIGNUP_FAILED'){
      target.textContent='';
      if(target.style)target.style.display='none';
      return;
    }
    target.textContent=JSON.stringify({
      authStage:String(diagnostic.authStage||''),
      success:diagnostic.success===true,
      errorCode:safeAuthErrorCode(diagnostic.errorCode)||null,
      httpStatus:diagnostic.httpStatus==null
        ?null:String(diagnostic.httpStatus),
      sanitizedMessage:String(diagnostic.sanitizedMessage||''),
      userPresent:diagnostic.userPresent===true,
      sessionPresent:diagnostic.sessionPresent===true,
      timestamp:String(diagnostic.timestamp||'')
    },null,2);
    if(target.style)target.style.display='block';
  }

  function rerender(){
    if(typeof global.renderSettings==='function')global.renderSettings();
  }

  function refreshAccountIdentity(){
    if(element('sync_account_panel'))rerender();
  }
  function clearStartupAuthDraft(){
    if(global.StartupAccessGate&&
      typeof global.StartupAccessGate.clearAuthDraft==='function'){
      global.StartupAccessGate.clearAuthDraft();
    }
  }

  function applyStartupAuthBusyState(){
    if(!global.document||
      typeof global.document.querySelectorAll!=='function')return;
    var startupAuthButtons=global.document.querySelectorAll(
      '#startupAccessGate .startup-auth-submit'
    );
    Array.prototype.forEach.call(startupAuthButtons,function(button){
      button.disabled=busy;
      if(busy){
        button.setAttribute('aria-busy','true');
        button.classList.add('is-loading');
      }else{
        button.removeAttribute('aria-busy');
        button.classList.remove('is-loading');
      }
    });
    var startupAuthNavigation=global.document.querySelectorAll(
      '#startupAccessGate .startup-auth-navigation'
    );
    Array.prototype.forEach.call(startupAuthNavigation,function(button){
      button.disabled=busy;
    });
  }

  function setBusy(value){
    busy=!!value;
    if(!global.document||
      typeof global.document.querySelectorAll!=='function')return;
    var buttons=global.document.querySelectorAll(
      '.sync-settings-section button'
    );
    Array.prototype.forEach.call(buttons,function(button){
      button.disabled=busy;
    });
    applyStartupAuthBusyState();
  }

  function saveRuntimeConfig(){
    var url=element('sync_supabase_url');
    var key=element('sync_supabase_key');
    var redirect=element('sync_auth_redirect_url');
    var api=global.SupabaseRuntimeConfig;
    if(!api||busy)return;
    var result=api.save({
      url:url&&url.value,
      publishableKey:key&&key.value,
      emailRedirectTo:redirect&&redirect.value
    });
    if(!result.ok){
      message('sync_config_message',
        result.errors.indexOf('SUPABASE_SERVICE_ROLE_KEY_REJECTED')>=0
          ?'تم رفض المفتاح السري. استخدم Anon Key فقط.'
          :'إعداد الاتصال غير صالح.',
        true);
      return;
    }
    api.configureClient();
    if(key)key.value='';
    rerender();
  }

  function clearRuntimeConfig(){
    if(busy||!global.SupabaseRuntimeConfig)return;
    global.SupabaseRuntimeConfig.clear();
    rerender();
  }

  function authFields(){
    return {
      email:String(element('sync_auth_email')&&
        element('sync_auth_email').value||'').trim(),
      password:String(element('sync_auth_password')&&
        element('sync_auth_password').value||'')
    };
  }

  function signUpFields(){return {displayName:String(element('sync_signup_display_name')&&element('sync_signup_display_name').value||'').trim(),email:String(element('sync_signup_email')&&element('sync_signup_email').value||'').trim().toLowerCase(),password:String(element('sync_signup_password')&&element('sync_signup_password').value||''),confirmation:String(element('sync_signup_password_confirm')&&element('sync_signup_password_confirm').value||'')};}
  function validEmail(value){return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);}
  function validateSignIn(fields){
    if(!fields.email)return 'أدخل البريد الإلكتروني.';
    if(!validEmail(fields.email))return 'أدخل بريدًا إلكترونيًا صحيحًا.';
    if(!fields.password)return 'أدخل كلمة المرور.';
    return '';
  }
  function validateSignUp(fields){if(fields.displayName.length<2)return 'أدخل الاسم الظاهر بشكل صحيح.';if(!validEmail(fields.email))return 'أدخل بريدًا إلكترونيًا صحيحًا.';if(fields.password.length<8)return 'يجب ألا تقل كلمة المرور عن 8 أحرف.';if(fields.password!==fields.confirmation)return 'كلمتا المرور غير متطابقتين.';return '';}

  function safeAuthMessage(result,successText,action){
    if(result&&result.success)return successText;
    var code=result&&result.error&&result.error.code;
    if(code==='ACTIVE_AUTH_SESSION'){
      return 'يجب تسجيل الخروج أولًا قبل تبديل الحساب.';
    }
    if(code==='SUPABASE_AUTH_UNAVAILABLE'){
      return 'خدمة تسجيل الدخول غير مهيأة.';
    }
    if(code==='invalid_credentials'||code==='invalid_grant')return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    if(code==='email_not_confirmed')return 'يجب تأكيد البريد الإلكتروني أولًا.';
    if(code==='user_already_exists'||code==='email_exists')return 'يوجد حساب مسجل بهذا البريد الإلكتروني.';
    if(code==='weak_password')return 'كلمة المرور غير قوية بما يكفي.';
    code=safeAuthErrorCode(code);
    if(action==='signup')return code?
      'تعذر إنشاء الحساب. رمز الخطأ: '+code:
      'تعذر إنشاء الحساب. يرجى مراجعة تشخيص التسجيل.';
    return 'تعذر إكمال الطلب. تحقق من البيانات والاتصال.';
  }

  function prepareAuth(){
    var config=global.SupabaseRuntimeConfig;
    if(!config)return Promise.resolve(false);
    var configured=config.configureClient();
    if(!configured.available)return Promise.resolve(false);
    return global.SupabaseAuth.initialize().then(function(){return true;});
  }

  function authenticationAllowedAfterInitialization(){
    var auth=global.SupabaseAuth;
    return !(auth&&typeof auth.getAccountIdentity==='function'&&
      auth.getAccountIdentity().authenticated);
  }

  function runAuth(action,successText){
    if(busy)return;
    var fields=authFields();
    var validation=validateSignIn(fields);
    if(validation){message('sync_auth_message',validation,true);return;}
    setBusy(true);
    var passwordElement=element('sync_auth_password');
    prepareAuth().then(function(ready){
      if(!ready)return {success:false,error:{code:'SUPABASE_AUTH_UNAVAILABLE'}};
      if(!authenticationAllowedAfterInitialization()){
        return {success:false,error:{code:'ACTIVE_AUTH_SESSION'}};
      }
      return action(fields.email,fields.password);
    }).then(function(result){
      if(passwordElement)passwordElement.value='';
      if(result&&result.success){
        clearStartupAuthDraft();
        rerender();
        return global.StartupAccessGate&&typeof global.StartupAccessGate.evaluate==='function'
          ?global.StartupAccessGate.evaluate():null;
      }else{
        message('sync_auth_message',safeAuthMessage(result,successText),true);
      }
    }).catch(function(){
      message('sync_auth_message','تعذر إكمال الطلب بأمان.',true);
    }).then(function(){setBusy(false);});
  }

  function signIn(){
    runAuth(function(email,password){
      return global.SupabaseAuth.signInWithPassword(email,password);
    },'تم تسجيل الدخول.');
  }

  function signUp(){
    if(busy)return;
    setBusy(true);
    var fields=signUpFields(),validation=validateSignUp(fields);
    if(validation){message('sync_auth_message',validation,true);setBusy(false);return;}
    var displayNameElement=element('sync_signup_display_name');
    var emailElement=element('sync_signup_email');
    var passwordElement=element('sync_signup_password');
    var confirmationElement=element('sync_signup_password_confirm');
    prepareAuth().then(function(ready){
      if(!ready)return {success:false,error:{code:'SUPABASE_AUTH_UNAVAILABLE'}};
      if(!authenticationAllowedAfterInitialization()){
        return {success:false,error:{code:'ACTIVE_AUTH_SESSION'}};
      }
      return global.SupabaseAuth.signUp(fields.email,fields.password,{display_name:fields.displayName});
    }).then(function(result){
      if(passwordElement)passwordElement.value='';
      if(confirmationElement)confirmationElement.value='';
      if(!result||!result.success){
        message('sync_auth_message',safeAuthMessage(result,'','signup'),true);
        showSignUpDiagnostics(result&&result.diagnostics);
        return;
      }
      clearStartupAuthDraft();
      showSignUpDiagnostics(null);
      var session=result.data&&result.data.session;
      if(session){
        rerender();
        return;
      }
      if(displayNameElement)displayNameElement.value='';
      if(emailElement)emailElement.value='';
      message(
        'sync_auth_message',
        'تم إنشاء الحساب بنجاح. راجع بريدك لتأكيده، ثم سجل الدخول وانتظر اعتماد مسؤول النظام.',
        false
      );
    }).catch(function(){
      message('sync_auth_message','تعذر إكمال الطلب بأمان.',true);
    }).then(function(){setBusy(false);});
  }

  function signOut(){
    if(global.PlatformDeviceSession&&typeof global.PlatformDeviceSession.clear==='function')global.PlatformDeviceSession.clear();
    if(busy||!global.SupabaseAuth)return;
    setBusy(true);
    var editLockCleanup=global.ConferenceEditLockManager&&
      typeof global.ConferenceEditLockManager.release==='function'
      ?Promise.resolve(global.ConferenceEditLockManager.release())
        .catch(function(){return {ok:false,status:'release_failed_expiry_pending'};})
      :Promise.resolve();
    Promise.resolve(editLockCleanup).then(function(){
      return global.SupabaseAuth.signOut();
    }).then(function(result){
      if(result&&result.success){
        var platformLogout=global.PlatformIntegration&&
          typeof global.PlatformIntegration.logout==='function'
          ?global.PlatformIntegration.logout():Promise.resolve();
        return Promise.resolve(platformLogout).then(function(){
          clearStartupAuthDraft();
          rerender();
        });
      }
      else message('sync_auth_message','تعذر تسجيل الخروج.',true);
    }).catch(function(){
      message('sync_auth_message','تعذر تسجيل الخروج بأمان.',true);
    }).then(function(){setBusy(false);});
  }

  function refreshAuthState(){
    if(busy)return;
    setBusy(true);
    prepareAuth().then(function(ready){
      if(ready)rerender();
      else message('sync_auth_message','خدمة تسجيل الدخول غير مهيأة.',true);
    }).catch(function(){
      message('sync_auth_message','تعذر قراءة حالة الحساب بأمان.',true);
    }).then(function(){setBusy(false);});
  }

  function saveDeviceName(){
    var input=element('sync_device_name');
    var api=global.SupabaseDeviceIdentity;
    if(!api||typeof api.setDeviceName!=='function')return;
    var result=api.setDeviceName(input&&input.value);
    message('sync_device_message',
      result.success?'تم حفظ اسم الجهاز محليًا.':'تعذر حفظ اسم الجهاز.',
      !result.success);
  }

  function setConnectivity(value){
    explicitConnectivity=value==='online'||value==='offline'
      ?value
      :'unknown';
    rerender();
  }

  function getState(){
    return {
      busy:busy,
      connectivity:explicitConnectivity,
      configured:getConfigState().configured,
      authenticated:getAuthState().authenticated
    };
  }

  global.SyncSettingsUI=Object.freeze({
    renderSection:renderSection,
    refreshAccountIdentity:refreshAccountIdentity,
    saveRuntimeConfig:saveRuntimeConfig,
    clearRuntimeConfig:clearRuntimeConfig,
    signIn:signIn,
    signUp:signUp,
    signOut:signOut,
    refreshAuthState:refreshAuthState,
    saveDeviceName:saveDeviceName,
    exportTemplateDiagnostics:exportTemplateDiagnostics,
    refreshAccommodationLockDiagnostics:refreshAccommodationLockDiagnostics,
    releaseOwnedAccommodationLock:releaseOwnedAccommodationLock,
    setConnectivity:setConnectivity,
    applyStartupAuthBusyState:applyStartupAuthBusyState,
    getState:getState
  });
})(window);
