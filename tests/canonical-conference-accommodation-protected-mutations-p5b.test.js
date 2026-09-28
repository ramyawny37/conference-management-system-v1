'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync,execFile}=require('node:child_process');
const {promisify}=require('node:util');
const test=require('node:test');
const execFileAsync=promisify(execFile);
const root=path.join(__dirname,'..');
const migration='supabase/migrations/20260929120000_canonical_conference_accommodation_protected_mutations.sql';
const p5a='supabase/migrations/20260928170000_canonical_conference_accommodation_data_foundation.sql';
const sql=fs.readFileSync(path.join(root,migration),'utf8');

test('P5B extends only the canonical router with protected Accommodation operations',()=>{
  for(const operation of ['get_conference_accommodation','create_accommodation_house','update_accommodation_house','delete_accommodation_house','create_accommodation_floor','update_accommodation_floor','delete_accommodation_floor','create_accommodation_room','update_accommodation_room','delete_accommodation_room','assign_conference_accommodation','move_conference_accommodation','remove_conference_accommodation']) assert.match(sql,new RegExp(`'${operation}'`));
  assert.match(sql,/create or replace function platform_private\.route_canonical_conference_operation/);
  assert.doesNotMatch(sql,/create or replace function platform\.execute_conference_device_operation\(/);
  assert.doesNotMatch(sql,/create table|_operations\b|conference_snapshots|reservations\.|organization_members|conference_members/i);
});

test('P5B encodes duration, active participation, locking, revision and audit contracts',()=>{
  assert.match(sql,/end_date-start_date\+1/);
  assert.match(sql,/status='active'/);
  assert.match(sql,/order by id for update/);
  assert.match(sql,/bed_type=p_bed/);
  assert.match(sql,/revision=revision\+1/g);
  assert.match(sql,/ACCOMMODATION_CLOSURE_CONFLICT/);
  assert.match(sql,/insert into platform\.audit_events/g);
});

const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_p5b_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
async function queryAsync(statement){return (await execFileAsync(pgBin?path.join(pgBin,'psql'):'psql',[...connection,'-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement],{encoding:'utf8',env})).stdout.trim();}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves protected Accommodation behavior and concurrency',async()=>{
  const actor='10000000-0000-0000-0000-000000000001',device='11000000-0000-0000-0000-000000000001',authz='12000000-0000-0000-0000-000000000001';
  const conference='20000000-0000-0000-0000-000000000001',completed='20000000-0000-0000-0000-000000000002',nodates='20000000-0000-0000-0000-000000000003';
  const person1='30000000-0000-0000-0000-000000000001',person2='30000000-0000-0000-0000-000000000002',person3='30000000-0000-0000-0000-000000000003';
  const part1='40000000-0000-0000-0000-000000000001',part2='40000000-0000-0000-0000-000000000002',part3='40000000-0000-0000-0000-000000000003';
  const roles=['anon','authenticated','service_role'],created=[];
  command('createdb',[database]);
  try{
    for(const role of roles) if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}
    query(`create schema extensions; create extension pgcrypto with schema extensions; create schema platform; create schema platform_private;
      create table platform.profiles(user_id uuid primary key);
      create table platform.people(id uuid primary key,full_name text,phone text,gender text,date_of_birth date,church text);
      create table public.conferences(id uuid primary key,start_date date,end_date date,status text,deleted_at timestamptz);
      create table public.conference_participations(id uuid primary key,conference_id uuid not null references public.conferences(id),person_id uuid not null references platform.people(id),status text not null,unique(conference_id,person_id));
      create table public.module_permission_catalog(permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text);
      create table public.p5_context(permission text,enabled boolean);
      insert into public.p5_context values('conference.accommodation.manage',true);
      create table platform.audit_events(id uuid primary key default extensions.gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,request_id uuid,operation_id uuid,source text,occurred_at timestamptz default now());
      insert into public.module_permission_catalog values('conference.accommodation.view','conference','active','resource','conference'),('conference.accommodation.manage','conference','active','resource','conference');
      insert into platform.profiles values('${actor}'); insert into platform.people values('${person1}','One','1','m',null,'A'),('${person2}','Two','2','f',null,'B'),('${person3}','Three','3','m',null,'C');
      insert into public.conferences values('${conference}','2027-01-01','2027-01-03','active',null),('${completed}','2027-01-01','2027-01-03','completed',null),('${nodates}',null,null,'active',null);
      insert into public.conference_participations values('${part1}','${conference}','${person1}','active'),('${part2}','${conference}','${person2}','apologized'),('${part3}','${conference}','${person3}','active');
      create function public.require_effective_module_permission(uuid,text,text,text,text) returns jsonb language plpgsql stable as \$\$ begin if not (select enabled from public.p5_context) or \$3<>(select permission from public.p5_context) then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if; return jsonb_build_object('actorUserId','${actor}','authoritySource','resource_grant','grantId','13000000-0000-0000-0000-000000000001'); end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql stable as \$\$ select case when \$1='${actor}' and \$2='${device}' and (select enabled from public.p5_context) then '${authz}'::uuid end \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language sql immutable as \$\$ select \$\$;
      create function public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.list_conference_participations(uuid,uuid) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.create_conference_participation(uuid,uuid,uuid,uuid) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.delete_conference_participation(uuid,uuid,uuid,bigint) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,p5a)]);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    for(const role of roles){
      assert.equal(query(`select has_function_privilege('${role}','public.assign_conference_accommodation(uuid,uuid,uuid,uuid,integer,integer,text,text)','EXECUTE')`),'f');
      assert.equal(query(`select has_table_privilege('${role}','public.conference_accommodation_occupancies','INSERT,UPDATE,DELETE')`),'f');
    }
    const mutate=(op,args)=>JSON.parse(query(`select public.mutate_conference_accommodation_structure('${device}','${op}',${args})`));
    const house=mutate('create_house',`jsonb_build_object('p_conference_id','${conference}','p_name','H','p_description',null,'p_position',0)`);
    assert.equal(mutate('update_house',`jsonb_build_object('p_conference_id','${conference}','p_house_id','${house.houseId}','p_expected_revision',1,'p_name','H2','p_description',null,'p_position',0)`).revision,2);
    rejects(`select public.mutate_conference_accommodation_structure('${device}','update_house',jsonb_build_object('p_conference_id','${conference}','p_house_id','${house.houseId}','p_expected_revision',1,'p_name','stale','p_description',null,'p_position',0))`,/ACCOMMODATION_REVISION_CONFLICT/);
    rejects(`select public.mutate_conference_accommodation_structure('${device}','create_house',jsonb_build_object('p_conference_id','${completed}','p_name','No','p_description',null,'p_position',0))`,/COMPLETED_CONFERENCE_IMMUTABLE/);
    const floor=mutate('create_floor',`jsonb_build_object('p_conference_id','${conference}','p_house_id','${house.houseId}','p_name','F','p_position',0)`);
    assert.ok(floor.floorId);
    const room1=mutate('create_room',`jsonb_build_object('p_conference_id','${conference}','p_floor_id','${floor.floorId}','p_room_number','101','p_base_capacity',1,'p_extra_bed_capacity',1,'p_notes',null,'p_is_closed',false,'p_closed_day',null,'p_position',0)`);
    const room2=mutate('create_room',`jsonb_build_object('p_conference_id','${conference}','p_floor_id','${floor.floorId}','p_room_number','102','p_base_capacity',1,'p_extra_bed_capacity',0,'p_notes',null,'p_is_closed',false,'p_closed_day',null,'p_position',1)`);
    rejects(`select public.mutate_conference_accommodation_structure('${device}','delete_floor',jsonb_build_object('p_conference_id','${conference}','p_floor_id','${floor.floorId}','p_expected_revision',1))`,/ACCOMMODATION_FLOOR_NOT_EMPTY/);
    rejects(`select public.assign_conference_accommodation('${device}','${conference}','${room1.roomId}','${part2}',1,null,'base',null)`,/ACTIVE_CONFERENCE_PARTICIPATION_REQUIRED/);
    rejects(`select public.assign_conference_accommodation('${device}','${conference}','${room1.roomId}','${part1}',0,null,'base',null)`,/ACCOMMODATION_STAY_INVALID/);
    const assigned=JSON.parse(query(`select public.assign_conference_accommodation('${device}','${conference}','${room1.roomId}','${part1}',1,3,'base',null)`));
    rejects(`select public.assign_conference_accommodation('${device}','${conference}','${room1.roomId}','${part3}',1,3,'base',null)`,/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
    rejects(`select public.move_conference_accommodation('${device}','${conference}','${assigned.occupancyId}',2,'${room2.roomId}',1,3,'base',null)`,/ACCOMMODATION_REVISION_CONFLICT/);
    const moved=JSON.parse(query(`select public.move_conference_accommodation('${device}','${conference}','${assigned.occupancyId}',1,'${room2.roomId}',1,3,'base',null)`));
    assert.equal(moved.occupancyId,assigned.occupancyId); assert.equal(moved.revision,2);
    query(`update public.p5_context set permission='conference.accommodation.view'`);
    const read=JSON.parse(query(`select public.get_conference_accommodation('${device}','${conference}')`));
    assert.equal(read.houses[0].floors[0].rooms[1].occupancies[0].person.fullName,'One');
    rejects(`select public.remove_conference_accommodation('${device}','${conference}','${assigned.occupancyId}',2)`,/MODULE_PERMISSION_REQUIRED/);
    query(`update public.p5_context set permission='conference.accommodation.manage'`);
    assert.equal(JSON.parse(query(`select public.remove_conference_accommodation('${device}','${conference}','${assigned.occupancyId}',2)`)).deleted,true);
    assert.equal(query(`select count(*) from public.conference_participations where id='${part1}'`),'1'); assert.equal(query(`select count(*) from platform.people where id='${person1}'`),'1');
    const call1=`select public.assign_conference_accommodation('${device}','${conference}','${room1.roomId}','${part1}',1,3,'base',null)`;
    const call2=`select public.assign_conference_accommodation('${device}','${conference}','${room1.roomId}','${part3}',1,3,'base',null)`;
    const concurrent=await Promise.allSettled([queryAsync(call1),queryAsync(call2)]);
    assert.equal(concurrent.filter(result=>result.status==='fulfilled').length,1); assert.equal(concurrent.filter(result=>result.status==='rejected').length,1);
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where room_id='${room1.roomId}'`),'1');
    assert.equal(query(`select count(*) from platform.audit_events where action like 'conference.accommodation.%'`),'9');
  }finally{command('dropdb',['--if-exists',database]); for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);}
});
