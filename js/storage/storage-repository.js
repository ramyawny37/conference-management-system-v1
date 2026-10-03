(function(global){
  'use strict';

  var localWriteQueue=Promise.resolve();

  function saveAppData(appData,options){
    options=options&&typeof options==='object'?options:{};
    var persistence=global.AppIndexedDB;
    var writeOperation=localWriteQueue.catch(function(){}).then(function(){
      if(!persistence||typeof persistence.saveAppData!=='function'){
        throw Object.assign(new Error('Local persistence is unavailable.'),
          {code:'LOCAL_PERSISTENCE_UNAVAILABLE'});
      }
      return persistence.saveAppData(appData);
    }).then(function(result){
      var templateSync=options.skipTemplateSync?null:global.OrganizationTemplateSync;
      if(templateSync&&typeof templateSync.captureLocalSave==='function'){
        Promise.resolve(templateSync.captureLocalSave(appData)).catch(function(){return null;});
      }
      return {ok:true,status:'persisted',indexedDB:result};
    });
    localWriteQueue=writeOperation;
    return writeOperation;
  }

  function getAppData(){return global.AppIndexedDB.getAppData();}
  function hasAppData(){return global.AppIndexedDB.hasAppData();}
  function createLocalBackup(appData,reason){return global.AppIndexedDB.createLocalBackup(appData,reason);}
  function getLocalBackups(conferenceId){return global.AppIndexedDB.getLocalBackups(conferenceId);}
  function getLocalBackup(backupId){return global.AppIndexedDB.getLocalBackup(backupId);}
  function deleteLocalBackup(backupId){return global.AppIndexedDB.deleteLocalBackup(backupId);}

  global.StorageRepository=Object.freeze({
    saveAppData:saveAppData,
    getAppData:getAppData,
    hasAppData:hasAppData,
    createLocalBackup:createLocalBackup,
    getLocalBackups:getLocalBackups,
    getLocalBackup:getLocalBackup,
    deleteLocalBackup:deleteLocalBackup
  });
})(window);
