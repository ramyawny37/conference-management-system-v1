'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {JSDOM}=require('jsdom');

const ui=fs.readFileSync('script.js','utf8');
const start=ui.indexOf('function canonicalHouseDirectoryDialog(');
const end=ui.indexOf('\nfunction createHouseTemplate(',start);
assert.ok(start>=0&&end>start,'canonical house directory editor must exist');
const editor=ui.slice(start,end);

function harness(){
  const dom=new JSDOM('<!doctype html><html><body></body></html>');
  const calls=[],refreshes=[],errors=[];
  let mutate=()=>Promise.resolve({ok:true});
  const window={
    CanonicalConferenceHouses:{
      mutate(operation,payload){
        calls.push({operation,payload:JSON.parse(JSON.stringify(payload))});
        return mutate(operation,payload);
      }
    },
    console:{error(...args){errors.push(args);}}
  };
  const context={
    document:dom.window.document,window,Promise,Object,Number,String,
    refreshCanonicalHouseDirectory:message=>{refreshes.push(message);return Promise.resolve(true);}
  };
  vm.runInNewContext(editor+'\nthis.openDialog=canonicalHouseDirectoryDialog;',context);
  const overlay=()=>dom.window.document.getElementById('canonicalHouseDirectoryDialog');
  const input=name=>overlay().querySelector('[name="'+name+'"]');
  const set=(name,value)=>{input(name).value=String(value);};
  const submit=()=>overlay().querySelector('form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));
  const flush=()=>new Promise(resolve=>setImmediate(resolve));
  return {
    calls,refreshes,errors,overlay,input,set,submit,flush,dom,
    open:(kind,entity=null,parent=null)=>context.openDialog(kind,entity,parent),
    setMutate:fn=>{mutate=fn;}
  };
}

test('creation uses one central writer for house, floor and room and refreshes after save',async()=>{
  for(const [kind,field,value,operation,parent] of [
    ['house','name',' بيت القاهرة ','create_house',null],
    ['floor','name',' الدور الثاني ','create_floor','house-1'],
    ['room','roomNumber',' 502 ','create_room','floor-1']
  ]){
    const h=harness();
    assert.equal(h.open(kind,null,parent),true);
    h.set(field,value);
    h.submit();
    await h.flush();
    assert.equal(h.calls.length,1,kind);
    assert.equal(h.calls[0].operation,operation);
    assert.equal(h.calls[0].payload[field],value.trim());
    if(kind==='floor')assert.equal(h.calls[0].payload.houseId,parent);
    if(kind==='room'){
      assert.equal(h.calls[0].payload.floorId,parent);
      assert.equal(h.calls[0].payload.baseCapacity,1);
      assert.equal(h.calls[0].payload.extraBedCapacity,0);
    }
    assert.equal(h.refreshes.length,1);
    assert.equal(h.overlay(),null);
    h.dom.window.close();
  }
});

test('editing all three directory entities preserves expectedRevision and position',async()=>{
  const cases=[
    ['house',{houseId:'house-1',name:'Before',description:'old',position:2,revision:17,isActive:true},'name','After','update_house','houseId'],
    ['floor',{floorId:'floor-1',name:'Before',position:3,revision:18},'name','After','update_floor','floorId'],
    ['room',{roomId:'room-1',roomNumber:'501',baseCapacity:2,extraBedCapacity:1,notes:'memo',position:4,revision:19},'roomNumber','502','update_room','roomId']
  ];
  for(const [kind,entity,field,value,operation,idField] of cases){
    const h=harness();
    h.open(kind,entity);
    h.set(field,value);
    h.submit();
    await h.flush();
    assert.equal(h.calls.length,1);
    assert.equal(h.calls[0].operation,operation);
    assert.equal(h.calls[0].payload[idField],entity[idField]);
    assert.equal(h.calls[0].payload.expectedRevision,entity.revision);
    assert.equal(h.calls[0].payload.position,entity.position);
    assert.equal(h.calls[0].payload[field],value);
    assert.equal(h.refreshes.length,1);
    h.dom.window.close();
  }
});

test('blank and whitespace-only names and numbers never call mutation',async()=>{
  for(const kind of ['house','floor','room']){
    for(const value of ['', '   ']){
      const h=harness();
      h.open(kind);
      h.set(kind==='room'?'roomNumber':'name',value);
      h.submit();
      await h.flush();
      assert.equal(h.calls.length,0,kind+' '+JSON.stringify(value));
      assert.equal(h.refreshes.length,0);
      assert.ok(h.overlay());
      assert.match(h.overlay().querySelector('[role="alert"]').textContent,/أكمل البيانات/);
      h.dom.window.close();
    }
  }
});

test('capacity parser accepts nonnegative integers and rejects invalid or unsafe totals',async()=>{
  for(const [base,extra,valid] of [
    ['2','1',true],['0','3',true],['1','0',true],
    ['0','0',false],['','2',false],['2','',false],
    ['1.5','1',false],['-1','2',false],
    ['9007199254740992','0',false],['9007199254740991','1',false]
  ]){
    const h=harness();
    h.open('room',null,'floor-1');
    h.set('roomNumber','101');
    h.set('baseCapacity',base);
    h.set('extraBedCapacity',extra);
    h.submit();
    await h.flush();
    assert.equal(h.calls.length,valid?1:0,'base='+base+' extra='+extra);
    if(valid){
      assert.equal(h.calls[0].payload.baseCapacity,Number(base));
      assert.equal(h.calls[0].payload.extraBedCapacity,Number(extra));
    }else{
      assert.ok(h.overlay());
      assert.match(h.overlay().querySelector('[role="alert"]').textContent,/سعة صحيحة/);
    }
    h.dom.window.close();
  }
});

test('cancel and backdrop dismissal never invoke the writer',()=>{
  const h=harness();
  h.open('floor',null,'house-1');
  h.set('name','Valid but canceled');
  h.overlay().querySelector('button[type="button"]').click();
  assert.equal(h.overlay(),null);
  assert.equal(h.calls.length,0);
  h.open('room',null,'floor-1');
  h.overlay().dispatchEvent(new h.dom.window.MouseEvent('click',{bubbles:true}));
  assert.equal(h.overlay(),null);
  assert.equal(h.calls.length,0);
  h.dom.window.close();
});

test('pending save blocks second submit and backdrop dismissal',async()=>{
  const h=harness();
  let release;
  h.setMutate(()=>new Promise(resolve=>{release=resolve;}));
  h.open('house');
  h.set('name','Busy');
  h.submit();
  await h.flush();
  const overlay=h.overlay();
  assert.equal(overlay.querySelector('button[type="submit"]').disabled,true);
  h.submit();
  overlay.dispatchEvent(new h.dom.window.MouseEvent('click',{bubbles:true}));
  assert.equal(h.calls.length,1);
  assert.ok(h.overlay());
  release({ok:true});
  await h.flush();
  assert.equal(h.calls.length,1);
  assert.equal(h.refreshes.length,1);
  assert.equal(h.overlay(),null);
  h.dom.window.close();
});

test('failed mutation leaves editor open, displays error and permits retry',async()=>{
  const h=harness();
  h.setMutate(()=>Promise.reject(new Error('rejected')));
  h.open('floor',null,'house-1');
  h.set('name','Test');
  h.submit();
  await h.flush();
  assert.equal(h.calls.length,1);
  assert.equal(h.refreshes.length,0);
  assert.ok(h.overlay());
  assert.match(h.overlay().querySelector('[role="alert"]').textContent,/تعذر الحفظ/);
  assert.equal(h.overlay().querySelector('button[type="submit"]').disabled,false);
  h.setMutate(()=>Promise.resolve({ok:true}));
  h.submit();
  await h.flush();
  assert.equal(h.calls.length,2);
  assert.equal(h.refreshes.length,1);
  assert.equal(h.overlay(),null);
  h.dom.window.close();
});

test('active editor retains one canonical writer and no native prompt draft',()=>{
  assert.doesNotMatch(editor,/\bprompt\s*\(/);
  assert.doesNotMatch(ui,/function canonicalHouseRoomDraft\(/);
  assert.equal((editor.match(/CanonicalConferenceHouses\.mutate\(/g)||[]).length,1);
});

test('closing the house editor restores focus to its original trigger',()=>{
 const h=harness();
 const trigger=h.dom.window.document.createElement('button');
 trigger.textContent='Open house';
 h.dom.window.document.body.appendChild(trigger);
 trigger.focus();
 assert.equal(h.dom.window.document.activeElement,trigger);
 h.open('house');
 assert.notEqual(h.dom.window.document.activeElement,trigger);
 h.overlay().querySelector('button[type="button"]').click();
 assert.equal(h.dom.window.document.activeElement,trigger);
 h.dom.window.close();
});
