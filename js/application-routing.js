(function(global){
  'use strict';

  var document=global.document;
  var script=document&&document.currentScript;
  var source=script&&script.src;
  var location=global.location;
  var baseUrl=null;
  var conferenceTabNames=[
    'accommodation','transportation','accounts','reports','cards','search','settings'
  ];

  try{
    baseUrl=new URL('../',source);
    if(location&&baseUrl.origin!==location.origin)baseUrl=null;
  }catch(error){
    baseUrl=null;
  }

  function requireBase(){
    if(!baseUrl)throw new Error('APPLICATION_BASE_UNAVAILABLE');
    return baseUrl;
  }

  function basePathname(){
    return requireBase().pathname;
  }

  function normalizeLogicalRoute(route){
    route=String(route||'');
    if(!/^\/[a-z][a-z0-9-]*(?:[/?#]|$)/i.test(route)&&route!=='/'){
      throw new Error('APPLICATION_ROUTE_INVALID');
    }
    return route;
  }

  function resolveLogicalRoute(route){
    route=normalizeLogicalRoute(route);
    return requireBase().pathname+(route==='/'?'':'#'+route);
  }

  function logicalPathname(pathname){
    pathname=String(pathname||'');
    var base=basePathname();
    var baseWithoutSlash=base.length>1?base.replace(/\/$/,''):base;
    if(pathname===base||pathname===baseWithoutSlash)return '/';
    if(pathname.indexOf(base)===0)return '/'+pathname.slice(base.length).replace(/^\/+|\/+$/g,'');
    return null;
  }

  function getConferenceRoute(route){
    route=String(route===undefined
      ?(location&&location.hash||'').replace(/^#/,'')
      :route||'/');
    if(route.length>1)route=route.replace(/\/+$/,'');
    if(route==='/conference')return Object.freeze({kind:'home',tabId:null,tabName:null});
    var match=/^\/conference\/app\/([a-z-]+)(?:\/(houses|people))?$/.exec(route);
    if(!match)return route.indexOf('/conference')===0
      ?Object.freeze({kind:'invalid',tabId:null,tabName:null}):null;
    var tabId=conferenceTabNames.indexOf(match[1]);
    return tabId<0||(match[2]&&match[1]!=='settings')?Object.freeze({kind:'invalid',tabId:null,tabName:null})
      :Object.freeze(match[2]?{kind:'application',tabId:tabId,tabName:match[1],settingsView:match[2]}:{kind:'application',tabId:tabId,tabName:match[1]});
  }

  function resolveConferenceTabRoute(tabId){
    tabId=typeof tabId==='number'?tabId:parseInt(tabId,10);
    if(tabId<0||tabId>=conferenceTabNames.length||!isFinite(tabId))return null;
    return '/conference/app/'+conferenceTabNames[tabId];
  }

  function resolveConferenceSettingsRoute(view){
    return view==='houses'||view==='people'?'/conference/app/settings/'+view:'/conference/app/settings';
  }

  global.ApplicationRouting=Object.freeze({
    getBasePathname:basePathname,
    resolveLogicalRoute:resolveLogicalRoute,
    getLogicalPathname:function(){
      var hash=String(location&&location.hash||'');
      return hash.indexOf('#/')===0?normalizeLogicalRoute(hash.slice(1)):'/';
    },
    getLogicalQueryParam:function(name){
      name=String(name||'').trim();
      if(!name)return null;
      var route=this.getLogicalPathname(),queryIndex=route.indexOf('?');
      if(queryIndex<0)return null;var query=route.slice(queryIndex+1).split('&');for(var i=0;i<query.length;i++){var pair=query[i].split('='),key=decodeURIComponent(pair.shift()||'');if(key===name)return decodeURIComponent(pair.join('=')||'');}return null;
    },removeLogicalQueryParam:function(name){var hash=String(global.location&&global.location.hash||'');if(hash.indexOf('#/')!==0)return false;var route=hash.slice(1),queryIndex=route.indexOf('?');if(queryIndex<0)return false;var key=encodeURIComponent(String(name||'')),parts=route.slice(queryIndex+1).split('&').filter(Boolean),kept=parts.filter(function(part){return part.split('=')[0]!==key;});if(kept.length===parts.length)return false;var next=route.slice(0,queryIndex)+(kept.length?'?'+kept.join('&'):'');if(global.history&&typeof global.history.replaceState==='function')global.history.replaceState(null,'',resolveLogicalRoute(next));return true;},
    logicalPathname:logicalPathname,
    getConferenceRoute:getConferenceRoute,
    resolveConferenceTabRoute:resolveConferenceTabRoute,
    resolveConferenceSettingsRoute:resolveConferenceSettingsRoute
  });
})(window);
