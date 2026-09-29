'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migrationPath='supabase/migrations/20260928130000_canonical_server_conference_core_foundation.sql';
const sql=fs.readFileSync(path.join(root,migrationPath),'utf8');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const mutation=sql.match(/create function public\.mutate_conference_core\([\s\S]*?end \$\$;/i);

test('P3A extends the one existing Conference root without section or derived authority',()=>{
  assert.match(sql,/alter table public\.conferences[\s\S]*add column start_date date/);
  assert.doesNotMatch(sql,/create table\s+(?:public\.)?(?:conference_v2|conferences_v2|conference_people)/i);
  assert.doesNotMatch(sql,/add column\s+(?:days|nights|schedule)\b/i);
  assert.match(sql,/id','uuid'/);
  assert.match(sql,/conferences_core_status_check[\s\S]*active','completed/);
  assert.match(sql,/conferences_core_date_order_check[\s\S]*end_date>=start_date/);
  assert.match(sql,/conferences_core_revision_check check\(revision>=1\)/);
  assert.doesNotMatch(sql,/peopleDb|accommodation|transport|restaurant|airConditioning|financialV3|platform\.people|conference_person_links/i);
});

test('new mutation uses exact U2B authority and the existing protected session dispatcher',()=>{
  assert.ok(mutation);
  assert.match(mutation[0],/require_effective_module_permission\([\s\S]*?'conference','conference\.lifecycle\.manage'[\s\S]*?'conference',p_conference_id::text/);
  assert.match(mutation[0],/validated_phase1c_device_authorization/);
  assert.match(sql,/platform\.execute_conference_device_operation_phase1c_core/);
  assert.match(sql,/public\.mutate_conference_core\(v_session\.device_id/);
  assert.doesNotMatch(mutation[0],/organization_members|organizations|organization_id/);
  assert.doesNotMatch(sql,/legacy authority|\bor\s+public\.has_conference_role/i);
  assert.match(read('supabase/migrations/20260927180000_conference_platform_permission_foundation.sql'),
    /'conference\.lifecycle\.create'[\s\S]*?'module',null,true/);
});

test('actor, audit, revision and lifecycle transitions are server controlled',()=>{
  assert.match(sql,/v_actor:=\(v_context->>'actorUserId'\)::uuid/);
  assert.match(sql,/updated_by=v_actor/);
  assert.match(sql,/insert into platform\.audit_events/);
  assert.match(sql,/actor_device_authorization_id/);
  assert.match(sql,/CONFERENCE_CORE_REVISION_CONFLICT/);
  assert.match(sql,/revision=conferences\.revision\+1/);
  assert.match(sql,/CONFERENCE_LIFECYCLE_TRANSITION_INVALID/);
  assert.doesNotMatch(mutation[0],/p_actor_user_id|p_updated_by/);
  assert.match(sql,/require_exact_jsonb_keys\(p_args,array\[''p_conference_id'',''p_expected_revision'',''p_name'',''p_start_date'',''p_end_date'',''p_status''\]\)/);
});

test('P3A leaves unrelated runtime and modules outside the migration',()=>{
  assert.doesNotMatch(sql,/\b(?:reservations|warehouse)\./i);
  assert.doesNotMatch(sql,/conference_snapshots|sync_operations|sync_conflicts|conf_v5|indexeddb|localstorage/i);
  const trackedRuntime=execFileSync('git',['ls-files','-z','*.js','*.html'],{
    cwd:root,encoding:'utf8'
  }).split('\0').filter(Boolean).filter(file=>!file.startsWith('tests/'));
  for(const file of trackedRuntime){
    assert.ok(!read(file).includes('mutate_conference_core'),file);
  }
});

const postgresBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const psql=path.join(postgresBin,'psql');
const database=`conference_p3a_${process.pid}_${Date.now()}`;
const actor='10000000-0000-0000-0000-000000000001';
const device='20000000-0000-0000-0000-000000000001';
const authorization='30000000-0000-0000-0000-000000000001';
const conference='40000000-0000-0000-0000-000000000001';
const cleanEnv={...Object.fromEntries(Object.entries(process.env)
  .filter(([key])=>!key.startsWith('PG'))),PGHOST:'/tmp',PGPORT:'5432',PGDATABASE:database};
function command(name,args){
  return execFileSync(path.join(postgresBin,name),args,{encoding:'utf8',stdio:'pipe',env:cleanEnv}).trim();
}
function query(statement){
  return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);
}

test('isolated PostgreSQL enforces canonical core, concurrency and trusted attribution',
  {skip:!fs.existsSync(psql)},()=>{
  const clientRoles=['anon','authenticated','service_role'];
  const createdRoles=[];
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
      create table auth.users(id uuid primary key);
      create table platform.profiles(user_id uuid primary key references auth.users(id),account_status text not null);
      create table platform.devices(id uuid primary key,user_id uuid not null references platform.profiles(user_id));
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid not null references platform.profiles(user_id),device_id uuid not null references platform.devices(id),status text not null);
      create table platform.audit_events(
        id uuid primary key default gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,
        subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,
        scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,source text
      );
      create table public.organizations(id uuid primary key);
      create table public.conferences(
        id uuid primary key,name text not null,owner_id uuid not null references auth.users(id),
        created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
        deleted_at timestamptz,organization_id uuid references public.organizations(id)
      );
      create table public.module_permission_catalog(
        permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text
      );
      create table public.module_permission_grants(id uuid);
      insert into public.module_permission_catalog values
        ('conference.lifecycle.create','conference','active','module',null),
        ('conference.lifecycle.manage','conference','active','resource','conference');
      insert into auth.users values('${actor}');
      insert into platform.profiles values('${actor}','approved');
      insert into platform.devices values('${device}','${actor}');
      insert into platform.user_device_authorizations values('${authorization}','${actor}','${device}','approved');
      create function public.require_effective_module_permission(uuid,text,text,text,text)
      returns jsonb language plpgsql stable as \$\$ begin
        if \$1<>'${device}'::uuid or \$2<>'conference' or \$3<>'conference.lifecycle.manage'
           or \$4<>'conference' or \$5 is null then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if;
        return jsonb_build_object('actorUserId','${actor}','authoritySource','resource_grant','grantId',null);
      end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid)
      returns uuid language sql stable as \$\$ select case when \$1='${actor}'::uuid and \$2='${device}'::uuid then '${authorization}'::uuid end \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}')
      returns void language plpgsql immutable as \$\$ declare key text; begin
        if \$1 is null or jsonb_typeof(\$1)<>'object' then raise exception 'INVALID'; end if;
        foreach key in array \$2 loop if not \$1 ? key then raise exception 'MISSING'; end if; end loop;
        if exists(select 1 from jsonb_object_keys(\$1) item where not(item=any(\$2) or item=any(\$3))) then raise exception 'UNKNOWN'; end if;
      end \$\$;
      create function platform.execute_conference_device_operation_phase1c_core(
        p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_operation text,p_args jsonb
      )
      returns jsonb language plpgsql security definer as \$\$
      declare v_session record; v_result jsonb; begin
        select '${device}'::uuid as device_id into v_session;
        case p_operation when 'existing_operation' then v_result:='{}'::jsonb;
        else raise exception 'CONFERENCE_OPERATION_NOT_ALLOWED' using errcode='42501'; end case;
        return v_result;
      end \$\$;
    `);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migrationPath)]);
    const mutationSignature='public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text)';
    for(const role of clientRoles){
      assert.equal(query(`select has_function_privilege('${role}','${mutationSignature}','EXECUTE')`),'f',
        role+' must not directly execute the core mutation');
    }
    assert.equal(query(`select coalesce(bool_or(acl.grantee=0 and acl.privilege_type='EXECUTE'),false)
      from pg_proc procedure
      cross join lateral aclexplode(coalesce(procedure.proacl,acldefault('f',procedure.proowner))) acl
      where procedure.oid='${mutationSignature}'::regprocedure`),'f','PUBLIC execute must be revoked');
    assert.throws(()=>query(`set role authenticated; select public.mutate_conference_core(
      '${device}','${conference}',1,'Denied','2026-10-01','2026-10-03','active')`),
      /permission denied for function mutate_conference_core/i);
    query(`insert into public.conferences(id,name,owner_id) values('${conference}','Initial','${actor}')`);

    const mutate=(revision,status='active',extra='')=>query(`select platform.execute_conference_device_operation_phase1c_core(
      '${actor}',gen_random_uuid(),decode(repeat('00',32),'hex'),'mutate_conference_core',
      jsonb_build_object('p_conference_id','${conference}','p_expected_revision',${revision},
        'p_name','Canonical','p_start_date','2026-10-01','p_end_date','2026-10-03','p_status','${status}'${extra})
      )->>'revision'`);
    assert.equal(mutate(1),'2');
    assert.equal(query(`select start_date||'|'||end_date||'|'||status||'|'||revision||'|'||updated_by from public.conferences where id='${conference}'`),
      `2026-10-01|2026-10-03|active|2|${actor}`);
    assert.equal(query(`select platform.execute_conference_device_operation_phase1c_core(
      '${actor}',gen_random_uuid(),decode(repeat('00',32),'hex'),'mutate_conference_core',
      jsonb_build_object('p_conference_id','${conference}','p_expected_revision',2,'p_name','Canonical',
      'p_start_date','2026-10-01','p_end_date','2026-10-03','p_status','active'))->>'days'`),'3');
    assert.throws(()=>mutate(2),/CONFERENCE_CORE_REVISION_CONFLICT/);
    assert.throws(()=>mutate(3,'active',`,'p_actor_user_id','${actor}'`),/UNKNOWN/);
    assert.equal(mutate(3,'completed'),'4');
    assert.throws(()=>mutate(4,'active'),/CONFERENCE_LIFECYCLE_TRANSITION_INVALID/);
    assert.equal(query(`select count(*)||'|'||min(actor_user_id::text)||'|'||min(actor_device_authorization_id::text) from platform.audit_events`),
      `3|${actor}|${authorization}`);
    assert.throws(()=>query(`insert into public.conferences(id,name,owner_id,start_date,end_date,status,completed_at)
      values(gen_random_uuid(),'Bad','${actor}','2026-10-03','2026-10-01','future',null)`),/conferences_core_/i);
    const columns=query(`select string_agg(column_name,',' order by column_name) from information_schema.columns
      where table_schema='public' and table_name='conferences' and column_name in('days','nights','schedule')`);
    assert.equal(columns,'');
    assert.equal(query(`select count(*) from information_schema.tables where table_schema='public' and table_name in('conference_v2','conferences_v2','conference_people')`),'0');
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of createdRoles){
      command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
    }
  }
});
