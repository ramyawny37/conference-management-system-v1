'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration='supabase/migrations/20260928160000_canonical_conference_routing_consolidation.sql';
const sql=fs.readFileSync(path.join(root,migration),'utf8');
const routerSignature='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)';

test('P4C creates one internal canonical router and preserves the external signature',()=>{
  assert.match(sql,/create function platform_private\.route_canonical_conference_operation\(/);
  assert.match(sql,/create or replace function platform\.execute_conference_device_operation\(\s*p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_operation text,p_args jsonb\s*\)/);
  assert.match(sql,/revoke all on function platform_private\.route_canonical_conference_operation\([\s\S]*?from public,anon,authenticated,service_role;/);
  assert.match(sql,/grant execute on function platform\.execute_conference_device_operation\([\s\S]*?to service_role;/);
  assert.doesNotMatch(sql,/pg_get_functiondef|create\s+table|alter\s+table|conference_participation_operations|conference_creation_operations/i);
});

test('P4C moves all canonical selection behind one extension point and retains legacy fallback',()=>{
  const operations=[
    'create_canonical_conference','mutate_conference_core',
    'list_conference_participations','create_conference_participation',
    'set_conference_participation_status','delete_conference_participation'
  ];
  for(const operation of operations) assert.match(sql,new RegExp(`p_operation='${operation}'`));
  assert.match(sql,/return platform\.execute_conference_device_operation_phase1c_core\(\s*p_user_id,p_session_id,p_token_hash,p_operation,p_args\s*\)/);
  const outer=sql.split('create or replace function platform.execute_conference_device_operation(',2)[1];
  assert.match(outer,/return platform_private\.route_canonical_conference_operation\(/);
  for(const operation of operations) assert.doesNotMatch(outer,new RegExp(`p_operation='${operation}'`));
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_p4c_${process.pid}_${Date.now()}`;
const validationHost=process.env.PGHOST;
const connection=validationHost?['-h',validationHost,'-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username]:['-h','/tmp','-p','5432','-U',os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
if(process.env.PGPASSWORD) env.PGPASSWORD=process.env.PGPASSWORD;
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function rejectsCall(call,pattern){assert.throws(call,error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves routing, privileges, fallback and session boundary',()=>{
  try{command('psql',['-X','-At','-d','postgres','-c','select 1']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  const actor='10000000-0000-0000-0000-000000000001';
  const device='20000000-0000-0000-0000-000000000001';
  const authorization='30000000-0000-0000-0000-000000000001';
  const binding='31000000-0000-0000-0000-000000000001';
  const session='32000000-0000-0000-0000-000000000001';
  const conference='40000000-0000-0000-0000-000000000001';
  const person='50000000-0000-0000-0000-000000000001';
  const participation='60000000-0000-0000-0000-000000000001';
  const operation='70000000-0000-0000-0000-000000000001';
  const organization='80000000-0000-0000-0000-000000000001';
  const roles=['anon','authenticated','service_role'];
  const created=[];
  command('createdb',[database]);
  try{
    for(const role of roles){if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}}
    query(`create schema auth; create schema platform; create schema platform_private;
      create table public.p4c_runtime(backend_role text not null,permission_ok boolean not null);
      insert into public.p4c_runtime values('service_role',true);
      create table public.p4c_calls(operation text not null,device_id uuid not null);
      create function auth.role() returns text language sql stable as \$\$ select backend_role from public.p4c_runtime \$\$;
      create table platform.profiles(user_id uuid primary key,account_status text not null);
      create table platform.devices(id uuid primary key,user_id uuid,lifecycle_status text,retired_at timestamptz,compromised_at timestamptz);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid,device_id uuid,status text,revoked_at timestamptz);
      create table platform.device_key_bindings(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,public_key_thumbprint text,algorithm text,lifecycle_status text,revoked_at timestamptz,retired_at timestamptz);
      create table platform_private.device_sessions(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,binding_id uuid,token_hash bytea,purpose text,public_key_thumbprint text,revoked_at timestamptz,expires_at timestamptz);
      insert into platform.profiles values('${actor}','approved');
      insert into platform.devices values('${device}','${actor}','active',null,null);
      insert into platform.user_device_authorizations values('${authorization}','${actor}','${device}','approved',null);
      insert into platform.device_key_bindings values('${binding}','${actor}','${device}','${authorization}','thumb','ECDSA_P256_SHA256','active',null,null);
      insert into platform_private.device_sessions values('${session}','${actor}','${device}','${authorization}','${binding}',decode(repeat('00',32),'hex'),'PLATFORM_DEVICE_SESSION','thumb',null,now()+interval '1 day');
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language plpgsql immutable as \$\$ declare k text; begin foreach k in array \$2 loop if not \$1?k then raise exception 'MISSING_ARGUMENT' using errcode='22023'; end if; end loop; if exists(select 1 from jsonb_object_keys(\$1) x where not(x=any(\$2) or x=any(\$3))) then raise exception 'UNKNOWN_ARGUMENT' using errcode='22023'; end if; end \$\$;
      create function public.p4c_record(text,uuid) returns jsonb language plpgsql as \$\$ begin if not (select permission_ok from public.p4c_runtime) then raise exception 'CANONICAL_PERMISSION_REQUIRED' using errcode='42501'; end if; insert into public.p4c_calls values(\$1,\$2); return jsonb_build_object('operation',\$1,'deviceId',\$2); end \$\$;
      create function public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date) returns jsonb language sql as \$\$ select public.p4c_record('create_canonical_conference',\$1) \$\$;
      create function public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text) returns jsonb language sql as \$\$ select public.p4c_record('mutate_conference_core',\$1) \$\$;
      create function public.list_conference_participations(uuid,uuid) returns jsonb language sql as \$\$ select public.p4c_record('list_conference_participations',\$1) \$\$;
      create function public.create_conference_participation(uuid,uuid,uuid,uuid) returns jsonb language sql as \$\$ select public.p4c_record('create_conference_participation',\$1) \$\$;
      create function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) returns jsonb language sql as \$\$ select public.p4c_record('set_conference_participation_status',\$1) \$\$;
      create function public.delete_conference_participation(uuid,uuid,uuid,bigint) returns jsonb language sql as \$\$ select public.p4c_record('delete_conference_participation',\$1) \$\$;
      create function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) returns jsonb language plpgsql as \$\$ begin if \$4='legacy_operation' then return jsonb_build_object('operation','legacy_operation'); end if; raise exception 'CONFERENCE_OPERATION_NOT_ALLOWED' using errcode='42501'; end \$\$;
      create function platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    assert.equal(query(`select to_regprocedure('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)') is not null`),'t');
    assert.equal(query(`select to_regprocedure('${routerSignature}') is not null`),'t');
    assert.equal(query(`select not exists(select 1 from pg_proc function join lateral aclexplode(function.proacl) privilege on true where function.oid='${routerSignature}'::regprocedure and privilege.grantee=0 and privilege.privilege_type='EXECUTE')`),'t');
    for(const role of roles) assert.equal(query(`select has_function_privilege('${role}','${routerSignature}','EXECUTE')`),'f');
    assert.equal(query(`select has_function_privilege('service_role','platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)','EXECUTE')`),'t');
    assert.equal(query(`select not exists(select 1 from pg_proc function join lateral aclexplode(function.proacl) privilege on true where function.oid='platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)'::regprocedure and privilege.grantee=0 and privilege.privilege_type='EXECUTE')`),'t');
    for(const role of ['anon','authenticated']) assert.equal(query(`select has_function_privilege('${role}','platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)','EXECUTE')`),'f');
    const dispatch=(name,args)=>JSON.parse(query(`select platform.execute_conference_device_operation('${actor}','${session}',decode(repeat('00',32),'hex'),'${name}',${args})`));
    const cases=[
      ['create_canonical_conference',`jsonb_build_object('p_operation_id','${operation}','p_requested_conference_id','${conference}','p_organization_id','${organization}','p_name','Conference','p_start_date','2027-01-01','p_end_date','2027-01-02')`],
      ['mutate_conference_core',`jsonb_build_object('p_conference_id','${conference}','p_expected_revision',1,'p_name','Conference','p_start_date','2027-01-01','p_end_date','2027-01-02','p_status','active')`],
      ['list_conference_participations',`jsonb_build_object('p_conference_id','${conference}')`],
      ['create_conference_participation',`jsonb_build_object('p_operation_id','${operation}','p_conference_id','${conference}','p_person_id','${person}')`],
      ['set_conference_participation_status',`jsonb_build_object('p_operation_id','${operation}','p_participation_id','${participation}','p_expected_revision',1,'p_status','apologized')`],
      ['delete_conference_participation',`jsonb_build_object('p_operation_id','${operation}','p_participation_id','${participation}','p_expected_revision',2)`]
    ];
    for(const [name,args] of cases){const result=dispatch(name,args); assert.equal(result.operation,name); assert.equal(result.deviceId,device);}
    assert.equal(query('select count(*) from public.p4c_calls'),'6');
    assert.deepEqual(dispatch('legacy_operation',`'{}'::jsonb`),{operation:'legacy_operation'});
    rejectsCall(()=>dispatch('unknown_operation',`'{}'::jsonb`),/CONFERENCE_OPERATION_NOT_ALLOWED/);
    query(`update public.p4c_runtime set backend_role='authenticated'`);
    rejectsCall(()=>dispatch('list_conference_participations',`jsonb_build_object('p_conference_id','${conference}')`),/CONFERENCE_OPERATION_BACKEND_REQUIRED/);
    query(`update public.p4c_runtime set backend_role='service_role'`);
    rejectsCall(()=>query(`select platform.execute_conference_device_operation('${actor}','${session}',decode(repeat('11',32),'hex'),'list_conference_participations',jsonb_build_object('p_conference_id','${conference}'))`),/DEVICE_SESSION_INVALID/);
    query(`update public.p4c_runtime set permission_ok=false`);
    rejectsCall(()=>dispatch('list_conference_participations',`jsonb_build_object('p_conference_id','${conference}')`),/CANONICAL_PERMISSION_REQUIRED/);
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
  }
});
