const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const vm=require('node:vm');

const source=fs.readFileSync('js/platform-integration.js','utf8');

function runtime(initialRoute){
  let route=initialRoute;
  const listeners={};
  const calls=[];
  const elements={
    startupScreen:{style:{display:'none'},classList:{add(){},remove(){}}},
    applicationTopbar:{style:{display:'block'}},
    applicationBody:{style:{display:'block'}},
    conferenceWorkspace:{style:{},hidden:false,setAttribute(){}},
    reservationsWorkspace:{hidden:true,setAttribute(){}},
    warehouseWorkspace:{hidden:true,setAttribute(){}}
  };
  const window={
    document:{addEventListener(){},getElementById:id=>elements[id]||null},
    ApplicationRouting:{getLogicalPathname:()=>route,resolveLogicalRoute:value=>'#'+value},
    history:{pushState(_state,_title,value){route=value.slice(1);}},
    addEventListener(name,handler){listeners[name]=handler;},
    setApplicationMode(mode){
      calls.push(['mode',mode]);
      const startup=mode==='startup';
      elements.startupScreen.style.display=startup?'flex':'none';
      elements.applicationTopbar.style.display=startup?'none':'';
      elements.applicationBody.style.display=startup?'none':'';
    },
    reconcileConferenceRoute(){calls.push(['conference-route',route]);return true;},
    openConferenceWorkspace(){calls.push(['conference-open']);return true;},
    openWarehouseWorkspace(){return true;},
    PlatformDeviceSession:{invokeModuleProtected(module){return Promise.resolve({status:'allowed',moduleKey:module});}}
  };
  vm.runInNewContext(source,{window,Promise,Object,JSON,String});
  window.PlatformIntegration.registerModule({id:'reservations',mount(){calls.push(['reservations-mount']);return true;},reconcileRoute(){return true;}});
  return {window,elements,calls,listeners,setRoute(value){route=value;}};
}

test('Conference internal surface is relinquished before Reservations becomes visible',async()=>{
  const state=runtime('/conference/app/accommodation');
  assert.equal(state.window.PlatformIntegration.reconcileRoute(),true);
  assert.equal(state.window.PlatformIntegration.getActiveModuleId(),'conference');
  assert.equal(state.elements.applicationBody.style.display,'block');

  state.setRoute('/reservations/bookings/new');
  await state.listeners.hashchange();

  assert.equal(state.window.PlatformIntegration.getActiveModuleId(),'reservations');
  assert.deepEqual(state.calls.slice(-2),[['mode','startup'],['reservations-mount']]);
  assert.equal(state.elements.startupScreen.style.display,'flex');
  assert.equal(state.elements.applicationTopbar.style.display,'none');
  assert.equal(state.elements.applicationBody.style.display,'none');
  assert.equal(state.elements.conferenceWorkspace.hidden,true);
  assert.equal(state.elements.reservationsWorkspace.hidden,false);
});

test('returning to Conference delegates restoration to the Conference lifecycle',async()=>{
  const state=runtime('/reservations');
  await state.window.PlatformIntegration.reconcileRoute();
  state.calls.length=0;

  state.setRoute('/conference/app/accommodation');
  state.listeners.hashchange();

  assert.equal(state.window.PlatformIntegration.getActiveModuleId(),'conference');
  assert.deepEqual(state.calls,[['conference-route','/conference/app/accommodation']]);
  assert.equal(state.elements.conferenceWorkspace.hidden,false);
  assert.equal(state.elements.reservationsWorkspace.hidden,true);
});
