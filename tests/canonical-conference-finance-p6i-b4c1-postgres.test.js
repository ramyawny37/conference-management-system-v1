'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');
const root=path.join(__dirname,'..');
const migration=path.join(root,'supabase/migrations/20261004140000_canonical_conference_finance_foundation.sql');
const source=fs.readFileSync(migration,'utf8');
const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_p6i_b4c1_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)),String(pattern));}
function quoted(value){return `'${JSON.stringify(value).replaceAll("'","''")}'::jsonb`;}

const id={
  owner:'10000000-0000-4000-8000-000000000001',view:'10000000-0000-4000-8000-000000000002',manage:'10000000-0000-4000-8000-000000000003',none:'10000000-0000-4000-8000-000000000004',staleOwner:'10000000-0000-4000-8000-000000000005',staleManager:'10000000-0000-4000-8000-000000000006',staleViewer:'10000000-0000-4000-8000-000000000007',
  ownerDevice:'11000000-0000-4000-8000-000000000001',viewDevice:'11000000-0000-4000-8000-000000000002',manageDevice:'11000000-0000-4000-8000-000000000003',noneDevice:'11000000-0000-4000-8000-000000000004',staleOwnerDevice:'11000000-0000-4000-8000-000000000005',staleManagerDevice:'11000000-0000-4000-8000-000000000006',staleViewerDevice:'11000000-0000-4000-8000-000000000007',revokedDevice:'11000000-0000-4000-8000-000000000008',
  conference:'20000000-0000-4000-8000-000000000001',expense:'30000000-0000-4000-8000-000000000001',income:'30000000-0000-4000-8000-000000000002',settlement:'30000000-0000-4000-8000-000000000003',adjustment:'30000000-0000-4000-8000-000000000004'
};
function context(actor,device){return `set local platform.phase1c_context='${JSON.stringify({purpose:'PLATFORM_DEVICE_SESSION_DISPATCH',user_id:actor,device_id:device})}';`;}
function read(actor,device){return `begin;${context(actor,device)}select public.get_conference_finance('${device}','${id.conference}');commit;`;}
let operationSequence=0;
function op(){operationSequence++;return `40000000-0000-4000-8000-${String(operationSequence).padStart(12,'0')}`;}
function mutate(actor,device,operation,entity,action,entityId,revision,payload){return `begin;${context(actor,device)}select public.mutate_conference_finance('${device}','${operation}','${id.conference}','${entity}','${action}',${entityId?`'${entityId}'`:'null'},${revision},${quoted(payload)});commit;`;}
const itemPayload=(name,method='fixed')=>({name,enabled:true,calculationMethod:method,target:null,operation:null,quantity:null,unitPrice:null,amount:10,notes:'proof'});
const settlementPayload=name=>({name,enabled:true,calculationMethod:'quantity_price',target:'expense',operation:'subtract',quantity:2,unitPrice:3,amount:null,notes:'proof'});

