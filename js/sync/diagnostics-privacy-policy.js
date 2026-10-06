(function(global){
  'use strict';

  function platformCapabilities(){
    var service=global.UserManagementReadService;
    return service&&typeof service.getCachedActorCapabilities==='function'?
      service.getCachedActorCapabilities():null;
  }

  function isSystemOwner(){
    var capabilities=platformCapabilities();
    return !!(capabilities&&capabilities.canManageAccount===true);
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
