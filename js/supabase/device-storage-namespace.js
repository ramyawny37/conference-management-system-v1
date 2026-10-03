(function(global){
  'use strict';

  var DATABASE_PREFIX='platform-device-ownership-v1';

  function projectRefFromUrl(value){
    try{
      var host=new URL(String(value||'')).hostname.toLowerCase();
      var match=host.match(/^([a-z0-9]{20})\.supabase\.co$/);
      return match?match[1]:'';
    }catch(error){
      return '';
    }
  }

  function projectRef(){
    var config=global.SUPABASE_RUNTIME_CONFIG||{};
    return projectRefFromUrl(config.url);
  }

  function requireProjectRef(){
    var value=projectRef();
    if(!value)throw new Error('SUPABASE_PROJECT_IDENTITY_REQUIRED');
    return value;
  }

  function databaseName(){
    return DATABASE_PREFIX+':'+requireProjectRef();
  }

  function identityKey(userId){
    return 'device-identity:'+requireProjectRef()+':'+String(userId||'');
  }

  global.PlatformDeviceStorageNamespace=Object.freeze({
    projectRefFromUrl:projectRefFromUrl,
    projectRef:projectRef,
    databaseName:databaseName,
    identityKey:identityKey
  });
})(window);
