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
const database=`conference_lifecycle_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args,input){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env,input}).trim();}
function query(sql){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',sql]);}

test('real migrations execute and preserve the independent-child and dynamic-period contracts',()=>{
  const actor='10000000-0000-0000-0000-000000000001';
  const device='11000000-0000-0000-0000-000000000001';
  const authz='12000000-0000-0000-0000-000000000001';
  const conference='20000000-0000-0000-0000-000000000001';
  const event='21000000-0000-0000-0000-000000000001';
  const partition='22000000-0000-0000-0000-000000000001';
  command('createdb',[database]);
  try{
    for(const role of ['anon','authenticated','service_role']) if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f')query(`create role ${role} nologin`);
    query(`
      create extension if not exists pgcrypto; create schema platform; create schema platform_private; create schema reservations; create schema reservations_private;
      create table platform.profiles(user_id uuid primary key); insert into platform.profiles values('${actor}');
      create table platform.people(id uuid primary key,full_name text); 
      create table platform.audit_events(id uuid primary key default gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,operation_id uuid,source text);
      create table public.conferences(id uuid primary key,start_date date,end_date date,status text,deleted_at timestamptz); insert into public.conferences values('${conference}',current_date,current_date+4,'active',null);
      create table public.conference_participations(id uuid primary key,conference_id uuid not null,person_id uuid not null,status text not null default 'active',guardian_participation_id uuid,revision bigint not null default 1,updated_at timestamptz default now(),updated_by uuid,created_at timestamptz default now(),created_by uuid);
      create table public.conference_participation_operations(actor_user_id uuid,operation_id uuid,operation text,request jsonb,result jsonb,created_at timestamptz,primary key(actor_user_id,operation_id));
      create table public.conference_accommodation_occupancies(id uuid primary key,conference_id uuid,room_id uuid,participation_id uuid,arrival_day integer,leave_day integer,bed_type text,revision bigint default 1,updated_at timestamptz default now(),updated_by uuid);
      create table public.conference_transport_assignments(id uuid primary key,conference_id uuid,vehicle_id uuid,participation_id uuid,assignment_mode text,rider_kind text,seat_number integer,revision bigint default 1);
      create table public.conference_restaurant_participation_overrides(id uuid primary key,conference_id uuid,participation_id uuid);
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql stable as $$select '${authz}'::uuid$$;
      create function platform_private.require_conference_participation_context(uuid,uuid,text,boolean) returns jsonb language sql stable as $$select jsonb_build_object('actorUserId','${actor}','authoritySource','test','grantId',null)$$;
      create function platform_private.require_conference_accommodation_context(uuid,uuid,text,boolean) returns jsonb language sql stable as $$select jsonb_build_object('actorUserId','${actor}','authoritySource','test','grantId',null)$$;
      create function platform_private.audit_conference_transport_assignment_removal(uuid,uuid,public.conference_transport_assignments,uuid,text,text) returns void language sql as $$select$$;
      create function platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid) returns uuid language plpgsql as $$declare found_id uuid;begin delete from public.conference_accommodation_occupancies where participation_id=$1 returning id into found_id;return found_id;end$$;
      create function platform_private.sync_shared_child_removal() returns trigger language plpgsql as $$begin delete from public.conference_accommodation_occupancies stay using public.conference_participations child where child.id=stay.participation_id and child.guardian_participation_id=old.participation_id and stay.bed_type='shared';return old;end$$;
      create trigger sync_shared_child_removal after delete on public.conference_accommodation_occupancies for each row when(old.bed_type<>'shared') execute function platform_private.sync_shared_child_removal();

      create table reservations.events(id uuid primary key,scope_partition_id uuid not null,start_date date,end_date date,created_by uuid,updated_by uuid,unique(scope_partition_id,id));
      create table reservations.event_periods(id uuid primary key default gen_random_uuid(),scope_partition_id uuid not null,event_id uuid not null,kind text not null check(kind in('conference','caravans')),starts_on date,ends_on date,display_order integer not null,revision bigint default 1,created_at timestamptz default now(),updated_at timestamptz default now(),created_by uuid,updated_by uuid,unique(event_id,display_order) deferrable initially deferred);
      create table reservations.booking_types(id uuid primary key,event_id uuid not null,scope_partition_id uuid not null,eligible_attendance_segments text[] not null check(eligible_attendance_segments<@array['conference','caravans']::text[]),revision bigint default 1);
      create table reservations.bookings(id uuid primary key,event_id uuid not null,scope_partition_id uuid not null,attendance_segments_snapshot text[] not null check(attendance_segments_snapshot<@array['conference','caravans']::text[]));
      create table reservations.attendance_records(id uuid primary key,booking_id uuid not null,scope_partition_id uuid not null,segment text not null check(segment in('conference','caravans')),attended boolean not null default false);
      create function reservations_private.mutate_scoped(p_device_id uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin if p_operation='create_event_period' then if p_args->>'p_kind' not in ('conference','caravans') or false then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE';end if;elsif p_operation='update_event_period' then if p_args->>'p_kind' not in ('conference','caravans') or false then raise exception 'RESERVATIONS_EVENT_PERIOD_OUT_OF_RANGE';end if;end if;return '{}'::jsonb;end$$;
      insert into reservations.events values('${event}','${partition}','2026-10-12','2026-10-14','${actor}','${actor}');
      insert into reservations.booking_types values('23000000-0000-0000-0000-000000000001','${event}','${partition}',array['conference'],1);
      insert into reservations.bookings values('24000000-0000-0000-0000-000000000001','${event}','${partition}',array['conference']);
    `);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,'supabase/migrations/20261031210000_conference_operational_lifecycle_unification.sql')]);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,'supabase/migrations/20261031213000_reservations_dynamic_attendance_periods.sql')]);
    assert.equal(query(`select count(*) from reservations.event_periods where event_id='${event}' and kind='conference'`),'1');
    query(`insert into reservations.event_periods(scope_partition_id,event_id,kind,starts_on,ends_on,display_order,created_by,updated_by) values('${partition}','${event}','workshop','2026-10-12','2026-10-14',1,'${actor}','${actor}')`);
    query(`update reservations.booking_types set eligible_attendance_segments=array['conference','workshop'] where id='23000000-0000-0000-0000-000000000001'`);
    assert.equal(query(`select eligible_attendance_segments @> array['workshop'] from reservations.booking_types where id='23000000-0000-0000-0000-000000000001'`),'t');

    function family(seed){
      const guardian=`3${seed}000000-0000-0000-0000-000000000001`,shared=`3${seed}000000-0000-0000-0000-000000000002`,independent=`3${seed}000000-0000-0000-0000-000000000003`;
      query(`insert into platform.people values('${guardian}','guardian'),('${shared}','shared'),('${independent}','independent');insert into public.conference_participations(id,conference_id,person_id,guardian_participation_id,updated_by,created_by) values('${guardian}','${conference}','${guardian}',null,'${actor}','${actor}'),('${shared}','${conference}','${shared}','${guardian}','${actor}','${actor}'),('${independent}','${conference}','${independent}','${guardian}','${actor}','${actor}');insert into public.conference_accommodation_occupancies values('4${seed}000000-0000-0000-0000-000000000001','${conference}',gen_random_uuid(),'${guardian}',1,5,'base',1,now(),'${actor}'),('4${seed}000000-0000-0000-0000-000000000002','${conference}',gen_random_uuid(),'${shared}',1,5,'shared',1,now(),'${actor}'),('4${seed}000000-0000-0000-0000-000000000003','${conference}',gen_random_uuid(),'${independent}',1,5,'base',1,now(),'${actor}');insert into public.conference_transport_assignments values('5${seed}000000-0000-0000-0000-000000000001','${conference}',gen_random_uuid(),'${guardian}','independent','adult',1,1),('5${seed}000000-0000-0000-0000-000000000002','${conference}',gen_random_uuid(),'${shared}','shared','child',null,1),('5${seed}000000-0000-0000-0000-000000000003','${conference}',gen_random_uuid(),'${independent}','independent','child',2,1)`);
      return {guardian,shared,independent};
    }
    const apology=family('1');
    query(`begin;select set_config('platform.phase1c_context',jsonb_build_object('purpose','PLATFORM_DEVICE_SESSION_DISPATCH','user_id','${actor}','device_id','${device}')::text,true);select public.set_conference_participation_status('${device}',gen_random_uuid(),'${apology.guardian}',1,'apologized');commit`);
    assert.equal(query(`select count(*) from public.conference_transport_assignments where participation_id in('${apology.guardian}','${apology.shared}')`),'0');
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${apology.independent}'`),'1');
    assert.equal(query(`select count(*) from public.conference_transport_assignments where participation_id='${apology.independent}'`),'1');

    const deleting=family('2');
    const deleted=JSON.parse(query(`begin;select set_config('platform.phase1c_context',jsonb_build_object('purpose','PLATFORM_DEVICE_SESSION_DISPATCH','user_id','${actor}','device_id','${device}')::text,true);select public.delete_conference_participation('${device}',gen_random_uuid(),'${deleting.guardian}',1);commit`).split('\n').filter(line=>line.startsWith('{')).pop());
    assert.equal(deleted.deleted,true);
    assert.equal(query(`select count(*) from public.conference_participations where id='${deleting.guardian}'`),'0');
    assert.equal(query(`select count(*) from public.conference_participations where id in('${deleting.shared}','${deleting.independent}') and guardian_participation_id is null`),'2');
    assert.equal(query(`select count(*) from platform.people where id in('${deleting.guardian}','${deleting.shared}','${deleting.independent}')`),'3');
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${deleting.independent}'`),'1');
  }finally{
    try{command('dropdb',['--if-exists',database]);}catch{}
  }
});
