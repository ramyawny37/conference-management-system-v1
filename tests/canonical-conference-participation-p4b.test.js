'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');
const root=path.join(__dirname,'..');
const migration='supabase/migrations/20260928150000_canonical_conference_participation_foundation.sql';
const sql=fs.readFileSync(path.join(root,migration),'utf8');

test('P4B is one relational participation root with existing authority',()=>{
  assert.match(sql,/create table public\.conference_participations/);
  assert.match(sql,/person_id uuid not null references platform\.people\(id\) on delete restrict/);
  assert.match(sql,/conference_id uuid not null references public\.conferences\(id\) on delete restrict/);
  assert.match(sql,/unique\(conference_id,person_id\)/);
  assert.match(sql,/status text not null default 'active' check\(status in\('active','apologized'\)\)/);
  assert.doesNotMatch(sql,/full_name|phone|gender|date_of_birth|church/);
  assert.match(sql,/'conference\.people\.view'/);
  assert.match(sql,/'conference\.people\.manage'/);
  assert.doesNotMatch(sql,/organization_members|conference_members|has_conference_role/);
  assert.doesNotMatch(sql,/conference_snapshots|peopleDb|reservations\.|accommodation|transport|warehouse\./i);
});

test('P4B uses existing dispatcher, audit and bounded operation ledger',()=>{
  for(const operation of ['list_conference_participations','create_conference_participation','set_conference_participation_status','delete_conference_participation']) assert.match(sql,new RegExp(`p_operation='${operation}'`));
  assert.match(sql,/create or replace function platform\.execute_conference_device_operation/);
  assert.doesNotMatch(sql,/create function platform\.execute_conference_device_operation_phase/i);
  assert.match(sql,/insert into platform\.audit_events/g);
  assert.match(sql,/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
  assert.match(sql,/CONFERENCE_PARTICIPATION_REVISION_CONFLICT/);
  assert.match(sql,/COMPLETED_CONFERENCE_IMMUTABLE/);
  assert.match(sql,/count\(\*\) filter\(where status='active'\)/);
  const deleteBody=sql.match(/create function public\.delete_conference_participation[\s\S]*?revoke all on function/)?.[0]||'';
  assert.doesNotMatch(deleteBody,/auth\.uid\(\)/);
  assert.match(deleteBody,/current_setting\('platform\.phase1c_context',true\)/);
  assert.match(deleteBody,/validated_phase1c_device_authorization\(v_actor,p_actor_device_id\)/);
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_p4b_${process.pid}_${Date.now()}`;
const validationHost=process.env.PGHOST;
const connection=validationHost?['-h',validationHost,'-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username]:['-h','/tmp','-p','5432','-U',os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
if(process.env.PGPASSWORD) env.PGPASSWORD=process.env.PGPASSWORD;
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)));}
function rejectsCall(call,pattern){assert.throws(call,error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves canonical participation lifecycle and security',()=>{
  try{command('psql',['-X','-At','-d','postgres','-c','select 1']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  const actor='10000000-0000-0000-0000-000000000001';
  const device='20000000-0000-0000-0000-000000000001';
  const authorization='30000000-0000-0000-0000-000000000001';
  const binding='31000000-0000-0000-0000-000000000001';
  const session='32000000-0000-0000-0000-000000000001';
  const actor2='10000000-0000-0000-0000-000000000002';
  const device2='20000000-0000-0000-0000-000000000002';
  const authorization2='30000000-0000-0000-0000-000000000002';
  const binding2='31000000-0000-0000-0000-000000000002';
  const session2='32000000-0000-0000-0000-000000000002';
  const conference='40000000-0000-0000-0000-000000000001';
  const completed='41000000-0000-0000-0000-000000000001';
  const deleted='42000000-0000-0000-0000-000000000001';
  const person='50000000-0000-0000-0000-000000000001';
  const person2='51000000-0000-0000-0000-000000000001';
  const roles=['anon','authenticated','service_role']; const created=[];
  command('createdb',[database]);
  try{
    for(const role of roles){if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}}
    query(`create schema extensions; create extension pgcrypto with schema extensions; create schema auth; create schema platform; create schema platform_private;
      create table public.p4_context(account_ok boolean,device_ok boolean,permission text,jwt_actor uuid);
      insert into public.p4_context values(true,true,'conference.people.manage','${actor}');
      create function auth.uid() returns uuid language sql stable as \$\$ select jwt_actor from public.p4_context \$\$;
      create function auth.role() returns text language sql stable as \$\$ select 'service_role'::text \$\$;
      create table auth.users(id uuid primary key);
      create table platform.profiles(user_id uuid primary key,account_status text not null);
      create table platform.devices(id uuid primary key,user_id uuid,lifecycle_status text,retired_at timestamptz,compromised_at timestamptz);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid,device_id uuid,status text,revoked_at timestamptz);
      create table platform.device_key_bindings(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,public_key_thumbprint text,algorithm text,lifecycle_status text,revoked_at timestamptz,retired_at timestamptz);
      create table platform_private.device_sessions(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,binding_id uuid,token_hash bytea,purpose text,public_key_thumbprint text,revoked_at timestamptz,expires_at timestamptz);
      create table platform.people(id uuid primary key,full_name text,revision bigint default 1,created_at timestamptz default now(),updated_at timestamptz default now(),created_by uuid,updated_by uuid);
      create table platform.audit_events(id uuid primary key default extensions.gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,request_id uuid,operation_id uuid,source text,occurred_at timestamptz default now());
      create table public.conferences(id uuid primary key,name text,owner_id uuid,organization_id uuid,start_date date,end_date date,status text,completed_at timestamptz,revision bigint,created_at timestamptz default now(),updated_at timestamptz default now(),updated_by uuid,deleted_at timestamptz);
      create table public.organization_members(organization_id uuid,user_id uuid); create table public.conference_members(conference_id uuid,user_id uuid);
      create table public.module_permission_catalog(permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text);
      insert into public.module_permission_catalog values('conference.people.view','conference','active','resource','conference'),('conference.people.manage','conference','active','resource','conference');
      insert into auth.users values('${actor}'),('${actor2}'); insert into platform.profiles values('${actor}','approved'),('${actor2}','approved');
      insert into platform.devices values('${device}','${actor}','active',null,null),('${device2}','${actor2}','active',null,null);
      insert into platform.user_device_authorizations values('${authorization}','${actor}','${device}','approved',null),('${authorization2}','${actor2}','${device2}','approved',null);
      insert into platform.device_key_bindings values('${binding}','${actor}','${device}','${authorization}','thumb','ECDSA_P256_SHA256','active',null,null),('${binding2}','${actor2}','${device2}','${authorization2}','thumb2','ECDSA_P256_SHA256','active',null,null);
      insert into platform_private.device_sessions values('${session}','${actor}','${device}','${authorization}','${binding}',decode(repeat('00',32),'hex'),'PLATFORM_DEVICE_SESSION','thumb',null,now()+interval '1 day'),('${session2}','${actor2}','${device2}','${authorization2}','${binding2}',decode(repeat('11',32),'hex'),'PLATFORM_DEVICE_SESSION','thumb2',null,now()+interval '1 day');
      insert into platform.people(id,full_name) values('${person}','Person One'),('${person2}','Person Two');
      insert into public.conferences(id,name,status,revision,deleted_at) values('${conference}','Active','active',1,null),('${completed}','Completed','completed',1,null),('${deleted}','Deleted','active',1,now());
      create function public.require_effective_module_permission(uuid,text,text,text,text) returns jsonb language plpgsql stable as \$\$ declare c public.p4_context%rowtype; derived_actor uuid; begin select * into c from public.p4_context; if not c.account_ok then raise exception 'ACCOUNT_REQUIRED' using errcode='42501'; end if; derived_actor:=case \$1 when '${device}'::uuid then '${actor}'::uuid when '${device2}'::uuid then '${actor2}'::uuid end; if derived_actor is null or \$2<>'conference' or \$3<>c.permission or \$4<>'conference' or \$5 is null then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if; return jsonb_build_object('actorUserId',derived_actor,'authoritySource','resource_grant','grantId','60000000-0000-0000-0000-000000000001'); end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language plpgsql stable as \$\$ declare c jsonb:=nullif(current_setting('platform.phase1c_context',true),'')::jsonb; enabled boolean; begin select device_ok into enabled from public.p4_context; if not enabled or c->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (c->>'user_id')::uuid is distinct from \$1 or (c->>'device_id')::uuid is distinct from \$2 then return null; end if; return case when \$1='${actor}'::uuid and \$2='${device}'::uuid then '${authorization}'::uuid when \$1='${actor2}'::uuid and \$2='${device2}'::uuid then '${authorization2}'::uuid end; end \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language plpgsql immutable as \$\$ declare k text; begin foreach k in array \$2 loop if not \$1?k then raise exception 'MISSING'; end if; end loop; if exists(select 1 from jsonb_object_keys(\$1) x where not(x=any(\$2) or x=any(\$3))) then raise exception 'UNKNOWN'; end if; end \$\$;
      create function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    const dispatch=(operation,args)=>query(`select platform.execute_conference_device_operation('${actor}','${session}',decode(repeat('00',32),'hex'),'${operation}',${args})`);
    const dispatch2=(operation,args)=>query(`select platform.execute_conference_device_operation('${actor2}','${session2}',decode(repeat('11',32),'hex'),'${operation}',${args})`);
    const signatures=['public.list_conference_participations(uuid,uuid)','public.create_conference_participation(uuid,uuid,uuid,uuid)','public.set_conference_participation_status(uuid,uuid,uuid,bigint,text)','public.delete_conference_participation(uuid,uuid,uuid,bigint)','platform_private.require_conference_participation_context(uuid,uuid,text,boolean)'];
    for(const role of roles) for(const signature of signatures) assert.equal(query(`select has_function_privilege('${role}','${signature}','EXECUTE')`),'f');
    rejects(`set role authenticated; select public.create_conference_participation('${device}',extensions.gen_random_uuid(),'${conference}','${person}')`,/permission denied/);
    query(`update public.p4_context set permission='conference.people.view'`); rejects(`select public.create_conference_participation('${device}',extensions.gen_random_uuid(),'${conference}','${person}')`,/MODULE_PERMISSION_REQUIRED/);
    query(`update public.p4_context set permission='conference.people.manage'`);
    query(`update public.p4_context set account_ok=false`); rejectsCall(()=>dispatch('create_conference_participation',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_conference_id','${conference}','p_person_id','${person}')`),/ACCOUNT_REQUIRED/);
    query(`update public.p4_context set account_ok=true,device_ok=false`); rejectsCall(()=>dispatch('create_conference_participation',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_conference_id','${conference}','p_person_id','${person}')`),/APPROVED_DEVICE_SESSION_REQUIRED/);
    query(`update public.p4_context set device_ok=true`);
    const op1='70000000-0000-0000-0000-000000000001';
    const createdRow=JSON.parse(dispatch('create_conference_participation',`jsonb_build_object('p_operation_id','${op1}','p_conference_id','${conference}','p_person_id','${person}')`));
    assert.equal(createdRow.status,'active'); assert.equal(createdRow.revision,1);
    assert.deepEqual(JSON.parse(dispatch('create_conference_participation',`jsonb_build_object('p_operation_id','${op1}','p_conference_id','${conference}','p_person_id','${person}')`)),createdRow);
    rejectsCall(()=>dispatch('create_conference_participation',`jsonb_build_object('p_operation_id','${op1}','p_conference_id','${conference}','p_person_id','${person2}')`),/OPERATION_MISMATCH/);
    rejectsCall(()=>dispatch('create_conference_participation',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_conference_id','${conference}','p_person_id','${person}')`),/ALREADY_EXISTS/);
    rejectsCall(()=>dispatch('create_conference_participation',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_conference_id','${conference}','p_person_id','ffffffff-ffff-ffff-ffff-ffffffffffff')`),/PLATFORM_PERSON_NOT_FOUND/);
    rejectsCall(()=>dispatch('create_conference_participation',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_conference_id','ffffffff-ffff-ffff-ffff-ffffffffffff','p_person_id','${person2}')`),/CONFERENCE_NOT_FOUND/);
    const op2='70000000-0000-0000-0000-000000000002';
    const apologized=JSON.parse(dispatch('set_conference_participation_status',`jsonb_build_object('p_operation_id','${op2}','p_participation_id','${createdRow.participationId}','p_expected_revision',1,'p_status','apologized')`)); assert.equal(apologized.revision,2);
    rejectsCall(()=>dispatch('set_conference_participation_status',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_participation_id','${createdRow.participationId}','p_expected_revision',1,'p_status','active')`),/REVISION_CONFLICT/);
    query(`update public.p4_context set permission='conference.people.view'`);
    const listed=JSON.parse(dispatch('list_conference_participations',`jsonb_build_object('p_conference_id','${conference}')`)); assert.equal(listed.totalCount,1); assert.equal(listed.activeCount,0); assert.equal(listed.apologizedCount,1); assert.equal(listed.items.length,1);
    query(`update public.p4_context set permission='conference.people.manage'`);
    const active=JSON.parse(dispatch('set_conference_participation_status',`jsonb_build_object('p_operation_id','70000000-0000-0000-0000-000000000003','p_participation_id','${createdRow.participationId}','p_expected_revision',2,'p_status','active')`)); assert.equal(active.revision,3);
    rejectsCall(()=>dispatch('create_conference_participation',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_conference_id','${completed}','p_person_id','${person2}')`),/COMPLETED_CONFERENCE_IMMUTABLE/);
    const completedParticipation=query(`insert into public.conference_participations(conference_id,person_id,created_by,updated_by) values('${completed}','${person2}','${actor}','${actor}') returning id`).split('\n')[0];
    rejectsCall(()=>dispatch('set_conference_participation_status',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_participation_id','${completedParticipation}','p_expected_revision',1,'p_status','apologized')`),/COMPLETED_CONFERENCE_IMMUTABLE/);
    rejectsCall(()=>dispatch('delete_conference_participation',`jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_participation_id','${completedParticipation}','p_expected_revision',1)`),/COMPLETED_CONFERENCE_IMMUTABLE/);
    query(`update public.p4_context set permission='conference.people.view'`); assert.equal(JSON.parse(dispatch('list_conference_participations',`jsonb_build_object('p_conference_id','${completed}')`)).totalCount,1); rejectsCall(()=>dispatch('list_conference_participations',`jsonb_build_object('p_conference_id','${deleted}')`),/CONFERENCE_NOT_FOUND/);
    query(`update public.p4_context set permission='conference.people.manage'`);
    const op4='70000000-0000-0000-0000-000000000004'; const deletedResult=JSON.parse(dispatch('delete_conference_participation',`jsonb_build_object('p_operation_id','${op4}','p_participation_id','${createdRow.participationId}','p_expected_revision',3)`)); assert.equal(deletedResult.deleted,true);
    query(`update public.p4_context set jwt_actor='${actor2}'`);
    assert.deepEqual(JSON.parse(dispatch('delete_conference_participation',`jsonb_build_object('p_operation_id','${op4}','p_participation_id','${createdRow.participationId}','p_expected_revision',3)`)),deletedResult);
    rejectsCall(()=>dispatch('delete_conference_participation',`jsonb_build_object('p_operation_id','${op4}','p_participation_id','${createdRow.participationId}','p_expected_revision',2)`),/OPERATION_MISMATCH/);
    query(`update public.p4_context set device_ok=false`);
    rejectsCall(()=>dispatch('delete_conference_participation',`jsonb_build_object('p_operation_id','${op4}','p_participation_id','${createdRow.participationId}','p_expected_revision',3)`),/APPROVED_DEVICE_SESSION_REQUIRED/);
    query(`update public.p4_context set device_ok=true,permission='conference.people.view'`);
    rejectsCall(()=>dispatch('delete_conference_participation',`jsonb_build_object('p_operation_id','${op4}','p_participation_id','${createdRow.participationId}','p_expected_revision',3)`),/MODULE_PERMISSION_REQUIRED/);
    query(`update public.p4_context set permission='conference.people.manage'`);
    rejectsCall(()=>dispatch2('delete_conference_participation',`jsonb_build_object('p_operation_id','${op4}','p_participation_id','${createdRow.participationId}','p_expected_revision',3)`),/CONFERENCE_PARTICIPATION_NOT_FOUND/);
    assert.equal(query(`select count(*) from platform.people where id='${person}'`),'1');
    assert.equal(query(`select string_agg(action||':'||amount,',' order by action) from (select action,count(*) amount from platform.audit_events group by action) audit_counts`),'conference.participation.created:1,conference.participation.deleted:1,conference.participation.status_changed:2');
    assert.equal(query(`select count(*) from platform.audit_events where actor_user_id='${actor}' and actor_device_authorization_id='${authorization}' and metadata->>'permissionKey'='conference.people.manage'`),'4');
    assert.equal(query('select count(*) from public.organization_members'),'0'); assert.equal(query('select count(*) from public.conference_members'),'0');
  }finally{command('dropdb',['--if-exists',database]); for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);}
});
