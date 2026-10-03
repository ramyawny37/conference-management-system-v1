(function(global){
  'use strict';
  var namespace=global.BrowserStorageNamespace||{key:function(name){return name;}};
  var KEY=namespace.key('conference_manager_canonical_links_v2');
  function copy(value){if(typeof global.structuredClone==='function')return global.structuredClone(value);return JSON.parse(JSON.stringify(value));}
  function target(options){if(options&&options.storage)return options.storage;try{return global.localStorage||null;}catch(error){return null;}}
  function uuid(value){return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value||''));}
  function all(options){try{var value=JSON.parse(target(options).getItem(KEY)||'{}');return value&&typeof value==='object'&&!Array.isArray(value)?value:{};}catch(error){return {};}}
  function write(value,options){try{target(options).setItem(KEY,JSON.stringify(value));return true;}catch(error){return false;}}
  function inspect(options){var value=all(options);var valid=Object.keys(value).every(function(key){var item=value[key];return item&&item.localConferenceId===key&&uuid(item.remoteConferenceId)&&item.linkStatus==='linked';});return valid?{ok:true,status:Object.keys(value).length?'read':'empty',data:copy(value)}:{ok:false,status:'malformed',data:null};}
  function get(localId,options){var value=all(options)[String(localId||'')];return value?copy(value):null;}
  function list(options){var value=all(options);return Object.keys(value).sort().map(function(key){return copy(value[key]);});}
  function findByRemoteId(remoteId,options){remoteId=String(remoteId||'');return list(options).find(function(item){return item.remoteConferenceId===remoteId;})||null;}
  function save(input,options){
    input=input&&typeof input==='object'?input:{};
    var localId=String(input.localConferenceId||''),remoteId=String(input.remoteConferenceId||'');
    if(!localId||!uuid(remoteId)||String(input.linkStatus||'linked')!=='linked')return {ok:false,status:'invalid'};
    var links=all(options);
    if(Object.keys(links).some(function(key){return key!==localId&&links[key].remoteConferenceId===remoteId;}))return {ok:false,status:'remote_already_linked'};
    var previous=links[localId]||{},now=new Date().toISOString();
    links[localId]={localConferenceId:localId,remoteConferenceId:remoteId,remoteName:String(input.remoteName||previous.remoteName||''),linkStatus:'linked',createdAt:previous.createdAt||now,updatedAt:now};
    return write(links,options)?{ok:true,status:'saved',data:copy(links[localId])}:{ok:false,status:'storage_error'};
  }
  function remove(localId,options){var links=all(options);delete links[String(localId||'')];return write(links,options)?{ok:true,status:'removed'}:{ok:false,status:'storage_error'};}
  global.ConferenceLinkStore=Object.freeze({statuses:Object.freeze(['linked']),inspect:inspect,get:get,list:list,findByRemoteId:findByRemoteId,save:save,remove:remove});
})(window);
