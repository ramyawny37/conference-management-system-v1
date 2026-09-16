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

  function appendStylesheet(path,marker,value){
    if(!document||!document.createElement||!document.head||!baseUrl)return;
    var link=document.createElement('link');
    link.rel='stylesheet';
    link.href=new URL(path,baseUrl).href;
    if(marker)link.setAttribute(marker,value||'');
    document.head.appendChild(link);
  }

  /* Presentation layers intentionally load after document CSS. */
  appendStylesheet('platform-shell-reference-v3.css?rev=approved-reference-v4','data-platform-shell-reference','v4');
  appendStylesheet('modules/reservations/reservations-visual-source-v2.css?rev=reference-source-v3','data-reservations-visual-source','v3');

  function composeReferenceTopbar(){
    if(!document||!document.querySelector)return;
    var topbar=document.querySelector('.platform-topbar');
    if(!topbar||topbar.querySelector('[data-platform-reference-header]'))return;

    var brand=document.createElement('div');
    brand.className='platform-topbar-reference-brand';
    brand.setAttribute('data-platform-reference-header','brand');
    brand.innerHTML='<img src="assets/make-a-difference-logo.png" alt=""><div class="platform-topbar-reference-brand-copy"><strong>منظومة الإدارة المتكاملة</strong><small>Integrated Management Platform</small></div>';

    var search=document.createElement('label');
    search.className='platform-topbar-reference-search';
    search.setAttribute('data-platform-reference-header','search');
    search.innerHTML='<span data-app-icon="search"></span><input type="text" readonly aria-label="البحث العام — قريبًا" placeholder="بحث بالاسم أو رقم الحجز أو الهاتف أو البريد ...">';

    var actions=document.createElement('div');
    actions.className='platform-topbar-reference-actions';
    actions.setAttribute('data-platform-reference-header','actions');
    actions.innerHTML='<button type="button" disabled aria-label="إضافة سريعة — قريبًا"><b>＋</b><span>إضافة سريعة</span></button><button type="button" disabled aria-label="التنبيهات — قريبًا">♧</button><button type="button" disabled aria-label="الرسائل — قريبًا">✉</button>';

    topbar.appendChild(brand);
    topbar.appendChild(search);
    topbar.appendChild(actions);
  }

  if(document){
    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',composeReferenceTopbar,{once:true});
    else composeReferenceTopbar();
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
    var match=/^\/conference\/app\/([a-z-]+)$/.exec(route);
    if(!match)return route.indexOf('/conference')===0
      ?Object.freeze({kind:'invalid',tabId:null,tabName:null}):null;
    var tabId=conferenceTabNames.indexOf(match[1]);
    return tabId<0?Object.freeze({kind:'invalid',tabId:null,tabName:null})
      :Object.freeze({kind:'application',tabId:tabId,tabName:match[1]});
  }

  function resolveConferenceTabRoute(tabId){
    tabId=typeof tabId==='number'?tabId:parseInt(tabId,10);
    if(tabId<0||tabId>=conferenceTabNames.length||!isFinite(tabId))return null;
    return '/conference/app/'+conferenceTabNames[tabId];
  }

  global.ApplicationRouting=Object.freeze({
    getBasePathname:basePathname,
    resolveLogicalRoute:resolveLogicalRoute,
    getLogicalPathname:function(){
      var hash=String(location&&location.hash||'');
      return hash.indexOf('#/')===0?normalizeLogicalRoute(hash.slice(1)):'/';
    },
    logicalPathname:logicalPathname,
    getConferenceRoute:getConferenceRoute,
    resolveConferenceTabRoute:resolveConferenceTabRoute
  });
})(window);
