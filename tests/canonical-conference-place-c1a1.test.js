'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');
const root=path.join(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261005120000_canonical_conference_place_foundation.sql'),'utf8');
const contract=fs.readFileSync(path.join(root,'js/supabase/platform-device-operation-contract.js'),'utf8');

test('C1A.1 owns place in Conference Core without legacy migration',()=>{
  assert.match(migration,/alter table public\.conferences[\s\S]*add column place text not null default ''/);
  assert.match(migration,/char_length\(place\)<=500/);
  assert.match(migration,/place'',v_conference\.place/);
  assert.doesNotMatch(migration,/conference_snapshots|conf\.place|activityLog|saveAppData|\bsave\(\)/);
  assert.equal((migration.match(/add column place/g)||[]).length,1);
});

test('C1A.1 extends the existing protected mutation and shared replay ledger',()=>{
  const signature='public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text)';
  assert.ok(contract.includes(signature));
  assert.match(migration,/create function public\.mutate_conference_core\([\s\S]*p_operation_id uuid[\s\S]*p_place text/);
  assert.match(migration,/conference_participation_operations/);
  assert.match(migration,/'conference_core_mutation'/);
  assert.doesNotMatch(migration,/create table[^;]*(place|operation)/i);
  assert.match(migration,/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
  assert.match(migration,/CONFERENCE_CORE_REVISION_CONFLICT/);
});

test('C1A.1 preserves unified permission, device, audit, rollback, and ACL boundaries',()=>{
  assert.match(migration,/'conference\.lifecycle\.manage'/);
  assert.match(migration,/PLATFORM_DEVICE_SESSION_DISPATCH/);
  assert.match(migration,/validated_phase1c_device_authorization/);
  assert.match(migration,/ACTOR_DEVICE_OVERRIDE_DENIED/);
  assert.match(migration,/insert into platform\.audit_events/);
  assert.match(migration,/actor_user_id,actor_device_authorization_id/);
  assert.match(migration,/revoke all on function public\.mutate_conference_core\([\s\S]*from public,anon,authenticated,service_role/);
  assert.doesNotMatch(migration,/conference_members|owner|manager|viewer|grant execute/);
  const mutation=migration.match(/create function public\.mutate_conference_core\([\s\S]*?end \$\$;/)[0];
  assert.ok(mutation.indexOf('update public.conferences')<mutation.indexOf('insert into public.conference_participation_operations'));
  assert.ok(mutation.indexOf('insert into public.conference_participation_operations')<mutation.indexOf('insert into platform.audit_events'));
});

test('C1A.1 router requires operation id and place with exact keys',()=>{
  assert.match(migration,/require_exact_jsonb_keys\(p_args,array\[''p_operation_id'',''p_conference_id'',''p_expected_revision'',''p_name'',''p_place'',''p_start_date'',''p_end_date'',''p_status''\]\)/);
  assert.match(migration,/public\.mutate_conference_core\(p_actor_device_id,\(p_args->>''p_operation_id''\)::uuid/);
});

const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_c1a1_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const cleanEnv=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env:cleanEnv}).trim();}
function query(sql){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',sql]);}
function rejects(sql,pattern){assert.throws(()=>query(sql),error=>pattern.test(String(error.stderr)),String(pattern));}

test('C1A.1 executable PostgreSQL proof covers authorization, replay, revision, ACL and rollback',()=>{
  const actor='10000000-0000-4000-8000-000000000001';
  const unauthorized='10000000-0000-4000-8000-000000000002';
  const pending='10000000-0000-4000-8000-000000000003';
  const device='20000000-0000-4000-8000-000000000001';
  const wrongDevice='20000000-0000-4000-8000-000000000002';
  const revokedDevice='20000000-0000-4000-8000-000000000003';
  const pendingDevice='20000000-0000-4000-8000-000000000004';
  const authorization='30000000-0000-4000-8000-000000000001';
  const conference='40000000-0000-4000-8000-000000000001';
  const operation='50000000-0000-4000-8000-000000000001';
  const staleOperation='50000000-0000-4000-8000-000000000002';
  const failureOperation='50000000-0000-4000-8000-000000000003';
  const roles=['anon','authenticated','service_role'],created=[];
  const context=(user,actorDevice)=>`set local platform.phase1c_context='${JSON.stringify({purpose:'PLATFORM_DEVICE_SESSION_DISPATCH',user_id:user,device_id:actorDevice})}';`;
  const mutate=(user,actorDevice,op,revision,place='Hall B')=>`begin;${context(user,actorDevice)}select public.mutate_conference_core('${actorDevice}','${op}','${conference}',${revision},'Conference','${place}','2026-11-01','2026-11-03','active');commit;`;
  try{command('psql',['-X','-At','-d','postgres','-c','select 1']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  command('createdb',[database]);
  try{
    for(const role of roles)if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}
    query(`create extension pgcrypto;create schema platform;create schema platform_private;
      create table platform.profiles(user_id uuid primary key,account_status text not null);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid,device_id uuid,status text,revoked_at timestamptz);
      create table platform.audit_events(id uuid primary key default gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,old_values jsonb,new_values jsonb,metadata jsonb,operation_id uuid,source text);
      create table public.conferences(id uuid primary key,name text not null,owner_id uuid not null,start_date date,end_date date,status text not null,completed_at timestamptz,revision bigint not null default 1,updated_by uuid,updated_at timestamptz default now(),deleted_at timestamptz);
      create table public.conference_participation_operations(actor_user_id uuid not null references platform.profiles(user_id),operation_id uuid not null,operation text not null constraint conference_participation_operations_operation_check check(operation in('create','create_with_person','set_status','set_guardian','delete','transport_vehicle_create','transport_vehicle_update','transport_vehicle_delete','transport_assignment_set','transport_assignment_remove','restaurant_mutation','accommodation_pricing_mutation','air_conditioning_mutation','finance_mutation')),request jsonb not null,result jsonb not null,created_at timestamptz,primary key(actor_user_id,operation_id));
      alter table public.conferences enable row level security;alter table public.conferences force row level security;revoke all on public.conferences,public.conference_participation_operations from public,anon,authenticated,service_role;
      create table public.test_access(user_id uuid primary key,permission_granted boolean not null,returned_actor uuid);
      create function platform_private.validated_phase1c_device_authorization(a uuid,d uuid) returns uuid language sql stable as $$select id from platform.user_device_authorizations where user_id=a and device_id=d and status='approved' and revoked_at is null limit 1$$;
      create function public.require_effective_module_permission(d uuid,m text,p text,s text,r text) returns jsonb language plpgsql stable as $$declare c jsonb;a uuid;x public.test_access%rowtype;begin c:=nullif(current_setting('platform.phase1c_context',true),'')::jsonb;a:=(c->>'user_id')::uuid;select * into x from public.test_access where user_id=a;if not found or not x.permission_granted or (select account_status from platform.profiles where user_id=a)<>'approved' then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501';end if;return jsonb_build_object('actorUserId',coalesce(x.returned_actor,a),'authoritySource','module_grant','grantId','60000000-0000-4000-8000-000000000001');end$$;
      create function public.get_conference_core(d uuid,cid uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare v_conference public.conferences%rowtype;begin select * into v_conference from public.conferences where id=cid;return jsonb_build_object('conferenceId',v_conference.id,'name',v_conference.name,'startDate',v_conference.start_date);end$$;
      create function public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text) returns jsonb language sql as $$select '{}'::jsonb$$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language sql as $$select$$;
      create function platform_private.route_canonical_conference_operation(p_actor_user_id uuid,p_session_id uuid,p_token_hash bytea,p_actor_device_id uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql as $$begin if false then return '{}'::jsonb;elsif p_operation='mutate_conference_core' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_expected_revision','p_name','p_start_date','p_end_date','p_status']); return public.mutate_conference_core(p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_name',(p_args->>'p_start_date')::date,(p_args->>'p_end_date')::date,p_args->>'p_status');end if;return '{}'::jsonb;end$$;
      insert into platform.profiles values('${actor}','approved'),('${unauthorized}','approved'),('${pending}','pending');
      insert into platform.user_device_authorizations values('${authorization}','${actor}','${device}','approved',null),(gen_random_uuid(),'${actor}','${wrongDevice}','approved',null),(gen_random_uuid(),'${actor}','${revokedDevice}','revoked',now()),(gen_random_uuid(),'${pending}','${pendingDevice}','approved',null),(gen_random_uuid(),'${unauthorized}','${wrongDevice}','approved',null);
      insert into public.test_access values('${actor}',true,null),('${unauthorized}',false,null),('${pending}',true,null);
      insert into public.conferences values('${conference}','Conference','${actor}','2026-11-01','2026-11-03','active',null,1,null,now(),null);`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,'supabase/migrations/20261005120000_canonical_conference_place_foundation.sql')]);
    assert.equal(query(`select place||':'||revision from public.conferences where id='${conference}'`),':1');
    assert.match(query(`begin;${context(actor,device)}select public.get_conference_core('${device}','${conference}');commit;`),/"place": ""/);
    for(const role of roles){assert.equal(query(`select has_table_privilege('${role}','public.conferences','UPDATE')`),'f');assert.equal(query(`select has_function_privilege('${role}','public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text)','EXECUTE')`),'f');}
    rejects(`set role authenticated;update public.conferences set place='Denied' where id='${conference}'`,/permission denied/);
    rejects(`set role authenticated;select public.mutate_conference_core('${device}','${operation}','${conference}',1,'Conference','Denied','2026-11-01','2026-11-03','active')`,/permission denied/);
    rejects(mutate(unauthorized,wrongDevice,operation,1),/MODULE_PERMISSION_REQUIRED|APPROVED_DEVICE_SESSION_REQUIRED/);
    rejects(mutate(pending,pendingDevice,operation,1),/MODULE_PERMISSION_REQUIRED/);
    rejects(`select public.mutate_conference_core('${device}','${operation}','${conference}',1,'Conference','No session','2026-11-01','2026-11-03','active')`,/APPROVED_DEVICE_SESSION_REQUIRED/);
    rejects(mutate(actor,revokedDevice,operation,1),/APPROVED_DEVICE_SESSION_REQUIRED/);
    rejects(`begin;${context(actor,device)}select public.mutate_conference_core('${wrongDevice}','${operation}','${conference}',1,'Conference','Wrong','2026-11-01','2026-11-03','active');commit;`,/APPROVED_DEVICE_SESSION_REQUIRED/);
    query(`update public.test_access set returned_actor='${unauthorized}' where user_id='${actor}'`);rejects(mutate(actor,device,operation,1),/ACTOR_DEVICE_OVERRIDE_DENIED/);query(`update public.test_access set returned_actor=null where user_id='${actor}'`);
    const first=query(mutate(actor,device,operation,1));assert.match(first,/"place": "Hall B"/);assert.equal(query(`select place||':'||revision from public.conferences where id='${conference}'`),'Hall B:2');assert.equal(query(mutate(actor,device,operation,1)),first);assert.equal(query(`select revision from public.conferences where id='${conference}'`),'2');assert.equal(query(`select count(*) from platform.audit_events where operation_id='${operation}'`),'1');assert.equal(query(`select actor_user_id from platform.audit_events where operation_id='${operation}'`),actor);
    rejects(mutate(actor,device,operation,2,'Mismatch'),/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
    const ledgerBefore=query(`select count(*) from public.conference_participation_operations`),auditBefore=query(`select count(*) from platform.audit_events`);rejects(mutate(actor,device,staleOperation,1,'Stale'),/CONFERENCE_CORE_REVISION_CONFLICT/);assert.equal(query(`select place||':'||revision from public.conferences where id='${conference}'`),'Hall B:2');assert.equal(query(`select count(*) from public.conference_participation_operations`),ledgerBefore);assert.equal(query(`select count(*) from platform.audit_events`),auditBefore);
    query(`create function platform.fail_place_audit() returns trigger language plpgsql as $$begin if new.operation_id='${failureOperation}' then raise exception 'INJECTED_PLACE_AUDIT_FAILURE';end if;return new;end$$;create trigger fail_place_audit before insert on platform.audit_events for each row execute function platform.fail_place_audit()`);
    rejects(mutate(actor,device,failureOperation,2,'Rollback'),/INJECTED_PLACE_AUDIT_FAILURE/);assert.equal(query(`select place||':'||revision from public.conferences where id='${conference}'`),'Hall B:2');assert.equal(query(`select count(*) from public.conference_participation_operations where operation_id='${failureOperation}'`),'0');assert.equal(query(`select count(*) from platform.audit_events where operation_id='${failureOperation}'`),'0');
  }finally{command('dropdb',['--if-exists',database]);for(const role of created)command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);}
});
