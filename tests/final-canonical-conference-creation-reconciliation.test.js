'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migrationPath='supabase/migrations/20261009123000_final_canonical_conference_creation_reconciliation.sql';
const sql=fs.readFileSync(path.join(root,migrationPath),'utf8');
const creation=sql.match(/create or replace function public\.create_canonical_conference\([\s\S]*?end \$\$;/i);

test('one final creation implementation uses only canonical Platform authority',()=>{
  assert.ok(creation);
  assert.equal((sql.match(/create or replace function public\.create_canonical_conference\(/gi)||[]).length,1);
  assert.match(creation[0],/require_effective_module_permission\([\s\S]*?'conference','conference\.lifecycle\.create',null,null/);
  assert.match(creation[0],/validated_phase1c_device_authorization/);
  assert.match(creation[0],/conference\.access\.view[\s\S]*conference\.lifecycle\.manage/);
  assert.match(creation[0],/insert into public\.module_permission_grants/);
  assert.match(creation[0],/insert into platform\.audit_events/);
  assert.doesNotMatch(creation[0],/conference_members|is_conference_member|has_conference_role|organization_members|owner.?role/i);
  assert.doesNotMatch(sql,/create (?:or replace )?function public\.(?:create_organization_conference_idempotent|device_guarded_create_organization_conference_idempotent)|conference_snapshots|sync_operations|sync_conflicts|drop[\s\S]{0,80}\bcascade\b/i);
});

test('the current operation contract has one protected canonical creation owner',()=>{
  const contract=fs.readFileSync(path.join(root,'js/supabase/platform-device-operation-contract.js'),'utf8');
  const conferenceEdge=fs.readFileSync(path.join(root,'supabase/functions/conference-device-operation/index.ts'),'utf8');
  const platformEdge=fs.readFileSync(path.join(root,'supabase/functions/platform-device-operation/index.ts'),'utf8');
  for(const source of [contract,conferenceEdge,platformEdge])
    assert.equal((source.match(/['"]create_canonical_conference['"]/g)||[]).length,1);
  assert.match(contract,/public\.create_canonical_conference\(uuid,uuid,uuid,uuid,text,date,date\)/);
  assert.match(sql,/platform\.execute_conference_device_operation\(uuid,uuid,bytea,text,jsonb\)/);
  assert.match(sql,/platform_private\.route_canonical_conference_operation\([\s\n]*uuid,uuid,bytea,uuid,text,jsonb/);
  const router=sql.match(/create or replace function platform_private\.route_canonical_conference_operation\([\s\S]*?end \$\$;/i)[0];
  for(const operation of ['create_canonical_conference','mutate_conference_core','list_accessible_conferences'])
    assert.equal((router.match(new RegExp(`p_operation='${operation}'`,'g'))||[]).length,1);
  assert.match(router,/platform\.execute_conference_device_operation_phase1c_core/);
  assert.doesNotMatch(sql,/pg_get_functiondef|execute replace\(|FINAL_CANONICAL_CONFERENCE_DISPATCH_PRECONDITION_FAILED/);
  const operations=[...contract.matchAll(/\['([^']+)','public\.[^']+'\]/g)].map(match=>match[1]);
  for(const operation of operations){
    assert.equal((router.match(new RegExp(`'${operation}'`,'g'))||[]).length,1,operation);
    for(const edge of [conferenceEdge,platformEdge])
      assert.equal((edge.match(new RegExp(`'${operation}'`,'g'))||[]).length,1,operation);
  }
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_final_create_${process.pid}_${Date.now()}`;
const actor='10000000-0000-0000-0000-000000000001';
const device='20000000-0000-0000-0000-000000000001';
const authorization='30000000-0000-0000-0000-000000000001';
const organization='40000000-0000-0000-0000-000000000001';
const conference='50000000-0000-0000-0000-000000000001';
const operation='60000000-0000-0000-0000-000000000001';
const session='61000000-0000-0000-0000-000000000001';
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe'}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}

test('disposable PostgreSQL proves final creation, grants, audit, replay and zero legacy side effects',()=>{
  const roles=[];
  command('createdb',[database]);
  try{
    for(const role of ['anon','authenticated','service_role']){
      if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){
        query(`create role ${role} nologin`);roles.push(role);
      }
    }
    query(`
      create extension if not exists pgcrypto;
      create schema auth; create schema platform; create schema platform_private;
      create function auth.role() returns text language sql stable as \$\$select 'service_role'::text\$\$;
      create table auth.users(id uuid primary key);
      create table platform.profiles(user_id uuid primary key,account_status text);
      create table platform.devices(id uuid primary key,user_id uuid,lifecycle_status text,retired_at timestamptz,compromised_at timestamptz);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid,device_id uuid,status text,revoked_at timestamptz);
      create table platform.device_key_bindings(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,public_key_thumbprint text,algorithm text,lifecycle_status text,revoked_at timestamptz,retired_at timestamptz);
      create table platform_private.device_sessions(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,binding_id uuid,public_key_thumbprint text,purpose text,token_hash bytea,revoked_at timestamptz,expires_at timestamptz);
      create table platform.audit_events(id uuid primary key default gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,operation_id uuid,source text);
      create table public.organizations(id uuid primary key,status text);
      create table public.conferences(id uuid primary key,name text,owner_id uuid,organization_id uuid,start_date date,end_date date,status text,completed_at timestamptz,revision bigint,created_at timestamptz default now(),updated_at timestamptz default now(),updated_by uuid,deleted_at timestamptz);
      create table public.conference_creation_operations(id uuid primary key default gen_random_uuid(),user_id uuid,operation_id uuid,conference_id uuid,initial_metadata jsonb,created_at timestamptz default now(),updated_at timestamptz default now(),unique(user_id,operation_id),unique(conference_id));
      create table public.module_permission_catalog(permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text);
      create table public.module_permission_grants(grant_id uuid primary key default gen_random_uuid(),user_id uuid,module_key text,permission_key text,resource_type text,resource_id text,granted_by uuid,granted_by_device_id uuid,granted_at timestamptz default now(),revoked_at timestamptz,revoked_by uuid,revoked_by_device_id uuid,revocation_reason text);
      create unique index module_permission_grants_active_resource_scope_uidx on public.module_permission_grants(user_id,module_key,permission_key,resource_type,resource_id) where revoked_at is null and resource_type is not null and resource_id is not null;
      create table public.final_create_test_context(permission_granted boolean,device_approved boolean);
      insert into public.final_create_test_context values(true,true);
      insert into auth.users values('${actor}');
      insert into platform.profiles values('${actor}','approved');
      insert into platform.devices values('${device}','${actor}','active',null,null);
      insert into platform.user_device_authorizations values('${authorization}','${actor}','${device}','approved',null);
      insert into platform.device_key_bindings values('31000000-0000-0000-0000-000000000001','${actor}','${device}','${authorization}','thumbprint','ECDSA_P256_SHA256','active',null,null);
      insert into platform_private.device_sessions values('${session}','${actor}','${device}','${authorization}','31000000-0000-0000-0000-000000000001','thumbprint','PLATFORM_DEVICE_SESSION',decode(repeat('00',32),'hex'),null,now()+interval '1 day');
      insert into public.organizations values('${organization}','active');
      insert into public.module_permission_catalog values
        ('conference.lifecycle.create','conference','active','module',null),
        ('conference.access.view','conference','active','resource','conference'),
        ('conference.lifecycle.manage','conference','active','resource','conference');
      create function public.require_effective_module_permission(uuid,text,text,text,text) returns jsonb language plpgsql stable as \$\$
      begin
        if not (select permission_granted from public.final_create_test_context) or \$1<>'${device}'::uuid or \$2<>'conference' or \$3<>'conference.lifecycle.create' or \$4 is not null or \$5 is not null then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if;
        return jsonb_build_object('actorUserId','${actor}','authoritySource','module_grant','grantId','70000000-0000-0000-0000-000000000001');
      end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql stable as \$\$select case when (select device_approved from public.final_create_test_context) and \$1='${actor}'::uuid and \$2='${device}'::uuid then '${authorization}'::uuid end\$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language plpgsql immutable as \$\$declare key text;begin if \$1 is null or jsonb_typeof(\$1)<>'object' then raise exception 'INVALID';end if;foreach key in array \$2 loop if not \$1 ? key then raise exception 'MISSING';end if;end loop;if exists(select 1 from jsonb_object_keys(\$1) item where not(item=any(\$2) or item=any(\$3))) then raise exception 'UNKNOWN';end if;end\$\$;
      create function public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text) returns jsonb language sql as \$\$select jsonb_build_object('operation','mutate','device',\$1,'operationId',\$2)\$\$;
      revoke all on function public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text) from public,anon,authenticated,service_role;
      create function public.list_accessible_conferences(uuid) returns jsonb language sql as \$\$select jsonb_build_array(jsonb_build_object('operation','discovery','device',\$1))\$\$;
      create function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) returns jsonb language plpgsql as \$\$begin raise exception 'CONFERENCE_OPERATION_NOT_ALLOWED' using errcode='42501';end\$\$;
      create function platform.execute_conference_device_operation(p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as \$\$
      declare v_session platform_private.device_sessions%rowtype;
      begin
        if auth.role() is distinct from 'service_role' then raise exception 'CONFERENCE_OPERATION_BACKEND_REQUIRED' using errcode='42501';end if;
        select * into v_session from platform_private.device_sessions where id=p_session_id and user_id=p_user_id and token_hash=p_token_hash and revoked_at is null and expires_at>statement_timestamp();
        if not found then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501';end if;
        return platform.execute_conference_device_operation_phase1c_core(p_user_id,p_session_id,p_token_hash,p_operation,p_args);
      end\$\$;
    `);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migrationPath)]);

    const signature='public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date)';
    for(const role of ['public','anon','authenticated','service_role'])
      assert.equal(query(`select has_function_privilege('${role}','${signature}','execute')`),'f');
    for(const role of ['public','anon','authenticated','service_role'])
      assert.equal(query(`select has_function_privilege('${role}','public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text)','execute')`),'f');
    assert.equal(query(`select regexp_count(pg_get_functiondef('platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)'::regprocedure),'route_canonical_conference_operation')`),'1');
    assert.equal(query(`select count(*) from pg_proc where pronamespace='platform_private'::regnamespace and proname='route_canonical_conference_operation'`),'1');
    const routerDefinition=query(`select pg_get_functiondef('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure)`);
    for(const operationName of ['create_canonical_conference','mutate_conference_core','list_accessible_conferences'])
      assert.equal((routerDefinition.match(new RegExp(`p_operation\\s*=\\s*'${operationName}'`,'g'))||[]).length,1);
    const dispatch=(extra='')=>query(`select platform.execute_conference_device_operation('${actor}','${session}',decode(repeat('00',32),'hex'),'create_canonical_conference',jsonb_build_object('p_operation_id','${operation}','p_requested_conference_id','${conference}','p_organization_id','${organization}','p_name','  Final Conference  ','p_start_date','2026-11-01','p_end_date','2026-11-03'${extra}))->>'created'`);
    query(`update public.final_create_test_context set permission_granted=false`);
    assert.throws(()=>dispatch(),/MODULE_PERMISSION_REQUIRED/);
    query(`update public.final_create_test_context set permission_granted=true,device_approved=false`);
    assert.throws(()=>dispatch(),/APPROVED_DEVICE_SESSION_REQUIRED/);
    query(`update public.final_create_test_context set device_approved=true`);
    assert.equal(dispatch(),'true');
    assert.equal(query(`select count(*) from public.conferences where id='${conference}' and name='Final Conference' and owner_id='${actor}' and organization_id='${organization}' and status='active' and revision=1`),'1');
    assert.equal(query(`select string_agg(permission_key,',' order by permission_key) from public.module_permission_grants where user_id='${actor}' and resource_type='conference' and resource_id='${conference}' and revoked_at is null`),'conference.access.view,conference.lifecycle.manage');
    assert.equal(query(`select count(*) from platform.audit_events where action='conference.lifecycle.created' and actor_user_id='${actor}' and actor_device_authorization_id='${authorization}' and operation_id='${operation}' and metadata->>'permissionKey'='conference.lifecycle.create'`),'1');
    assert.equal(dispatch(),'false');
    assert.equal(query(`select count(*) from public.conferences where id='${conference}'`),'1');
    assert.equal(query(`select count(*) from public.module_permission_grants where resource_id='${conference}'`),'2');
    assert.equal(query(`select count(*) from platform.audit_events where operation_id='${operation}'`),'1');
    assert.throws(()=>dispatch(`,'p_name','Different'`),/CANONICAL_CONFERENCE_CREATE_OPERATION_MISMATCH/);
    assert.throws(()=>dispatch(`,'p_actor_user_id','${actor}'`),/UNKNOWN/);
    assert.match(query(`select platform.execute_conference_device_operation('${actor}','${session}',decode(repeat('00',32),'hex'),'mutate_conference_core',jsonb_build_object('p_operation_id','62000000-0000-0000-0000-000000000001','p_conference_id','${conference}','p_expected_revision',1,'p_name','Changed','p_place','Hall','p_start_date','2026-11-01','p_end_date','2026-11-03','p_status','active'))->>'operation'`),/mutate/);
    assert.match(query(`select platform.execute_conference_device_operation('${actor}','${session}',decode(repeat('00',32),'hex'),'list_accessible_conferences','{}'::jsonb)->0->>'operation'`),/discovery/);
    assert.throws(()=>query(`select platform.execute_conference_device_operation('${actor}','${session}',decode(repeat('00',32),'hex'),'unknown_conference_operation','{}'::jsonb)`),/CONFERENCE_OPERATION_NOT_ALLOWED/);
    assert.equal(query(`select to_regclass('public.conference_members') is null and to_regprocedure('public.is_conference_member(uuid)') is null`),'t');
    assert.equal(query(`select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('has_conference_role','create_organization_conference_idempotent','device_guarded_create_organization_conference_idempotent')`),'t');
    assert.equal(query(`select to_regclass('public.conference_snapshots') is null and to_regclass('public.sync_operations') is null and to_regclass('public.sync_conflicts') is null`),'t');
  } finally {
    command('dropdb',['--if-exists',database]);
    for(const role of roles)command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
  }
});
