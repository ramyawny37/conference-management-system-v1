(function(global){
  'use strict';

  function systemAccess(){
    var service=global.SystemAccessService;
    return service&&typeof service.getState==='function'?service.getState():{};
  }

  function isSystemOwner(){
    var access=systemAccess();
    return access.accountStatus==='approved'&&
      access.fresh===true&&
      access.isSystemOwner===true;
  }

  function canViewConferenceDiagnostics(){
    return isSystemOwner();
  }

  function canExportRescue(){
    return isSystemOwner();
  }

  global.DiagnosticsPrivacyPolicy=Object.freeze({
    isDevelopment:function(){
      return !!(global.BrowserStorageNamespace&&
        global.BrowserStorageNamespace.environment==='development');
    },
    isSystemOwner:isSystemOwner,
    canViewConferenceDiagnostics:canViewConferenceDiagnostics,
    canExportRescue:canExportRescue
  });
})(window);
