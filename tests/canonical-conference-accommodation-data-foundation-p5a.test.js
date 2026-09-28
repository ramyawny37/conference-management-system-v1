'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration='supabase/migrations/20260928170000_canonical_conference_accommodation_data_foundation.sql';
const sql=fs.readFileSync(path.join(root,migration),'utf8');
const tables=['houses','floors','rooms','occupancies'].map(name=>`conference_accommodation_${name}`);

test('P5A defines one normalized Conference-owned Accommodation hierarchy',()=>{
  for(const table of tables) assert.match(sql,new RegExp(`create table public\\.${table}\\(`));
  assert.match(sql,/foreign key\(conference_id,house_id\)[\s\S]*references public\.conference_accommodation_houses\(conference_id,id\)/);
  assert.match(sql,/foreign key\(conference_id,floor_id\)[\s\S]*references public\.conference_accommodation_floors\(conference_id,id\)/);
  assert.match(sql,/foreign key\(conference_id,room_id\)[\s\S]*references public\.conference_accommodation_rooms\(conference_id,id\)/);
  assert.match(sql,/foreign key\(participation_id,conference_id\)[\s\S]*references public\.conference_participations\(id,conference_id\)/);
  assert.match(sql,/unique\(participation_id\)/);
  assert.doesNotMatch(sql,/person_id|full_name|phone|gender|date_of_birth|church|guardian/i);
});

