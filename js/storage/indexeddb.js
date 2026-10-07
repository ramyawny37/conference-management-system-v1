(function(global){
  'use strict';

  var namespace=global.BrowserStorageNamespace||{
    databaseName:function(name){return name;}
  };
  var DATABASE_NAME = namespace.databaseName(
    'conference_manager_v3'
  );
  var DATABASE_VERSION = 8;
  var STORE_NAMES = Object.freeze({
    conferences: 'conferences',
    rooms: 'rooms',
    deviceSettings: 'device_settings',
    localBackups: 'local_backups',
    libraryTemplateContentOperations:
      'library_template_content_operations',
  });
  var database = null;
  var openingPromise = null;

  function requestToPromise(request){
    return new Promise(function(resolve,reject){
      request.onsuccess = function(){ resolve(request.result); };
      request.onerror = function(){ reject(request.error); };
    });
  }

  function ensureIndex(store,indexName,keyPath,options){
    if(!store.indexNames.contains(indexName)){
      store.createIndex(indexName,keyPath,options||{});
    }
  }

  function ensureStore(db,upgradeTransaction,name,options,indexes){
    var store = db.objectStoreNames.contains(name)
      ? upgradeTransaction.objectStore(name)
      : db.createObjectStore(name,options);
    (indexes||[]).forEach(function(index){
      ensureIndex(store,index.name,index.keyPath,index.options);
    });
  }

  function upgradeDatabase(db,upgradeTransaction){
    [
      'organization_membership_pending_operations',
      'organization_template_operations',
      'organization_template_access_operations'
    ].forEach(function(name){
      if(db.objectStoreNames.contains(name))db.deleteObjectStore(name);
    });
    ensureStore(db,upgradeTransaction,STORE_NAMES.conferences,{keyPath:'conferenceId'});
    ensureStore(db,upgradeTransaction,STORE_NAMES.rooms,{keyPath:['conferenceId','roomId']});
    ensureStore(db,upgradeTransaction,STORE_NAMES.deviceSettings,{keyPath:'key'});
    ensureStore(db,upgradeTransaction,STORE_NAMES.localBackups,{keyPath:'backupId'},[
      {name:'conferenceId',keyPath:'conferenceId'},
      {name:'conferenceCreatedAt',keyPath:['conferenceId','createdAt']}
    ]);
    ensureStore(db,upgradeTransaction,
      STORE_NAMES.libraryTemplateContentOperations,
      {keyPath:'operationId'},[
        {name:'by_status',keyPath:'status'},
        {name:'by_template',keyPath:['templateType','templateId']},
        {name:'by_created_at',keyPath:'createdAt'}
      ]);
  }

  function openDatabase(){
    if(database)return Promise.resolve(database);
    if(openingPromise)return openingPromise;
    if(!global.indexedDB)return Promise.reject(new Error('INDEXEDDB_UNAVAILABLE'));

    openingPromise = new Promise(function(resolve,reject){
      var request = global.indexedDB.open(DATABASE_NAME,DATABASE_VERSION);
      request.onupgradeneeded = function(event){
        upgradeDatabase(event.target.result,event.target.transaction);
      };
      request.onsuccess = function(){
        database = request.result;
        database.onversionchange = function(){ closeDatabase(); };
        openingPromise = null;
        resolve(database);
      };
      request.onerror = function(){
        openingPromise = null;
        reject(request.error);
      };
      request.onblocked = function(){
        openingPromise = null;
        reject(new Error('INDEXEDDB_OPEN_BLOCKED'));
      };
    });
    return openingPromise;
  }

  function closeDatabase(){
    if(database)database.close();
    database = null;
    openingPromise = null;
  }

  function runTransaction(storeNames,mode,executor){
    var names = Array.isArray(storeNames) ? storeNames : [storeNames];
    return openDatabase().then(function(db){
      return new Promise(function(resolve,reject){
        var transaction;
        try{
          transaction = db.transaction(names,mode||'readonly');
        }catch(error){
          reject(error);
          return;
        }
        var stores = {};
        names.forEach(function(name){ stores[name] = transaction.objectStore(name); });
        var result;
        try{
          result = executor(stores,transaction);
        }catch(error){
          try{ transaction.abort(); }catch(abortError){}
          reject(error);
          return;
        }
        transaction.oncomplete = function(){ resolve(result); };
        transaction.onerror = function(){ reject(transaction.error); };
        transaction.onabort = function(){ reject(transaction.error||new Error('INDEXEDDB_TRANSACTION_ABORTED')); };
      });
    });
  }

  function getRecord(storeName,key){
    return openDatabase().then(function(db){
      return requestToPromise(db.transaction(storeName,'readonly').objectStore(storeName).get(key));
    });
  }

  function getAllRecords(storeName){
    return openDatabase().then(function(db){
      return requestToPromise(db.transaction(storeName,'readonly').objectStore(storeName).getAll());
    });
  }

  function putRecord(storeName,value){
    return runTransaction(storeName,'readwrite',function(stores){
      return requestToPromise(stores[storeName].put(value));
    });
  }

  function deleteRecord(storeName,key){
    return runTransaction(storeName,'readwrite',function(stores){
      return requestToPromise(stores[storeName].delete(key));
    });
  }

  function clearStore(storeName){
    return runTransaction(storeName,'readwrite',function(stores){
      return requestToPromise(stores[storeName].clear());
    });
  }

  function serializeAppData(appData){
    try{
      var serialized=JSON.stringify(appData);
      if(typeof serialized!=='string')throw new Error('NOT_SERIALIZABLE');
      return {data:JSON.parse(serialized),sizeBytes:calculateUtf8Size(serialized)};
    }catch(error){
      throw Object.assign(new Error('Application data could not be serialized.'),
        {code:'LOCAL_PERSISTENCE_SERIALIZATION_FAILED'});
    }
  }

  function isQuotaExceededError(error){
    var current=error;
    for(var depth=0;current&&depth<4;depth++){
      if(current.name==='QuotaExceededError'||current.code===22||current.code===1014)return true;
      current=current.cause;
    }
    return false;
  }

  function saveAppData(appData){
    var serialized;
    try{serialized=serializeAppData(appData);}catch(error){return Promise.reject(error);}
    return putRecord(STORE_NAMES.conferences,{
      conferenceId:'**app_data**',
      data:serialized.data,
      schemaVersion:serialized.data&&serialized.data.version?serialized.data.version:'',
      appVersion: global.APP_RELEASE&&global.APP_RELEASE.version?global.APP_RELEASE.version:'',
      savedAt: new Date().toISOString(),
      source:'indexeddb',
      sizeBytes:serialized.sizeBytes
    }).catch(function(error){
      if(isQuotaExceededError(error)){
        var quotaError=new Error('Local storage quota prevented saving application data.');
        quotaError.code='LOCAL_STORAGE_QUOTA_EXCEEDED';
        quotaError.sizeBytes=serialized.sizeBytes;
        throw quotaError;
      }
      throw error;
    });
  }

  function validateAppDataRecord(record){
    if(!record||typeof record!=='object'||Array.isArray(record)||!Object.keys(record).length){
      return {valid:false,reason:'APP_DATA_EMPTY'};
    }
    if(!record.data||typeof record.data!=='object'||Array.isArray(record.data)||!Object.keys(record.data).length){
      return {valid:false,reason:'APP_DATA_MISSING'};
    }
    if(!Object.prototype.hasOwnProperty.call(record.data,'conferences')){
      return {valid:false,reason:'APP_DATA_CONFERENCES_MISSING'};
    }
    if(!Array.isArray(record.data.conferences)){
      return {valid:false,reason:'APP_DATA_CONFERENCES_INVALID'};
    }
    if(!Object.prototype.hasOwnProperty.call(record.data,'currentConferenceId')){
      return {valid:false,reason:'APP_DATA_CURRENT_CONFERENCE_ID_MISSING'};
    }
    return {valid:true,reason:''};
  }

  function getAppData(){
    return getRecord(STORE_NAMES.conferences,'**app_data**');
  }

  function hasAppData(){
    return getAppData().then(function(record){
      return validateAppDataRecord(record).valid;
    });
  }

  function createBackupId(){
    if(global.crypto&&typeof global.crypto.randomUUID==='function'){
      return global.crypto.randomUUID();
    }
    if(global.crypto&&typeof global.crypto.getRandomValues==='function'){
      var bytes = new Uint8Array(16);
      global.crypto.getRandomValues(bytes);
      bytes[6] = (bytes[6]&15)|64;
      bytes[8] = (bytes[8]&63)|128;
      return Array.prototype.map.call(bytes,function(byte,index){
        var value = byte.toString(16).padStart(2,'0');
        return index===4||index===6||index===8||index===10?'-'+value:value;
      }).join('');
    }
    throw new Error('SECURE_UUID_UNAVAILABLE');
  }

  function calculateUtf8Size(json){
    if(typeof global.TextEncoder==='function'){
      return new global.TextEncoder().encode(json).byteLength;
    }
    return unescape(encodeURIComponent(json)).length;
  }

  function getLocalBackups(conferenceId){
    return openDatabase().then(function(db){
      var store = db.transaction(STORE_NAMES.localBackups,'readonly').objectStore(STORE_NAMES.localBackups);
      return requestToPromise(store.index('conferenceId').getAll(conferenceId||'**all**'));
    }).then(function(backups){
      return backups.sort(function(first,second){
        return second.createdAt.localeCompare(first.createdAt);
      });
    }).catch(function(error){
      console.warn('تعذر قراءة النسخ الاحتياطية المحلية من IndexedDB.',error);
      return [];
    });
  }

  function getLocalBackup(backupId){
    return getRecord(STORE_NAMES.localBackups,backupId).catch(function(error){
      console.warn('تعذر قراءة النسخة الاحتياطية المحلية من IndexedDB.',error);
      return null;
    });
  }

  function deleteLocalBackup(backupId){
    return deleteRecord(STORE_NAMES.localBackups,backupId).then(function(){
      return true;
    }).catch(function(error){
      console.warn('تعذر حذف النسخة الاحتياطية المحلية من IndexedDB.',error);
      return false;
    });
  }

  function pruneLocalBackups(conferenceId,maxBackups){
    var limit = Number.isInteger(maxBackups)&&maxBackups>=0?maxBackups:10;
    return getLocalBackups(conferenceId).then(function(backups){
      var obsoleteBackups = backups.slice(limit);
      return Promise.all(obsoleteBackups.map(function(backup){
        return deleteLocalBackup(backup.backupId);
      })).then(function(results){
        return results.every(function(result){ return result; });
      });
    }).catch(function(error){
      console.warn('تعذر تقليم النسخ الاحتياطية المحلية في IndexedDB.',error);
      return false;
    });
  }

  function createLocalBackup(appData,reason){
    try{
      var dataJson=JSON.stringify(appData);
      var data=JSON.parse(dataJson);
      var conferenceId=data.currentConferenceId||'**all**';
      var backup = {
        backupId: createBackupId(),
        conferenceId: conferenceId,
        createdAt: new Date().toISOString(),
        reason: typeof reason==='string'?reason:'',
        schemaVersion:data.version||'',
        appVersion: global.APP_RELEASE&&global.APP_RELEASE.version?global.APP_RELEASE.version:'',
        data:data,
        sizeBytes:calculateUtf8Size(dataJson)
      };
      return putRecord(STORE_NAMES.localBackups,backup).then(function(){
        return pruneLocalBackups(conferenceId,10);
      }).then(function(pruned){
        return pruned?backup:false;
      }).catch(function(error){
        console.warn('تعذر إنشاء النسخة الاحتياطية المحلية في IndexedDB.',error);
        return false;
      });
    }catch(error){
      console.warn('تعذر تجهيز النسخة الاحتياطية المحلية.',error);
      return Promise.resolve(false);
    }
  }

  global.AppIndexedDB = Object.freeze({
    databaseName: DATABASE_NAME,
    databaseVersion: DATABASE_VERSION,
    stores: STORE_NAMES,
    openDatabase: openDatabase,
    closeDatabase: closeDatabase,
    runTransaction: runTransaction,
    getRecord: getRecord,
    getAllRecords: getAllRecords,
    putRecord: putRecord,
    deleteRecord: deleteRecord,
    clearStore: clearStore,
    saveAppData:saveAppData,
    getAppData:getAppData,
    hasAppData:hasAppData,
    validateAppDataRecord:validateAppDataRecord,
    createLocalBackup: createLocalBackup,
    getLocalBackups: getLocalBackups,
    getLocalBackup: getLocalBackup,
    deleteLocalBackup: deleteLocalBackup,
    pruneLocalBackups: pruneLocalBackups
  });
})(window);
