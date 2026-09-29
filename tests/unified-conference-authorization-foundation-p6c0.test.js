'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const migration='supabase/migrations/20260930120000_unified_conference_authorization_foundation.sql';
const sql=read(migration);

test('P6C0 changes the existing resolver without creating a parallel authority system',()=>{
  assert.match(sql,/create or replace function public\.require_effective_module_permission/);
  assert.doesNotMatch(sql,/create\s+(?:table|schema|policy|trigger)|insert into public\.module_permission_grants/i);
  assert.doesNotMatch(sql,/conference_members|conference_participations|organization_members|manager|viewer/i);
  assert.match(sql,/require_current_approved_device\(p_actor_device_id\)/);
  assert.match(sql,/require_module_permission\([\s\S]*?'module\.access'/);
  assert.match(sql,/conference\.owner_id=actor_id/);
  assert.match(sql,/'authoritySource', 'conference_owner'/);
});

test('all P3 through P6B0 canonical operations already use exact Platform permissions',()=>{
  const contracts=[
    ['supabase/migrations/20260928130000_canonical_server_conference_core_foundation.sql','conference.lifecycle.manage'],
    ['supabase/migrations/20260928140000_canonical_platform_conference_creation_foundation.sql','conference.lifecycle.create'],
    ['supabase/migrations/20260928150000_canonical_conference_participation_foundation.sql','conference.people.manage'],
    ['supabase/migrations/20260929120000_canonical_conference_accommodation_protected_mutations.sql','conference.accommodation.manage'],
    ['supabase/migrations/20260929170000_canonical_conference_core_read_edge_foundation.sql','conference.access.view']
  ];
  for(const [file,permission] of contracts){
    const source=read(file);
    assert.match(source,/require_effective_module_permission|require_conference_(?:participation|accommodation)_context/);
    assert.ok(source.includes(permission),file+' '+permission);
  }
});

test('one dispatcher and one device session remain shared by Conference, Warehouse and Reservations',()=>{
  const conferenceEdge=read('supabase/functions/conference-device-operation/index.ts');
  const platformEdge=read('supabase/functions/platform-device-operation/index.ts');
  assert.match(conferenceEdge,/\.rpc\('execute_conference_device_operation'/);
  assert.match(platformEdge,/\.rpc\('execute_device_operation'/);
  assert.doesNotMatch(sql,/execute_device_operation|device_session|create table/i);
  assert.match(read('supabase/migrations/20260829140200_warehouse_v1_guarded_rpc.sql'),/require_effective_module_permission/);
  assert.match(read('supabase/migrations/20260915220000_reservations_authorization_architecture_reconciliation.sql'),/require_effective_module_permission/);
});

test('legacy role and boolean capability consumers remain explicitly temporary',()=>{
  const members=read('js/sync/conference-members-service.js');
  const activation=read('js/sync/conference-activation-authorization.js');
  const queue=read('js/sync/conference-queue-integration.js');
  for(const capability of ['canManageMembers','canSync','canResolveConflicts','canAcquireLock'])assert.ok(members.includes(capability));
  assert.match(activation,/CLOUD_ROLES=\['owner','manager','viewer','accommodation_viewer','transport_viewer'\]/);
  assert.match(queue,/\['owner','manager'\]/);
  assert.doesNotMatch(sql,/canManageMembers|canSync|canResolveConflicts|canAcquireLock/);
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_p6c0_${process.pid}_${Date.now()}`;
const ids={
  owner:'10000000-0000-4000-8000-000000000001',grantee:'10000000-0000-4000-8000-000000000002',
  participant:'10000000-0000-4000-8000-000000000003',legacy:'10000000-0000-4000-8000-000000000004',
  other:'10000000-0000-4000-8000-000000000005',conferenceA:'20000000-0000-4000-8000-000000000001',
  conferenceB:'20000000-0000-4000-8000-000000000002',badDevice:'30000000-0000-4000-8000-000000000099'
};
const device=user=>user.replace(/^10000000/,'30000000');
const validationHost=process.env.PGHOST;
const validationPort=process.env.PGPORT;
const validationUser=process.env.PGUSER;
const validationPassword=process.env.PGPASSWORD;
const connection=validationHost
  ?['-h',validationHost,'-p',validationPort||'5432','-U',validationUser||os.userInfo().username]
  :['-h','/tmp','-p','5432','-U',os.userInfo().username];
const cleanEnv=Object.fromEntries(Object.entries(process.env).filter(([key])=>
  !key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)
));
if(validationPassword)cleanEnv.PGPASSWORD=validationPassword;
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env:cleanEnv}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}

test('disposable PostgreSQL proves grants, isolation, participant separation, legacy denial and owner inheritance',
  ()=>{
  try{
    command('psql',['-X','-At','-d','postgres','-c','select 1']);
  }catch{
    assert.fail('isolated/local PostgreSQL is required; do not silently skip');
  }
  command('createdb',[database]);
  try{
    query(`
      create extension if not exists pgcrypto;
      create table public.conferences(id uuid primary key,owner_id uuid not null,deleted_at timestamptz);
      create table public.conference_members(conference_id uuid,user_id uuid,role text);
      create table public.conference_participations(id uuid primary key,conference_id uuid,user_id uuid,status text);
      create table public.module_permission_catalog(permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text,catalog_version int);
      create table public.module_permission_grants(
        grant_id uuid primary key default gen_random_uuid(),user_id uuid,module_key text,permission_key text,
        resource_type text,resource_id text,revoked_at timestamptz
      );
      create table public.approved_devices(device_id uuid primary key,user_id uuid,status text);
      create function public.require_current_approved_device(uuid) returns uuid language plpgsql stable as $$
      declare actor uuid; begin select user_id into actor from public.approved_devices where device_id=$1 and status='approved';
      if actor is null then raise exception 'DEVICE_DENIED' using errcode='42501'; end if; return actor; end $$;
      create function public.is_system_owner(uuid) returns boolean language sql stable as $$ select false $$;
      create function public.validate_module_permission_catalog(text,text,text,text,text) returns jsonb language plpgsql stable as $$
      declare row record; begin select * into row from public.module_permission_catalog where permission_key=$2 and module_key=$1 and status='active';
      if not found or (row.allowed_scope_mode='resource' and ($3 is distinct from row.allowed_resource_type or $4 is null))
        or (row.allowed_scope_mode='module' and ($3 is not null or $4 is not null)) then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if;
      return jsonb_build_object('catalogVersion',row.catalog_version); end $$;
      create function public.require_module_permission(uuid,text,text,text,text) returns jsonb language plpgsql stable as $$
      declare actor uuid; begin actor:=public.require_current_approved_device($1);
      if not exists(select 1 from public.module_permission_grants where user_id=actor and module_key=$2 and permission_key=$3 and resource_type is null and resource_id is null and revoked_at is null)
      then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if; return '{}'::jsonb; end $$;
      create function public.require_effective_module_permission(uuid,text,text,text,text) returns jsonb language sql stable as $$ select '{}'::jsonb $$;
      insert into public.module_permission_catalog values
        ('module.access','conference','active','module',null,1),
        ('conference.access.view','conference','active','resource','conference',1),
        ('conference.people.manage','conference','active','resource','conference',1),
        ('warehouse.items.view','warehouse','active','resource','store',1),
        ('reservations.booking.view','reservations','active','resource','event',1);
      insert into public.conferences values('${ids.conferenceA}','${ids.owner}',null),('${ids.conferenceB}','${ids.other}',null);
      insert into public.approved_devices values
        ('${device(ids.owner)}','${ids.owner}','approved'),('${device(ids.grantee)}','${ids.grantee}','approved'),
        ('${device(ids.participant)}','${ids.participant}','approved'),('${device(ids.legacy)}','${ids.legacy}','approved'),
        ('${device(ids.other)}','${ids.other}','approved');
      insert into public.module_permission_grants(user_id,module_key,permission_key) values
        ('${ids.owner}','conference','module.access'),('${ids.grantee}','conference','module.access'),
        ('${ids.participant}','conference','module.access'),('${ids.legacy}','conference','module.access'),('${ids.other}','conference','module.access');
      insert into public.module_permission_grants(user_id,module_key,permission_key,resource_type,resource_id) values
        ('${ids.grantee}','conference','conference.access.view','conference','${ids.conferenceA}');
      insert into public.conference_members values('${ids.conferenceA}','${ids.legacy}','manager'),('${ids.conferenceB}','${ids.legacy}','viewer');
      insert into public.conference_participations values(gen_random_uuid(),'${ids.conferenceA}','${ids.participant}','active');
    `);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    const authorize=(user,permission,conference)=>query(`select public.require_effective_module_permission('${device(user)}','conference','${permission}','conference','${conference}')->>'authoritySource'`);
    assert.equal(authorize(ids.grantee,'conference.access.view',ids.conferenceA),'resource_grant');
    assert.throws(()=>query(`select public.require_effective_module_permission('${ids.badDevice}','conference','conference.access.view','conference','${ids.conferenceA}')`),/DEVICE_DENIED/);
    assert.throws(()=>authorize(ids.grantee,'conference.people.manage',ids.conferenceA),/MODULE_PERMISSION_REQUIRED/);
    assert.throws(()=>authorize(ids.grantee,'conference.access.view',ids.conferenceB),/MODULE_PERMISSION_REQUIRED/);
    assert.throws(()=>authorize(ids.participant,'conference.access.view',ids.conferenceA),/MODULE_PERMISSION_REQUIRED/);
    query(`update public.conference_participations set status='apologized' where user_id='${ids.participant}'; delete from public.conference_participations where user_id='${ids.participant}'`);
    assert.throws(()=>authorize(ids.participant,'conference.access.view',ids.conferenceA),/MODULE_PERMISSION_REQUIRED/);
    assert.throws(()=>authorize(ids.legacy,'conference.access.view',ids.conferenceA),/MODULE_PERMISSION_REQUIRED/);
    assert.throws(()=>authorize(ids.legacy,'conference.access.view',ids.conferenceB),/MODULE_PERMISSION_REQUIRED/);
    assert.equal(authorize(ids.owner,'conference.people.manage',ids.conferenceA),'conference_owner');
    assert.throws(()=>authorize(ids.owner,'conference.people.manage',ids.conferenceB),/MODULE_PERMISSION_REQUIRED/);
    assert.equal(query(`select count(*) from public.module_permission_grants where resource_type='conference'`),'1');
  }finally{command('dropdb',['--if-exists',database]);}
});

test('P6C0 changes no direct canonical SQL execution privileges',()=>{
  assert.doesNotMatch(sql,/\bgrant\s+execute|\brevoke\s+all|alter default privileges/i);
  for(const file of [
    'supabase/migrations/20260928130000_canonical_server_conference_core_foundation.sql',
    'supabase/migrations/20260928150000_canonical_conference_participation_foundation.sql',
    'supabase/migrations/20260929120000_canonical_conference_accommodation_protected_mutations.sql',
    'supabase/migrations/20260929170000_canonical_conference_core_read_edge_foundation.sql'
  ])assert.match(read(file),/revoke all on function/i);
});
