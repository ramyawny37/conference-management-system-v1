(function(global){
  'use strict';
  // P6C1 compatibility shell. The former role-derived resolver/shadow gate
  // must never grant or block runtime mutations; canonical platform guards own authorization.
  function deniedResult(handler){
    return Object.freeze({handler:handler||null,scope:null,section:null,action:null,
      role:null,allowed:false,enforcementEnabled:false,shouldProceed:true,status:'retired'});
  }
  global.ConferencePermissionResolver=Object.freeze({
    enforcementEnabled:false,
    can:function(){return false;},
    require:function(){return false;},
    canConference:function(){return false;},
    requireConference:function(){return false;},
    resolveHandler:function(handler){return deniedResult(handler);},
    getDiagnostics:function(){return [];},
    resetDiagnostics:function(){}
  });
  global.ConferencePermissionShadowGate=function(){return true;};
})(window);
