(function(global){
  'use strict';
  function output(ok,status,data,error){return {ok:ok,status:status,data:data||null,error:error||null};}
  function listAccessibleConferences(){
    var session=global.PlatformDeviceSession;
    if(!session||typeof session.invokeModuleProtected!=='function'){
      return Promise.resolve(output(false,'unavailable',null,{code:'DEVICE_SESSION_RUNTIME_REQUIRED'}));
    }
    return Promise.resolve(session.invokeModuleProtected(
      'conference','list_accessible_conferences',{}
    )).then(function(response){
      var rows=response&&Array.isArray(response.conferences)?response.conferences:[];
      var conferences=rows.filter(function(item){return item&&item.conferenceId;}).map(function(item){return {
        id:item.conferenceId,organizationId:item.organizationId||null,name:item.name,
        startDate:item.startDate||null,endDate:item.endDate||null,status:item.status,
        completedAt:item.completedAt||null,revision:item.revision,
        createdAt:item.createdAt,updatedAt:item.updatedAt
      };});
      return output(true,'listed',{conferences:conferences});
    }).catch(function(error){return output(false,'failed',null,{code:String(error&&error.code||'CANONICAL_CONFERENCE_DISCOVERY_FAILED')});});
  }
  global.CanonicalConferenceDiscovery=Object.freeze({listAccessibleConferences:listAccessibleConferences});
})(window);