test('B4C.1 executes the real Finance migration and proves canonical behavior in disposable PostgreSQL',async t=>{
  const roles=['anon','authenticated','service_role'],created=[];
  try{command('psql',['-X','-At','-d','postgres','-c','select version()']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  command('createdb',[database]);
  try{
    for(const role of roles)if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}
    query(`create schema extensions;create extension pgcrypto with schema extensions;create schema platform;create schema platform_private;
      create table platform.profiles(user_id uuid primary key);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid not null,device_id uuid not null,status text not null);
      create table public.conferences(id uuid primary key,owner_id uuid not null,status text not null default 'active',deleted_at timestamptz);
      create table public.conference_snapshots(conference_id uuid primary key,data jsonb not null);
      create table public.conference_members(conference_id uuid,user_id uuid,role text);
      create table public.module_permission_catalog(permission_key text primary key,status text,module_key text,allowed_scope_mode text,allowed_resource_type text);
      create table public.test_permission_grants(user_id uuid,permission_key text,conference_id uuid);
      create table public.conference_participation_operations(actor_user_id uuid not null references platform.profiles(user_id),operation_id uuid not null,operation text not null constraint conference_participation_operations_operation_check check(operation in('create','create_with_person','set_status','set_guardian','delete','transport_vehicle_create','transport_vehicle_update','transport_vehicle_delete','transport_assignment_set','transport_assignment_remove','restaurant_mutation','accommodation_pricing_mutation','air_conditioning_mutation')),request jsonb not null,result jsonb not null,created_at timestamptz,primary key(actor_user_id,operation_id));
      create table platform.audit_events(id uuid primary key default extensions.gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,old_values jsonb,new_values jsonb,metadata jsonb,operation_id uuid,source text);
      create function platform_private.require_exact_jsonb_keys(p jsonb,required text[],optional text[] default '{}') returns void language plpgsql as $$declare actual text[];begin select coalesce(array_agg(key order by key),'{}') into actual from jsonb_object_keys(p) key;if actual<>(select array_agg(x order by x) from unnest(required||optional) x) then raise exception 'JSON_KEYS_INVALID' using errcode='22023';end if;end$$;
      create function platform_private.validated_phase1c_device_authorization(actor uuid,device uuid) returns uuid language sql stable as $$select id from platform.user_device_authorizations where user_id=actor and device_id=device and status='approved' limit 1$$;
      create function public.require_effective_module_permission(device uuid,module text,permission text,scope text,resource text) returns jsonb language plpgsql stable as $$declare c jsonb;actor uuid;begin c:=nullif(current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(c->>'user_id')::uuid;if c->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (c->>'device_id')::uuid is distinct from device or platform_private.validated_phase1c_device_authorization(actor,device) is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;if not exists(select 1 from public.conferences where id=resource::uuid and owner_id=actor) and not exists(select 1 from public.test_permission_grants where user_id=actor and permission_key=permission and conference_id=resource::uuid) then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501';end if;return jsonb_build_object('actorUserId',actor,'actorDeviceId',device);end$$;
      create function platform_private.route_canonical_conference_operation(a uuid,b uuid,c bytea,d uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql as $$begin if p_operation='get_conference_air_conditioning' then return '{}'::jsonb;end if;return '{}'::jsonb;end$$;`);
    const people=[id.owner,id.view,id.manage,id.none,id.staleOwner,id.staleManager,id.staleViewer];
    query(`insert into platform.profiles select unnest(array[${people.map(x=>`'${x}'::uuid`).join(',')}]);
      insert into public.conferences values('${id.conference}','${id.owner}','active',null);
      insert into public.module_permission_catalog values('conference.accounts.view','active','conference','resource','conference'),('conference.accounts.manage','active','conference','resource','conference');
      insert into public.test_permission_grants values('${id.view}','conference.accounts.view','${id.conference}'),('${id.manage}','conference.accounts.manage','${id.conference}');
      insert into platform.user_device_authorizations values
      (extensions.gen_random_uuid(),'${id.owner}','${id.ownerDevice}','approved'),(extensions.gen_random_uuid(),'${id.view}','${id.viewDevice}','approved'),(extensions.gen_random_uuid(),'${id.manage}','${id.manageDevice}','approved'),(extensions.gen_random_uuid(),'${id.none}','${id.noneDevice}','approved'),(extensions.gen_random_uuid(),'${id.staleOwner}','${id.staleOwnerDevice}','approved'),(extensions.gen_random_uuid(),'${id.staleManager}','${id.staleManagerDevice}','approved'),(extensions.gen_random_uuid(),'${id.staleViewer}','${id.staleViewerDevice}','approved'),(extensions.gen_random_uuid(),'${id.manage}','${id.revokedDevice}','revoked');
      insert into public.conference_members values('${id.conference}','${id.staleOwner}','owner'),('${id.conference}','${id.staleManager}','manager'),('${id.conference}','${id.staleViewer}','viewer');
      insert into public.conference_snapshots values('${id.conference}',${quoted({accounts:{settings:{currency:'USD',roundingPrecision:3,accommodationDefaults:{roomRate:999},mealsDefaults:{adultLunchPrice:777},airConditioningDefaults:{roomRate:555}},financialItems:{enabled:true,items:[{id:id.expense,name:'Legacy expense',enabled:true,calculationMethod:'per_day',quantity:null,unitPrice:12,amount:null,notes:'expense'}]},incomeItems:{enabled:false,items:[{id:id.income,name:'Legacy income',enabled:true,calculationMethod:'manual',quantity:null,unitPrice:null,amount:90,notes:'income'}]},settlements:{enabled:true,items:[{id:id.settlement,name:'Legacy settlement',enabled:true,calculationMethod:'fixed',target:'income',operation:'add',quantity:null,unitPrice:null,amount:5,notes:'settlement'}]},expenses:{accommodation:{roomRate:999},meals:{manualTotal:777},airConditioning:{roomRate:555}}},financialV3:{enabled:true,adjustments:[{id:id.adjustment,type:'deduction',category:'other',amount:7,note:'adjustment'}],invoiceComparison:{enabled:true,total:12345}}})});`);
    await t.test('migration executes and one-time backfill preserves only Finance-owned active facts',()=>{
      command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migration]);
      assert.equal(query(`select currency||':'||rounding_precision||':'||income_enabled from public.conference_finance_settings where conference_id='${id.conference}'`),'USD:3:false');
      assert.equal(query(`select string_agg(kind||':'||id||':'||calculation_method,',' order by kind) from public.conference_finance_items`),`EXPENSE:${id.expense}:per_day,INCOME:${id.income}:manual,SETTLEMENT:${id.settlement}:fixed`);
      assert.equal(query(`select type||':'||category||':'||amount from public.conference_finance_adjustments where id='${id.adjustment}'`),'deduction:other:7.00');
      assert.equal(query(`select count(*) from information_schema.columns where table_name like 'conference_finance%' and column_name ~* 'invoice|accommodation|restaurant|air'`),'0');
      assert.equal((source.match(/conference_snapshots/g)||[]).length,3);
      const runtime=query(`select pg_get_functiondef('public.get_conference_finance(uuid,uuid)'::regprocedure)||pg_get_functiondef('public.mutate_conference_finance(uuid,uuid,uuid,text,text,uuid,bigint,jsonb)'::regprocedure)||pg_get_functiondef('platform_private.conference_finance_projection(uuid)'::regprocedure)`);
      assert.doesNotMatch(runtime,/conference_snapshots|conference\.accounts(?:\W)*(?:financialItems|incomeItems|settlements|settings)|financialV3/);
    });
    await t.test('authorization, stale memberships, and device/session boundary execute fail closed',()=>{
      assert.match(query(read(id.owner,id.ownerDevice)),/conferenceId/);assert.match(query(read(id.view,id.viewDevice)),/conferenceId/);
      rejects(mutate(id.view,id.viewDevice,op(),'EXPENSE','UPSERT',id.expense,1,itemPayload('Denied')),/MODULE_PERMISSION_REQUIRED/);
      assert.match(query(mutate(id.manage,id.manageDevice,op(),'EXPENSE','UPSERT',id.expense,1,itemPayload('Managed'))),/conferenceId/);
      rejects(read(id.none,id.noneDevice),/MODULE_PERMISSION_REQUIRED/);rejects(mutate(id.none,id.noneDevice,op(),'SETTINGS','UPSERT',null,1,{}),/MODULE_PERMISSION_REQUIRED/);
      for(const pair of [[id.staleOwner,id.staleOwnerDevice],[id.staleManager,id.staleManagerDevice],[id.staleViewer,id.staleViewerDevice]]){rejects(read(pair[0],pair[1]),/MODULE_PERMISSION_REQUIRED/);rejects(mutate(pair[0],pair[1],op(),'EXPENSE','DELETE',id.expense,2,{}),/MODULE_PERMISSION_REQUIRED/);}
      rejects(`select public.get_conference_finance('${id.ownerDevice}','${id.conference}')`,/APPROVED_DEVICE_SESSION_REQUIRED/);
      rejects(`begin;${context(id.owner,id.ownerDevice)}select public.get_conference_finance('${id.viewDevice}','${id.conference}');commit;`,/APPROVED_DEVICE_SESSION_REQUIRED/);
      rejects(`begin;${context(id.manage,id.revokedDevice)}select public.get_conference_finance('${id.revokedDevice}','${id.conference}');commit;`,/APPROVED_DEVICE_SESSION_REQUIRED/);
      rejects(`begin;${context(id.none,id.noneDevice)}select public.get_conference_finance('${id.ownerDevice}','${id.conference}');commit;`,/APPROVED_DEVICE_SESSION_REQUIRED/);
    });
    await t.test('actual ACL/RLS and direct EXECUTE privileges deny API roles',()=>{
      for(const role of roles)for(const table of ['conference_finance_settings','conference_finance_items','conference_finance_adjustments'])for(const privilege of ['SELECT','INSERT','UPDATE','DELETE'])assert.equal(query(`select has_table_privilege('${role}','public.${table}','${privilege}')`),'f');
      for(const role of roles){assert.equal(query(`select has_function_privilege('${role}','public.get_conference_finance(uuid,uuid)','EXECUTE')`),'f');assert.equal(query(`select has_function_privilege('${role}','public.mutate_conference_finance(uuid,uuid,uuid,text,text,uuid,bigint,jsonb)','EXECUTE')`),'f');}
      rejects(`set role authenticated;select * from public.conference_finance_items`,/permission denied/);
      rejects(`set role authenticated;select public.get_conference_finance('${id.ownerDevice}','${id.conference}')`,/permission denied/);
    });
    await t.test('CRUD, exact methods, revisions, replay, mismatch, audit, and actor-scoped IDs execute correctly',()=>{
      const methods=['fixed','quantity_price','per_day','per_room','per_person','manual'];
      for(const [index,method] of methods.entries()){const item=`31000000-0000-4000-8000-${String(index+1).padStart(12,'0')}`;query(mutate(id.manage,id.manageDevice,op(),'EXPENSE','UPSERT',item,0,itemPayload(method,method)));assert.equal(query(`select calculation_method from public.conference_finance_items where id='${item}'`),method);query(mutate(id.manage,id.manageDevice,op(),'EXPENSE','DELETE',item,1,{}));}
      const settingsOp=op();query(mutate(id.manage,id.manageDevice,settingsOp,'SETTINGS','UPSERT',null,1,{currency:'EUR',roundingPrecision:2,expensesEnabled:true,incomeEnabled:true,settlementsEnabled:true,adjustmentsEnabled:true}));assert.equal(query(`select revision from public.conference_finance_settings where conference_id='${id.conference}'`),'2');
      const incomeNew='32000000-0000-4000-8000-000000000001',settleNew='32000000-0000-4000-8000-000000000002',adjustNew='32000000-0000-4000-8000-000000000003';
      query(mutate(id.manage,id.manageDevice,op(),'INCOME','UPSERT',incomeNew,0,itemPayload('Income')));query(mutate(id.manage,id.manageDevice,op(),'SETTLEMENT','UPSERT',settleNew,0,settlementPayload('Settlement')));query(mutate(id.manage,id.manageDevice,op(),'ADJUSTMENT','UPSERT',adjustNew,0,{type:'addition',category:'restaurant',amount:11,note:'proof'}));
      const updateOp=op(),updateSql=mutate(id.manage,id.manageDevice,updateOp,'INCOME','UPSERT',incomeNew,1,itemPayload('Income updated','per_person'));const first=query(updateSql),auditBefore=query(`select count(*) from platform.audit_events where operation_id='${updateOp}'`);assert.equal(query(`select revision from public.conference_finance_items where id='${incomeNew}'`),'2');assert.equal(query(updateSql),first);assert.equal(query(`select revision from public.conference_finance_items where id='${incomeNew}'`),'2');assert.equal(query(`select count(*) from platform.audit_events where operation_id='${updateOp}'`),auditBefore);
      rejects(mutate(id.manage,id.manageDevice,updateOp,'INCOME','DELETE',incomeNew,2,{}),/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
      const ledgerBefore=query(`select count(*) from public.conference_participation_operations`),auditCount=query(`select count(*) from platform.audit_events`);rejects(mutate(id.manage,id.manageDevice,op(),'INCOME','UPSERT',incomeNew,1,itemPayload('stale')),/CONFERENCE_FINANCE_REVISION_CONFLICT/);assert.equal(query(`select name||':'||revision from public.conference_finance_items where id='${incomeNew}'`),'Income updated:2');assert.equal(query(`select count(*) from public.conference_participation_operations`),ledgerBefore);assert.equal(query(`select count(*) from platform.audit_events`),auditCount);
      const sharedOp=op(),actorItem='33000000-0000-4000-8000-000000000001';query(mutate(id.manage,id.manageDevice,sharedOp,'EXPENSE','UPSERT',actorItem,0,itemPayload('Actor one')));query(`insert into public.test_permission_grants values('${id.owner}','conference.accounts.manage','${id.conference}') on conflict do nothing`);const actorItem2='33000000-0000-4000-8000-000000000002';query(mutate(id.owner,id.ownerDevice,sharedOp,'EXPENSE','UPSERT',actorItem2,0,itemPayload('Actor two')));assert.equal(query(`select count(*) from public.conference_participation_operations where operation_id='${sharedOp}'`),'2');
      assert.equal(query(`select actor_user_id||':'||(actor_device_authorization_id is not null)||':'||action||':'||entity_type||':'||(metadata->>'entity') from platform.audit_events where operation_id='${updateOp}'`),`${id.manage}:true:conference.finance.changed:conference_finance:INCOME`);
      for(const [entity,entityId,revision] of [['INCOME',incomeNew,2],['SETTLEMENT',settleNew,1],['ADJUSTMENT',adjustNew,1]])query(mutate(id.manage,id.manageDevice,op(),entity,'DELETE',entityId,revision,{}));
    });
    await t.test('deterministic post-mutation failure rolls back business row, ledger, and audit',()=>{
      const failureOp=op(),item='34000000-0000-4000-8000-000000000001';query(`create function platform.fail_finance_audit() returns trigger language plpgsql as $$begin if new.operation_id='${failureOp}' then raise exception 'INJECTED_FINANCE_AUDIT_FAILURE';end if;return new;end$$;create trigger fail_finance_audit before insert on platform.audit_events for each row execute function platform.fail_finance_audit()`);
      rejects(mutate(id.manage,id.manageDevice,failureOp,'EXPENSE','UPSERT',item,0,itemPayload('Rollback')),/INJECTED_FINANCE_AUDIT_FAILURE/);
      assert.equal(query(`select count(*) from public.conference_finance_items where id='${item}'`),'0');assert.equal(query(`select count(*) from public.conference_participation_operations where operation_id='${failureOp}'`),'0');assert.equal(query(`select count(*) from platform.audit_events where operation_id='${failureOp}'`),'0');
    });
  }finally{command('dropdb',['--if-exists',database]);for(const role of created)command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);}
});
