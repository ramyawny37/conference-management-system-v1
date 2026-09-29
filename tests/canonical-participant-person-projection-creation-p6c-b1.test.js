'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');
const root=path.join(__dirname,'..');
const migration='supabase/migrations/20261001120000_canonical_participant_person_projection_creation.sql';
const sql=fs.readFileSync(path.join(root,migration),'utf8');
const platformEdge=fs.readFileSync(path.join(root,'supabase/functions/platform-device-operation/index.ts'),'utf8');
const conferenceEdge=fs.readFileSync(path.join(root,'supabase/functions/conference-device-operation/index.ts'),'utf8');

test('P6C-B1 extends the existing Participation boundary without exposing Person Bank',()=>{
  assert.match(sql,/create or replace function public\.list_conference_participations/);
  assert.match(sql,/join platform\.people person on person\.id=participation\.person_id/);
  for(const field of ['fullName','phone','gender','dateOfBirth','church']) assert.match(sql,new RegExp(`'${field}'`));
  assert.doesNotMatch(sql,/peopleDb|conference_snapshots|legacy|\bage\b|\bnotes\b|search_people/i);
  assert.match(sql,/create function public\.create_conference_participation_with_person/);
  assert.doesNotMatch(sql,/create (?:table|schema)|grant (?:select|insert|update|delete).*platform\.people/i);
  assert.match(sql,/revoke all on function[\s\S]*create_conference_participation_with_person/);
  assert.match(platformEdge,/conference\.add\('create_conference_participation_with_person'\)/);
  assert.match(conferenceEdge,/allowed\.add\('create_conference_participation_with_person'\)/);
  assert.doesNotMatch(sql,/create or replace function public\.create_conference_participation\(/);
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_p6c_b1_${process.pid}_${Date.now()}`;
const validationHost=process.env.PGHOST;
const connection=validationHost?['-h',validationHost,'-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username]:['-h','/tmp','-p','5432','-U',os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
if(process.env.PGPASSWORD)env.PGPASSWORD=process.env.PGPASSWORD;
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves projection and atomic scoped creation',()=>{
  try{command('psql',['-X','-At','-d','postgres','-c','select 1']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  const actor='10000000-0000-0000-0000-000000000001';
  const device='20000000-0000-0000-0000-000000000001';
  const authorization='30000000-0000-0000-0000-000000000001';
  const conference='40000000-0000-0000-0000-000000000001';
  const otherConference='40000000-0000-0000-0000-000000000002';
  const existingPerson='50000000-0000-0000-0000-000000000001';
  const operation='60000000-0000-0000-0000-000000000001';
  const roles=['anon','authenticated','service_role'];
  const created=[];
  command('createdb',[database]);
  try{
    for(const role of roles){if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}}
    query(`create schema extensions; create extension pgcrypto with schema extensions; create schema platform; create schema platform_private;
      create table platform.profiles(user_id uuid primary key);
      create table platform.people(id uuid primary key default extensions.gen_random_uuid(),full_name text not null check(length(full_name) between 1 and 240),phone text,gender text check(gender in('male','female')),date_of_birth date,church text,revision bigint default 1,created_at timestamptz default now(),updated_at timestamptz default now(),created_by uuid references platform.profiles(user_id),updated_by uuid references platform.profiles(user_id));
      create table public.conferences(id uuid primary key,status text,deleted_at timestamptz);
      create table public.conference_participations(id uuid primary key default extensions.gen_random_uuid(),conference_id uuid not null references public.conferences(id),person_id uuid not null references platform.people(id),status text not null default 'active',revision bigint not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(conference_id,person_id));
      create table public.conference_participation_operations(actor_user_id uuid not null references platform.profiles(user_id),operation_id uuid not null,operation text not null check(operation in('create','set_status','delete')),request jsonb not null,result jsonb not null,created_at timestamptz not null,primary key(actor_user_id,operation_id));
      create table platform.audit_events(id uuid primary key default extensions.gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,new_values jsonb,metadata jsonb,operation_id uuid,source text);
      alter table platform.people enable row level security; alter table platform.people force row level security;
      alter table public.conference_participations enable row level security; alter table public.conference_participations force row level security;
      alter table public.conference_participation_operations enable row level security; alter table public.conference_participation_operations force row level security;
      revoke all on platform.people,public.conference_participations,public.conference_participation_operations from public,anon,authenticated,service_role;
      insert into platform.profiles values('${actor}');
      insert into public.conferences values('${conference}','active',null),('${otherConference}','active',null);
      insert into platform.people(id,full_name,phone,gender,date_of_birth,church) values('${existingPerson}','Canonical Existing','0100','female','1990-02-03','Canonical Church');
      insert into public.conference_participations(conference_id,person_id,status,created_by,updated_by) values('${conference}','${existingPerson}','apologized','${actor}','${actor}');
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql stable as \$\$ select case when \$1='${actor}' and \$2='${device}' then '${authorization}'::uuid end \$\$;
      create function platform_private.require_conference_participation_context(uuid,uuid,text,boolean) returns jsonb language plpgsql stable security definer set search_path='' as \$\$ begin if \$1<>'${device}' or \$2<>'${conference}' or \$3 not in('conference.people.view','conference.people.manage') then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if; return jsonb_build_object('actorUserId','${actor}','authoritySource','conference_owner','grantId',null); end \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language sql immutable as \$\$ select \$\$;
      create function platform_private.route_canonical_conference_operation(p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_actor_device_id uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as \$\$ begin if p_operation='get_conference_core' then return '{}'::jsonb; elsif p_operation='list_conference_participations' then return public.list_conference_participations(p_actor_device_id,(p_args->>'p_conference_id')::uuid); end if; return '{}'::jsonb; end \$\$;
      revoke all on function platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb) from public,anon,authenticated,service_role;`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);

    const listed=JSON.parse(query(`select public.list_conference_participations('${device}','${conference}')`));
    assert.equal(listed.totalCount,1); assert.equal(listed.apologizedCount,1);
    assert.deepEqual(listed.items[0].person,{personId:existingPerson,fullName:'Canonical Existing',phone:'0100',gender:'female',dateOfBirth:'1990-02-03',church:'Canonical Church'});
    rejects(`select public.list_conference_participations('${device}','${otherConference}')`,/MODULE_PERMISSION_REQUIRED/);

    const call=`select public.create_conference_participation_with_person('${device}','${operation}','${conference}',' New Person ','0123','male','2000-01-02',' Church ')`;
    const result=JSON.parse(query(call));
    assert.equal(result.person.fullName,'New Person'); assert.equal(result.person.church,'Church');
    assert.equal(result.status,'active'); assert.equal(result.revision,1);
    assert.equal(query(`select created_by=updated_by and created_by='${actor}' from platform.people where id='${result.personId}'`),'t');
    assert.equal(query(`select created_by=updated_by and created_by='${actor}' from public.conference_participations where id='${result.participationId}'`),'t');
    assert.deepEqual(JSON.parse(query(call)),result);
    assert.equal(query(`select count(*) from platform.people where full_name='New Person'`),'1');
    assert.equal(query(`select count(*) from public.conference_participations where person_id='${result.personId}'`),'1');
    assert.equal(query(`select count(*) from platform.audit_events where operation_id='${operation}'`),'2');
    assert.equal(query(`select count(*) from public.conference_participation_operations where operation_id='${operation}' and operation='create_with_person'`),'1');
    rejects(`select public.create_conference_participation_with_person('${device}',extensions.gen_random_uuid(),'${otherConference}','Wrong',null,'male',null,null)`,/MODULE_PERMISSION_REQUIRED/);
    const beforeInvalid=query('select count(*) from platform.people');
    rejects(`select public.create_conference_participation_with_person('${device}',extensions.gen_random_uuid(),'${conference}',' ','0123','male',null,null)`,/CONFERENCE_PARTICIPANT_PERSON_ARGUMENT_INVALID/);
    assert.equal(query('select count(*) from platform.people'),beforeInvalid);

    query(`create function public.reject_participation_probe() returns trigger language plpgsql as \$\$ begin if (select full_name from platform.people where id=new.person_id)='Participation Failure' then raise exception 'PARTICIPATION_FAILURE'; end if; return new; end \$\$; create trigger reject_participation_probe before insert on public.conference_participations for each row execute function public.reject_participation_probe();`);
    const beforeFailure=query('select count(*) from platform.people');
    rejects(`select public.create_conference_participation_with_person('${device}',extensions.gen_random_uuid(),'${conference}','Participation Failure',null,null,null,null)`,/PARTICIPATION_FAILURE/);
    assert.equal(query('select count(*) from platform.people'),beforeFailure);
    for(const role of roles){
      assert.equal(query(`select has_table_privilege('${role}','platform.people','SELECT,INSERT,UPDATE,DELETE')`),'f');
      rejects(`set role ${role}; insert into platform.people(full_name) values('Denied')`,/permission denied/);
    }
    assert.equal(query(`select position('create_conference_participation_with_person' in pg_get_functiondef('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure))>0`),'t');
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of created)command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
  }
});
