'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const test=require('node:test');
const vm=require('node:vm');

const source=fs.readFileSync('js/platform-integration.js','utf8');

function harness(){
  let route='/conference';
  const calls=[];
  const elements={
    startupScreen:{classList:{add(){},remove(){}}},
    platformShell:{setAttribute(){},classList:{remove(){}}},
    conferenceWorkspace:{hidden:false,setAttribute(name,value){this[name]=value;}},
    warehouseWorkspace:{hidden:true,setAttribute(name,value){this[name]=value;}},
    reservationsWorkspace:{hidden:true,setAttribute(name,value){this[name]=value;}},
  };
  const window={
    document:{addEventListener(){},getElementById:id=>elements[id]||null,querySelector(){return null;}},
    addEventListener(){},
    history:{pushState(_a,_b,next){route=String(next);},replaceState(_a,_b,next){route=String(next);}},
    ApplicationRouting:{getLogicalPathname:()=>route,resolveLogicalRoute:value=>value},
    StartupAccessGate:{getState:()=>({pipelineState:'completed',applicationVisible:true}),isAllowed:()=>true},
    PlatformDeviceSession:{invokeModuleProtected:()=>Promise.resolve({status:'allowed',moduleKey:'reservations'})},
    openConferenceWorkspace(){calls.push('conference');return true;},
    reconcileConferenceRoute(){calls.push('conference-route');return true;},
  };
  vm.runInNewContext(source,{window,Promise,Object,JSON,String,Error});
  window.PlatformIntegration.registerModule({id:'reservations',mount(){calls.push('reservations');return true;},unmount(){calls.push('reservations-unmount');return true;}});
  return {window,elements,calls,setRoute:value=>{route=value;}};
}

test('module activation owns exactly one visible workspace',async()=>{
  const state=harness();
  state.window.PlatformIntegration.openModule('conference');
  assert.equal(state.elements.conferenceWorkspace.hidden,false);
  assert.equal(state.elements.reservationsWorkspace.hidden,true);
  await state.window.PlatformIntegration.openModule('reservations');
  assert.equal(state.elements.conferenceWorkspace.hidden,true);
  assert.equal(state.elements.warehouseWorkspace.hidden,true);
  assert.equal(state.elements.reservationsWorkspace.hidden,false);
  assert.equal(state.window.PlatformIntegration.getActiveModuleId(),'reservations');
});

test('route reconciliation restores reservations workspace ownership after refresh-style entry',async()=>{
  const state=harness();
  state.setRoute('/reservations/bookings/new');
  await state.window.PlatformIntegration.reconcileRoute();
  assert.equal(state.elements.conferenceWorkspace.hidden,true);
  assert.equal(state.elements.reservationsWorkspace.hidden,false);
  assert.equal(state.window.PlatformIntegration.getActiveModuleId(),'reservations');
});
