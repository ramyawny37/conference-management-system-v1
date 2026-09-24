(function(global){
  'use strict';
  var PREFIX='/reservations',states=Object.create(null),hasSnapshot=false;
  function isReservationsRoute(route){return route===PREFIX||String(route||'').indexOf(PREFIX+'/')===0;}
  function eachRouteItem(callback){var doc=global.document;if(!doc||!doc.querySelectorAll)return;Array.prototype.forEach.call(doc.querySelectorAll('[data-platform-route]'),callback);}
  function apply(){eachRouteItem(function(item){var route=String(item.getAttribute('data-platform-route')||'');if(!isReservationsRoute(route))return;var controlled=hasSnapshot&&Object.prototype.hasOwnProperty.call(states,route),enabled=!controlled||states[route]===true;item.disabled=!enabled;if(enabled){item.removeAttribute('aria-disabled');item.classList.remove('is-capability-disabled');}else{item.setAttribute('aria-disabled','true');item.classList.add('is-capability-disabled');}});}
  function setRouteAccessibility(snapshot){states=Object.create(null);hasSnapshot=Array.isArray(snapshot)&&snapshot.length>0;if(Array.isArray(snapshot))snapshot.forEach(function(entry){var route=entry&&String(entry.route||'');if(!isReservationsRoute(route))return;states[route]=entry.enabled===true;});apply();return true;}
  function isRouteEnabled(route){route=String(route||'');if(!isReservationsRoute(route)||!hasSnapshot||!Object.prototype.hasOwnProperty.call(states,route))return true;return states[route]===true;}
  function guard(event){var target=event&&event.target,item=target&&target.closest&&target.closest('[data-platform-route]');if(!item)return;var route=String(item.getAttribute('data-platform-route')||'');if(!isReservationsRoute(route)||isRouteEnabled(route))return;if(event.preventDefault)event.preventDefault();if(event.stopImmediatePropagation)event.stopImmediatePropagation();else if(event.stopPropagation)event.stopPropagation();}
  if(global.document&&global.document.addEventListener)global.document.addEventListener('click',guard,true);
  global.ReservationsRouteAccessibility=Object.freeze({setRouteAccessibility:setRouteAccessibility,isRouteEnabled:isRouteEnabled,apply:apply});
})(window);