test('P5A preserves relational room and stay facts without adding APIs or ledgers',()=>{
  for(const field of ['room_number','base_capacity','extra_bed_capacity','notes','is_closed','closed_day','arrival_day','leave_day','bed_type','extra_bed_person_type']) assert.match(sql,new RegExp(`\\b${field}\\b`));
  assert.match(sql,/check\(leave_day is null or leave_day>arrival_day\)/);
  assert.match(sql,/check\(base_capacity>=0\)/);
  assert.match(sql,/check\(extra_bed_capacity>=0\)/);
  assert.doesNotMatch(sql,/create\s+function|operation_ledger|_operations\b|audit_events|execute_conference_device_operation/i);
  assert.doesNotMatch(sql,/conference_snapshots|peopleDb|reservations\.|organization_members|conference_members|transport|warehouse/i);
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_p5a_${process.pid}_${Date.now()}`;
const validationHost=process.env.PGHOST;
const connection=validationHost?['-h',validationHost,'-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username]:['-h','/tmp','-p','5432','-U',os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
if(process.env.PGPASSWORD) env.PGPASSWORD=process.env.PGPASSWORD;
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves keys, constraints, deletion dependency and isolation',()=>{
  try{command('psql',['-X','-At','-d','postgres','-c','select 1']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  const actor='10000000-0000-0000-0000-000000000001';
  const conference1='20000000-0000-0000-0000-000000000001';
  const conference2='20000000-0000-0000-0000-000000000002';
  const person1='30000000-0000-0000-0000-000000000001';
  const person2='30000000-0000-0000-0000-000000000002';
  const participation1='40000000-0000-0000-0000-000000000001';
  const participation2='40000000-0000-0000-0000-000000000002';
  const house1='50000000-0000-0000-0000-000000000001';
  const house2='50000000-0000-0000-0000-000000000002';
  const floor1='60000000-0000-0000-0000-000000000001';
  const room1='70000000-0000-0000-0000-000000000001';
  const room2='70000000-0000-0000-0000-000000000002';
  const occupancy='80000000-0000-0000-0000-000000000001';
  const roles=['anon','authenticated','service_role'];
  const created=[];
  command('createdb',[database]);
  try{
    for(const role of roles){if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}}
    query(`create schema extensions; create extension pgcrypto with schema extensions; create schema platform;
      create table platform.profiles(user_id uuid primary key);
      create table platform.people(id uuid primary key);
      create table public.conferences(id uuid primary key);
      create table public.conference_participations(id uuid primary key,conference_id uuid not null references public.conferences(id),person_id uuid not null references platform.people(id),status text not null,unique(conference_id,person_id));
      create table public.module_permission_catalog(permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text);
      insert into public.module_permission_catalog values('conference.accommodation.view','conference','active','resource','conference'),('conference.accommodation.manage','conference','active','resource','conference');
      insert into platform.profiles values('${actor}');
      insert into platform.people values('${person1}'),('${person2}');
      insert into public.conferences values('${conference1}'),('${conference2}');
      insert into public.conference_participations values('${participation1}','${conference1}','${person1}','active'),('${participation2}','${conference2}','${person2}','apologized');`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    for(const table of tables) assert.equal(query(`select to_regclass('public.${table}') is not null`),'t');
    for(const role of roles) for(const table of tables) assert.equal(query(`select has_table_privilege('${role}','public.${table}','INSERT,UPDATE,DELETE')`),'f');
    query(`insert into public.conference_accommodation_houses(id,conference_id,name,created_by,updated_by) values('${house1}','${conference1}','House 1','${actor}','${actor}'),('${house2}','${conference2}','House 2','${actor}','${actor}')`);
    query(`insert into public.conference_accommodation_floors(id,conference_id,house_id,name,created_by,updated_by) values('${floor1}','${conference1}','${house1}','Floor 1','${actor}','${actor}')`);
    rejects(`insert into public.conference_accommodation_floors(conference_id,house_id,name,created_by,updated_by) values('${conference2}','${house1}','Wrong','${actor}','${actor}')`,/foreign key/);
    query(`insert into public.conference_accommodation_rooms(id,conference_id,floor_id,room_number,base_capacity,extra_bed_capacity,created_by,updated_by) values('${room1}','${conference1}','${floor1}','101',2,1,'${actor}','${actor}'),('${room2}','${conference1}','${floor1}','102',1,0,'${actor}','${actor}')`);
    rejects(`insert into public.conference_accommodation_rooms(conference_id,floor_id,room_number,base_capacity,created_by,updated_by) values('${conference1}','${floor1}','Bad',-1,'${actor}','${actor}')`,/check constraint/);
    rejects(`insert into public.conference_accommodation_rooms(conference_id,floor_id,room_number,base_capacity,extra_bed_capacity,created_by,updated_by) values('${conference1}','${floor1}','Bad',1,-1,'${actor}','${actor}')`,/check constraint/);
    query(`insert into public.conference_accommodation_occupancies(id,conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,extra_bed_person_type,created_by,updated_by) values('${occupancy}','${conference1}','${room1}','${participation1}',1,3,'extra','adult','${actor}','${actor}')`);
    rejects(`insert into public.conference_accommodation_occupancies(conference_id,room_id,participation_id,arrival_day,created_by,updated_by) values('${conference1}','${room2}','${participation1}',1,'${actor}','${actor}')`,/unique constraint/);
    rejects(`insert into public.conference_accommodation_occupancies(conference_id,room_id,participation_id,arrival_day,created_by,updated_by) values('${conference1}','${room2}','${participation2}',1,'${actor}','${actor}')`,/foreign key/);
    rejects(`insert into public.conference_accommodation_occupancies(conference_id,room_id,participation_id,arrival_day,created_by,updated_by) values('${conference1}','${room2}','${participation1}',0,'${actor}','${actor}')`,/check constraint/);
    rejects(`update public.conference_accommodation_occupancies set leave_day=arrival_day where id='${occupancy}'`,/check constraint/);
    rejects(`delete from public.conference_participations where id='${participation1}'`,/foreign key/);
    query(`delete from public.conference_accommodation_occupancies where id='${occupancy}'; delete from public.conference_participations where id='${participation1}'`);
    assert.equal(query(`select count(*) from platform.people where id='${person1}'`),'1');
    assert.equal(query(`select count(*) from information_schema.columns where table_schema='public' and table_name='conference_accommodation_occupancies' and column_name in('person_id','full_name','phone','gender','date_of_birth','church')`),'0');
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
  }
});
