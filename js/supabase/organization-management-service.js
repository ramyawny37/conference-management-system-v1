(function(global){
  'use strict';
  function deps(options){options=options||{};return {clientLayer:options.clientLayer||global.SupabaseClientLayer,auth:options.auth||global.SupabaseAuth,identity:options.identity||global.SupabaseDeviceIdentity,deviceSession:options.deviceSession||global.PlatformDeviceSession};}
  function uuid(value){return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value||''));}
  function context(options){var d=deps(options),client=d.clientLayer&&d.clientLayer.getClient&&d.clientLayer.getClient(),session=d.auth&&d.auth.getSession&&d.auth.getSession(),identity=d.identity&&d.identity.getOrCreate&&d.identity.getOrCreate();if(!client||!session||!session.user||!identity||!uuid(identity.id)||!d.deviceSession||typeof d.deviceSession.invokeProtected!=='function')return {error:'unavailable'};return {d:d,userId:String(session.user.id),deviceId:String(identity.id),deviceSession:d.deviceSession};}
  function output(ok,status,data,error){return {ok:ok,status:status,data:data||null,error:error||null};}
  function list(options){var ctx=context(options);if(ctx.error)return Promise.resolve(output(false,'unavailable'));return ctx.deviceSession.invokeProtected('get_organization_management_overview',{}).then(function(value){value=value||{};if(value.status!=='success'||!Array.isArray(value.organizations))return output(false,'malformed');return output(true,'listed',{canCreate:value.canCreate===true,organizations:value.organizations});}).catch(function(error){return output(false,'failed',null,{code:String(error&&error.code||'ORGANIZATION_MANAGEMENT_FAILED')});});}
  global.OrganizationManagementService=Object.freeze({list:list});
})(window);
