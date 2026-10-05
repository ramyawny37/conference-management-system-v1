'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migrationPath='supabase/migrations/20260928140000_canonical_platform_conference_creation_foundation.sql';
const sql=fs.readFileSync(path.join(root,migrationPath),'utf8');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const creation=sql.match(/create function public\.create_canonical_conference\([\s\S]*?end \$\$;/i);

test('P3B has one Platform-authorized server creation path',()=>{
  assert.ok(creation);
  assert.match(creation[0],/require_effective_module_permission\([\s\S]*?'conference','conference\.lifecycle\.create',null,null/);
  assert.match(creation[0],/validated_phase1c_device_authorization/);
  assert.doesNotMatch(creation[0],/organization_members|can_user_create_conferences|has_conference_role/);
  assert.doesNotMatch(creation[0],/device_guarded_create_organization_conference_idempotent/);
  assert.match(sql,/create or replace function platform\.execute_conference_device_operation\(/);
  assert.match(sql,/public\.create_canonical_conference\(\s*v_session\.device_id/);
  assert.doesNotMatch(sql,/create table\s+(?:public\.)?(?:conference_v2|conferences_v2|conference_people)/i);
  assert.match(sql,/drop trigger conferences_add_owner_membership on public\.conferences/);
  assert.match(sql,/drop function public\.add_conference_owner_membership\(\)/);
  assert.doesNotMatch(sql,/canonical_conference_create_capabilities|canonical_conference_create_actor/);
  assert.doesNotMatch(sql,/pg_get_functiondef|execute replace\(/i);
});

test('canonical input and initial P3A values are server constrained',()=>{
  assert.match(sql,/require_exact_jsonb_keys\([\s\S]*?'p_operation_id','p_requested_conference_id','p_organization_id',[\s\S]*?'p_name','p_start_date','p_end_date'/);
  assert.doesNotMatch(creation[0],/p_actor_user_id|p_device_authorization_id|p_status|p_revision|p_created_at|p_completed_at|p_permission/);
  assert.match(creation[0],/btrim\(coalesce\(p_name,''\)\)/);
  assert.match(creation[0],/p_end_date<p_start_date/);
  assert.match(creation[0],/'active',null,1,v_actor/);
  assert.doesNotMatch(sql,/add column\s+(?:days|nights|schedule)\b/i);
});

test('existing ledger, deterministic replay and canonical audit are reused',()=>{
  assert.match(creation[0],/public\.conference_creation_operations%rowtype/);
  assert.match(creation[0],/CANONICAL_CONFERENCE_CREATE_OPERATION_MISMATCH/);
  assert.match(creation[0],/v_prior\.initial_metadata<>v_intent/);
  assert.match(creation[0],/insert into public\.conference_creation_operations/);
  assert.match(creation[0],/insert into platform\.audit_events/);
  assert.match(creation[0],/'conference\.lifecycle\.created'/);
  assert.match(creation[0],/'permissionKey','conference\.lifecycle\.create'/);
  assert.doesNotMatch(sql,/create (?:table|schema).*audit/i);
});

test('retired local publishing consumers and unrelated domains are outside P3B',()=>{
  for(const file of ['js/supabase/snapshot-sync.js','js/sync/conference-linking-service.js','js/storage/conference-publishing-engine.js','js/storage/conference-publish-recovery.js'])assert.equal(fs.existsSync(path.join(root,file)),false,file);
  assert.doesNotMatch(sql,/\b(?:reservations|warehouse)\./i);
  assert.doesNotMatch(sql,/platform\.people|conference_people|conference_snapshots|sync_operations|sync_conflicts/i);
  assert.doesNotMatch(sql,/js\/|\.html|\.css/);
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_p3b_${process.pid}_${Date.now()}`;
const actor='10000000-0000-0000-0000-000000000001';
const device='20000000-0000-0000-0000-000000000001';
const authorization='30000000-0000-0000-0000-000000000001';
const organization='40000000-0000-0000-0000-000000000001';
const conference='50000000-0000-0000-0000-000000000001';
const operation='60000000-0000-0000-0000-000000000001';
const session='61000000-0000-0000-0000-000000000001';
const binding='62000000-0000-0000-0000-000000000001';
const validationHost=process.env.PGHOST;
const validationPort=process.env.PGPORT;
const validationUser=process.env.PGUSER;
const validationPassword=process.env.PGPASSWORD;
const connection=validationHost
  ? ['-h',validationHost,'-p',validationPort||'5432','-U',validationUser||os.userInfo().username]
  : ['-h','/tmp','-p','5432','-U',os.userInfo().username];
const cleanEnv=Object.fromEntries(Object.entries(process.env).filter(([key])=>
  !key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)
));
if(validationPassword) cleanEnv.PGPASSWORD=validationPassword;
function command(name,args){
  return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{
    encoding:'utf8',stdio:'pipe',env:cleanEnv
  }).trim();
}
function query(statement){
  return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);
}

test('isolated PostgreSQL proves authority, idempotency, audit and direct-execute security',()=>{
  const clientRoles=['anon','authenticated','service_role'];
  const createdRoles=[];
  try{
    command('psql',['-X','-At','-d','postgres','-c','select 1']);
  }catch{
    assert.fail('isolated/local PostgreSQL is required; do not silently skip');
  }
  command('createdb',[database]);
  try{
    for(const role of clientRoles){
      if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){
        query(`create role ${role} nologin`);
        createdRoles.push(role);
      }
    }
    query(`
      create extension if not exists pgcrypto;
      create schema auth; create schema platform; create schema platform_private;
      grant usage on schema public to authenticated;
      create function auth.uid() returns uuid language sql stable as \$\$
        select '${actor}'::uuid
      \$\$;
      create function auth.role() returns text language sql stable as \$\$
        select 'service_role'::text
      \$\$;
      create table auth.users(id uuid primary key);
      create table platform.profiles(user_id uuid primary key references auth.users(id),account_status text not null);
      create table platform.devices(id uuid primary key,user_id uuid not null references platform.profiles(user_id),lifecycle_status text not null,retired_at timestamptz,compromised_at timestamptz);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid not null references platform.profiles(user_id),device_id uuid not null references platform.devices(id),status text not null,revoked_at timestamptz);
      create table platform.device_key_bindings(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,public_key_thumbprint text,algorithm text,lifecycle_status text,revoked_at timestamptz,retired_at timestamptz);
      create table platform_private.device_sessions(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,binding_id uuid,token_hash bytea,purpose text,public_key_thumbprint text,revoked_at timestamptz,expires_at timestamptz);
      create table platform.audit_events(
        id uuid primary key default gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,
        subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,
        scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,
        operation_id uuid,source text
      );
      create table public.organizations(id uuid primary key,status text not null);
      create table public.organization_members(organization_id uuid,user_id uuid);
      create table public.conferences(
        id uuid primary key,name text not null,owner_id uuid not null references auth.users(id),
        organization_id uuid not null references public.organizations(id),
        start_date date,end_date date,status text not null default 'active',completed_at timestamptz,
        revision bigint not null default 1,created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),updated_by uuid,deleted_at timestamptz
      );
      create table public.conference_members(conference_id uuid,user_id uuid,role text);
      create table public.conference_creation_operations(
        id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
        operation_id uuid not null,conference_id uuid not null references public.conferences(id),
        initial_metadata jsonb not null default '{}'::jsonb,created_at timestamptz default now(),updated_at timestamptz default now(),
        unique(user_id,operation_id),unique(conference_id)
      );
      create table public.module_permission_catalog(
        permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text
      );
      create table public.module_permission_grants(id uuid);
      create table public.system_user_access(user_id uuid primary key,account_status text);
      create table public.p3b_test_context(account_approved boolean,device_approved boolean,permission_granted boolean);
      insert into public.p3b_test_context values(true,true,true);
      insert into public.module_permission_catalog values('conference.lifecycle.create','conference','active','module',null);
      insert into auth.users values('${actor}');
      insert into platform.profiles values('${actor}','approved');
      insert into platform.devices values('${device}','${actor}','active',null,null);
      insert into platform.user_device_authorizations values('${authorization}','${actor}','${device}','approved',null);
      insert into platform.device_key_bindings values('${binding}','${actor}','${device}','${authorization}','thumbprint','ECDSA_P256_SHA256','active',null,null);
      insert into platform_private.device_sessions values('${session}','${actor}','${device}','${authorization}','${binding}',decode(repeat('00',32),'hex'),'PLATFORM_DEVICE_SESSION','thumbprint',null,now()+interval '1 day');
      insert into public.system_user_access values('${actor}','approved');
      insert into public.organizations values('${organization}','active');
      create function public.add_conference_owner_membership() returns trigger language plpgsql security definer as \$\$
      begin
        if not exists(select 1 from public.organization_members where organization_id=new.organization_id and user_id=new.owner_id)
        then raise exception 'CONFERENCE_MEMBER_ORGANIZATION_REQUIRED' using errcode='42501'; end if;
        insert into public.conference_members values(new.id,new.owner_id,'owner'); return new;
      end \$\$;
      create trigger conferences_add_owner_membership after insert on public.conferences
        for each row execute function public.add_conference_owner_membership();
      create function public.can_user_create_conferences(uuid)
      returns boolean language sql stable as \$\$ select true \$\$;
      create function public.create_organization_conference_idempotent(uuid,uuid,uuid,text,jsonb)
      returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.device_guarded_create_organization_conference_idempotent(uuid,uuid,uuid,uuid,text,jsonb)
      returns jsonb language sql as \$\$ select public.create_organization_conference_idempotent(\$2,\$3,\$4,\$5,\$6) \$\$;
      create function public.require_effective_module_permission(uuid,text,text,text,text)
      returns jsonb language plpgsql stable as \$\$ declare c public.p3b_test_context%rowtype; begin
        select * into c from public.p3b_test_context;
        if not c.account_approved then raise exception 'ACCOUNT_APPROVAL_REQUIRED' using errcode='42501'; end if;
        if \$1<>'${device}'::uuid or \$2<>'conference' or \$3<>'conference.lifecycle.create'
           or \$4 is not null or \$5 is not null or not c.permission_granted
        then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if;
        return jsonb_build_object('actorUserId','${actor}','authoritySource','module_grant','grantId','70000000-0000-0000-0000-000000000001');
      end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid)
      returns uuid language sql stable as \$\$ select case when (select device_approved from public.p3b_test_context)
        and \$1='${actor}'::uuid and \$2='${device}'::uuid then '${authorization}'::uuid end \$\$;
      create function platform_private.phase1c_context_device_id()
      returns uuid language sql stable as \$\$ select '${device}'::uuid \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}')
      returns void language plpgsql immutable as \$\$ declare key text; begin
        if \$1 is null or jsonb_typeof(\$1)<>'object' then raise exception 'INVALID'; end if;
        foreach key in array \$2 loop if not \$1 ? key then raise exception 'MISSING'; end if; end loop;
        if exists(select 1 from jsonb_object_keys(\$1) item where not(item=any(\$2) or item=any(\$3))) then raise exception 'UNKNOWN'; end if;
      end \$\$;
      create function platform.execute_conference_device_operation_phase1c_core(
        p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_operation text,p_args jsonb
      ) returns jsonb language plpgsql security definer as \$\$
      declare v_session record; v_result jsonb; begin
        select '${device}'::uuid as device_id into v_session;
        case p_operation when 'existing_operation' then v_result:='{}'::jsonb;
        else raise exception 'CONFERENCE_OPERATION_NOT_ALLOWED' using errcode='42501'; end case;
        return v_result;
      end \$\$;
      create function public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text)
      returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform.execute_conference_device_operation(uuid,uuid,bytea,text,jsonb)
      returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
    `);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migrationPath)]);

    const signature='public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date)';
    for(const role of clientRoles){
      assert.equal(query(`select has_function_privilege('${role}','${signature}','EXECUTE')`),'f');
    }
    assert.equal(query(`select coalesce(bool_or(acl.grantee=0 and acl.privilege_type='EXECUTE'),false)
      from pg_proc procedure cross join lateral aclexplode(coalesce(procedure.proacl,acldefault('f',procedure.proowner))) acl
      where procedure.oid='${signature}'::regprocedure`),'f');
    assert.throws(()=>query(`set role authenticated; select public.create_canonical_conference(
      '${device}','${operation}','${conference}','${organization}','Denied','2026-11-01','2026-11-03')`),
      /permission denied for function create_canonical_conference/i);
    assert.equal(query(`select to_regclass('platform_private.canonical_conference_create_capabilities') is null`),'t');
    assert.equal(query(`select count(*) from pg_trigger where tgrelid='public.conferences'::regclass
      and tgname='conferences_add_owner_membership' and not tgisinternal`),'0');
    assert.equal(query(`select to_regprocedure('public.add_conference_owner_membership()') is null`),'t');

    query(`grant insert on public.conferences to authenticated`);
    query(`set role authenticated;
      insert into public.conferences(id,name,owner_id,organization_id)
      values('90000000-0000-0000-0000-000000000001','Direct','${actor}','${organization}')`);
    assert.equal(query(`select count(*) from public.conferences
      where id='90000000-0000-0000-0000-000000000001'`),'1');
    assert.equal(query(`select count(*) from public.conference_members
      where conference_id='90000000-0000-0000-0000-000000000001'`),'0');

    const dispatch=(overrides='')=>query(`select platform.execute_conference_device_operation(
      '${actor}','${session}',decode(repeat('00',32),'hex'),'create_canonical_conference',
      jsonb_build_object('p_operation_id','${operation}','p_requested_conference_id','${conference}',
        'p_organization_id','${organization}','p_name','  Canonical Conference  ',
        'p_start_date','2026-11-01','p_end_date','2026-11-03'${overrides}))->>'created'`);
    query(`update public.p3b_test_context set permission_granted=false`);
    assert.throws(()=>dispatch(),/MODULE_PERMISSION_REQUIRED/);
    query(`update public.p3b_test_context set permission_granted=true,account_approved=false`);
    assert.throws(()=>dispatch(),/ACCOUNT_APPROVAL_REQUIRED/);
    query(`update public.p3b_test_context set account_approved=true,device_approved=false`);
    assert.throws(()=>dispatch(),/APPROVED_DEVICE_SESSION_REQUIRED/);
    query(`update public.p3b_test_context set device_approved=true`);
    assert.equal(dispatch(),'true');
    assert.equal(query(`select name||'|'||start_date||'|'||end_date||'|'||status||'|'||coalesce(completed_at::text,'NULL')||'|'||revision||'|'||owner_id||'|'||organization_id from public.conferences where id='${conference}'`),
      `Canonical Conference|2026-11-01|2026-11-03|active|NULL|1|${actor}|${organization}`);
    assert.equal(query(`select count(*) from public.organization_members`),'0');
    assert.equal(query(`select count(*) from public.conference_members
      where conference_id='${conference}'`),'0');
    assert.equal(dispatch(),'false');
    assert.equal(query(`select count(*) from public.conferences where id='${conference}'`),'1');
    assert.equal(query(`select count(*) from platform.audit_events`),'1');
    assert.throws(()=>dispatch(`,'p_name','Different'`),/CANONICAL_CONFERENCE_CREATE_OPERATION_MISMATCH/);
    assert.throws(()=>dispatch(`,'p_actor_user_id','${actor}'`),/UNKNOWN/);
    assert.equal(query(`select actor_user_id||'|'||actor_device_authorization_id||'|'||action||'|'||(metadata->>'permissionKey')||'|'||(metadata->>'authoritySource')||'|'||operation_id from platform.audit_events`),
      `${actor}|${authorization}|conference.lifecycle.created|conference.lifecycle.create|module_grant|${operation}`);
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of createdRoles){
      command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
    }
  }
});
