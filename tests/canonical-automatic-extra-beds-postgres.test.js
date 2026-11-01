'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');

const root=path.join(__dirname,'..');
const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_auto_extra_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args,input){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env,input}).trim();}
function query(sql){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',sql]);}

test('automatic child extra beds are occupancy-owned and guardian-stay protected in real PostgreSQL',()=>{
  const conference='10000000-0000-0000-0000-000000000001';
  const roomA='20000000-0000-0000-0000-000000000001';
  const roomB='20000000-0000-0000-0000-000000000002';
  const guardian='30000000-0000-0000-0000-000000000001';
  const child='30000000-0000-0000-0000-000000000002';
  const adult='30000000-0000-0000-0000-000000000003';
  const unhousedGuardian='30000000-0000-0000-0000-000000000004';
  const unqualifiedChild='30000000-0000-0000-0000-000000000005';
  command('createdb',[database]);
  try{
    for(const role of ['anon','authenticated','service_role'])if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f')query(`create role ${role} nologin`);
    query(`
      create extension if not exists pgcrypto;create schema platform_private;
      create table public.conference_participations(id uuid primary key,conference_id uuid not null,status text not null,guardian_participation_id uuid);
      create table public.conference_accommodation_rooms(id uuid primary key,base_capacity integer not null,is_closed boolean default false,closed_day integer);
      create table public.conference_room_assignments(id uuid primary key default gen_random_uuid(),conference_id uuid not null,room_id uuid not null,extra_bed_capacity integer not null default 0,unique(conference_id,room_id));
      create table public.conference_accommodation_occupancies(id uuid primary key default gen_random_uuid(),conference_id uuid not null,room_id uuid not null,participation_id uuid not null,arrival_day integer not null,leave_day integer,bed_type text not null,extra_bed_person_type text,arrived_at timestamptz,arrived_by uuid,revision bigint default 1,created_by uuid,updated_by uuid,updated_at timestamptz default now());
      create function platform_private.conference_accommodation_duration(uuid) returns integer language sql stable as $$select 5$$;
      create function public.assign_conference_accommodation(p_device uuid,p_conference uuid,p_room uuid,p_participation uuid,p_arrival integer,p_leave integer,p_bed text,p_extra_type text) returns jsonb language plpgsql as $$declare participation public.conference_participations%rowtype;row public.conference_accommodation_occupancies%rowtype;begin select * into participation from public.conference_participations where id=p_participation and conference_id=p_conference and status='active';if not found then raise exception 'ACTIVE_CONFERENCE_PARTICIPATION_REQUIRED';end if;if not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,null) then raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED';end if;insert into public.conference_accommodation_occupancies(conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,extra_bed_person_type) values(p_conference,p_room,p_participation,p_arrival,p_leave,p_bed,p_extra_type) returning * into row;return to_jsonb(row);end$$;
      create function public.move_conference_accommodation(p_device uuid,p_conference uuid,p_occupancy uuid,p_expected bigint,p_room uuid,p_arrival integer,p_leave integer,p_bed text,p_extra_type text) returns jsonb language plpgsql as $$declare participation public.conference_participations%rowtype;historical boolean:=false;begin select p.* into participation from public.conference_participations p join public.conference_accommodation_occupancies o on o.participation_id=p.id where o.id=p_occupancy;if not platform_private.conference_room_has_capacity(p_conference,p_room,p_bed,p_arrival,p_leave,case when historical then null else p_occupancy end) then raise exception 'ACCOMMODATION_ROOM_CAPACITY_EXCEEDED';end if;return '{}'::jsonb;end$$;
      create function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb,jsonb) returns jsonb language plpgsql as $$begin if exists(select 1 from generate_series(1,5) d(day) join public.conference_accommodation_occupancies o on o.conference_id=$2 and o.room_id=$3 and o.bed_type='extra' and o.arrival_day<=d.day and d.day<coalesce(o.leave_day,6) group by d.day having count(*)>0) then null;end if;return '{}'::jsonb;end$$;
      create function platform_private.sync_guardian_linked_child_stays() returns trigger language plpgsql as $$declare linked public.conference_accommodation_occupancies%rowtype;begin for linked in select * from public.conference_accommodation_occupancies where false loop if not platform_private.conference_room_has_capacity(new.conference_id,new.room_id,linked.bed_type,new.arrival_day,new.leave_day,null) then raise exception 'CAPACITY';end if;insert into public.conference_accommodation_occupancies(conference_id,room_id,participation_id,arrival_day,leave_day,bed_type,extra_bed_person_type,arrived_at,arrived_by,created_by,updated_by) values(new.conference_id,new.room_id,linked.participation_id,new.arrival_day,new.leave_day,linked.bed_type,linked.extra_bed_person_type,new.arrived_at,new.arrived_by,linked.created_by,new.updated_by);end loop;return new;end$$;
      create function public.get_conference_accommodation(uuid,uuid) returns jsonb language sql as $$select coalesce(jsonb_agg(jsonb_build_object('extraBedPersonType',o.extra_bed_person_type,'participationId',o.participation_id)),'[]') from public.conference_accommodation_occupancies o$$;
      create function platform_private.conference_room_has_capacity(uuid,uuid,text,integer,integer,uuid default null) returns boolean language sql as $$select true$$;
      insert into public.conference_accommodation_rooms values('${roomA}',3,false,null),('${roomB}',3,false,null);
      insert into public.conference_room_assignments(conference_id,room_id,extra_bed_capacity) values('${conference}','${roomA}',1),('${conference}','${roomB}',0);
      insert into public.conference_participations values('${guardian}','${conference}','active',null),('${child}','${conference}','active','${guardian}'),('${adult}','${conference}','active',null),('${unhousedGuardian}','${conference}','active',null),('${unqualifiedChild}','${conference}','active','${unhousedGuardian}');
      insert into public.conference_accommodation_occupancies(conference_id,room_id,participation_id,arrival_day,leave_day,bed_type) values('${conference}','${roomA}','${guardian}',1,5,'base');
    `);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,'supabase/migrations/20261102100000_canonical_automatic_extra_beds_and_guardian_stays.sql')]);
    const automatic=JSON.parse(query(`select public.assign_conference_accommodation(gen_random_uuid(),'${conference}','${roomB}','${child}',1,5,'extra','child')`));
    assert.equal(query(`select extra_bed_source from public.conference_accommodation_occupancies where id='${automatic.id}'`),'automatic');
    assert.equal(query(`select extra_bed_capacity from public.conference_room_assignments where conference_id='${conference}' and room_id='${roomB}'`),'0');
    assert.throws(()=>query(`select public.assign_conference_accommodation(gen_random_uuid(),'${conference}','${roomB}','${adult}',1,5,'extra','adult')`),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
    assert.throws(()=>query(`select public.assign_conference_accommodation(gen_random_uuid(),'${conference}','${roomB}','${unqualifiedChild}',1,5,'extra','child')`),/ACCOMMODATION_CHILD_GUARDIAN_STAY_REQUIRED/);
    assert.throws(()=>query(`update public.conference_accommodation_occupancies set bed_type='shared',extra_bed_person_type=null where id='${automatic.id}'`),/ACCOMMODATION_SHARED_CHILD_GUARDIAN_STAY_REQUIRED/);
    assert.equal(query(`select extra_bed_source from public.conference_accommodation_occupancies where id='${automatic.id}'`),'automatic');
    query(`update public.conference_accommodation_occupancies set room_id='${roomA}',bed_type='shared',extra_bed_person_type=null where id='${automatic.id}'`);
    assert.equal(query(`select extra_bed_source is null from public.conference_accommodation_occupancies where id='${automatic.id}'`),'t');
    query(`update public.conference_accommodation_occupancies set room_id='${roomB}',bed_type='extra',extra_bed_person_type='child' where id='${automatic.id}'`);
    assert.equal(query(`select extra_bed_source from public.conference_accommodation_occupancies where id='${automatic.id}'`),'automatic');
    query(`delete from public.conference_accommodation_occupancies where id='${automatic.id}'`);
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where id='${automatic.id}'`),'0');
    assert.equal(query(`select extra_bed_capacity from public.conference_room_assignments where conference_id='${conference}' and room_id='${roomA}'`),'1');
    assert.equal(query(`select pg_get_functiondef('public.get_conference_accommodation(uuid,uuid)'::regprocedure) like '%extraBedSource%'`),'t');
  }finally{try{command('dropdb',['--if-exists',database]);}catch{}}
});
