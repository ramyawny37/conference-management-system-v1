'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const vm=require('node:vm');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration=path.join(root,'supabase/migrations/20261102120000_conference_participation_booking_projection.sql');
const sql=fs.readFileSync(migration,'utf8');
const script=fs.readFileSync(path.join(root,'script.js'),'utf8');
const integration=fs.readFileSync(path.join(root,'js/platform-integration.js'),'utf8');
const index=fs.readFileSync(path.join(root,'index.html'),'utf8');
const reservations=fs.readFileSync(path.join(root,'modules/reservations/reservations-module.js'),'utf8');

function functionSource(source,name){
  const start=source.indexOf(`function ${name}(`);
  assert.notEqual(start,-1,`${name} exists`);
  const body=source.indexOf('{',start);let depth=0,quote='',escaped=false;
  for(let cursor=body;cursor<source.length;cursor++){
    const character=source[cursor];
    if(quote){if(escaped)escaped=false;else if(character==='\\')escaped=true;else if(character===quote)quote='';continue;}
    if(character==='"'||character==="'"||character==='`'){quote=character;continue;}
    if(character==='{')depth++;else if(character==='}'&&--depth===0)return source.slice(start,cursor+1);
  }
  throw new Error(`${name} is incomplete`);
}

test('projection is canonical-person keyed, conference scoped, snapshot preserving, and ACL closed',()=>{
  assert.match(sql,/reservation_participant\.person_id=participation\.person_id/);
  assert.match(sql,/event\.conference_id=p_conference_id/);
  assert.match(sql,/booking_type_name_snapshot/);
  assert.match(sql,/price_snapshot/);
  assert.match(sql,/attendance_segments_snapshot/);
  assert.match(sql,/order by booking\.created_at desc,booking\.id desc/);
  assert.match(sql,/revoke all on function public\.list_conference_participations\(uuid,uuid\)/);
  assert.doesNotMatch(sql,/conference_snapshots|peopleDb|grant execute/i);
});

test('accommodation selection exposes combined category, booking type, period and search filters without changing mutation eligibility',()=>{
  for(const id of ['canonicalAccommodationCategoryFilter','canonicalAccommodationBookingTypeFilter','canonicalAccommodationPeriodFilter','canonicalAccommodationAssignmentResultCount']){
    assert.match(index,new RegExp(`id="${id}"`));
  }
  const list=functionSource(script,'renderCanonicalAccommodationAssignmentCandidateList');
  assert.match(list,/normalizePersonKey/);
  assert.match(list,/guardianParticipationId/);
  assert.match(list,/bookingTypeId===bookingType/);
  assert.match(list,/attendanceSegmentsSnapshot\.indexOf\(period\)/);
  assert.match(list,/النتائج المطابقة/);
  assert.doesNotMatch(list,/assignConferenceAccommodation|moveConferenceAccommodation|saveConferenceFamilyAccommodationDraft/);
  const available=functionSource(script,'getCanonicalAccommodationAvailableParticipations');
  assert.match(available,/status==='active'/);
  assert.match(available,/canonicalAccommodationIntervalsOverlap/);
});

test('participation projection retains every booking instead of selecting an arbitrary first booking',()=>{
  const projection=functionSource(integration,'participationProjection');
  assert.match(projection,/projected\.bookings=/);
  assert.match(projection,/\.map\(function\(booking\)/);
  assert.match(projection,/bookingTypeNameSnapshot/);
  assert.match(projection,/attendancePeriods/);
  assert.doesNotMatch(projection,/bookings\[0\]|\.find\(/);
});

test('booking and report filters consume canonical people fields and dynamic event periods',()=>{
  const participant=functionSource(reservations,'Wa');
  assert.match(participant,/gender:t\.gender/);
  assert.match(participant,/dateOfBirth:t\.date_of_birth/);
  assert.match(participant,/operationalCategory:t\.operational_category/);
  const reportFilter=functionSource(reservations,'xb');
  assert.match(reportFilter,/participant\.gender/);
  assert.match(reportFilter,/operationalCategory/);
  assert.match(reportFilter,/attendanceSegmentsSnapshot\.includes\(a\.attendancePeriod\)/);
  const distribution=functionSource(reservations,'_b');
  assert.match(distribution,/i\.map\(m=>\(\{kind:m\.kind,label:m\.label/);
  assert.doesNotMatch(distribution,/conferenceOnly|caravansOnly|conferenceAttended|caravansAttended/);
  const paymentTiming=functionSource(reservations,'Yl');
  assert.doesNotMatch(paymentTiming,/conference|caravans/);
});

const postgresApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresApp,'psql'))?postgresApp:'';
const database=`participation_booking_projection_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe'}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}

test('disposable PostgreSQL proves multiple bookings, no-booking participants, labels, and no cross-conference leakage',()=>{
  command('createdb',[database]);
  try{
    query(`create schema platform;create schema platform_private;create schema reservations;create extension if not exists pgcrypto;
      create table platform.people(id uuid primary key,full_name text,phone text,gender text,date_of_birth date,church text);
      create table public.conference_participations(id uuid primary key,conference_id uuid,person_id uuid,status text,revision bigint,guardian_participation_id uuid,created_at timestamptz default now(),updated_at timestamptz default now(),created_by uuid,updated_by uuid);
      create table reservations.events(id uuid primary key,scope_partition_id uuid,conference_id uuid);
      create table reservations.participants(id uuid primary key,scope_partition_id uuid,person_id uuid);
      create table reservations.booking_types(id uuid primary key);
      create table reservations.bookings(id uuid primary key,scope_partition_id uuid,booking_number text,participant_id uuid,event_id uuid,booking_type_id uuid,booking_type_name_snapshot text,price_snapshot numeric,attendance_segments_snapshot text[],created_at timestamptz);
      create table reservations.event_periods(event_id uuid,scope_partition_id uuid,kind text,label text);
      create function platform_private.require_conference_participation_context(uuid,uuid,text,boolean) returns jsonb language sql as $$select '{}'::jsonb$$;
      create function reservations_private_read_probe() returns void language sql as $$select$$;
      create schema reservations_private;
      create function reservations_private.read_scoped(uuid,text,jsonb) returns jsonb language plpgsql as $$declare result jsonb;begin select to_jsonb(p) into result from reservations.participants p limit 1;return result;end$$;
      insert into platform.people values
       ('10000000-0000-4000-8000-000000000001','One','010','male','1990-01-01','A'),
       ('10000000-0000-4000-8000-000000000002','No Booking','011',null,null,'B');
      insert into public.conference_participations(id,conference_id,person_id,status,revision,created_by,updated_by) values
       ('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','active',1,gen_random_uuid(),gen_random_uuid()),
       ('20000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','active',1,gen_random_uuid(),gen_random_uuid());
      insert into reservations.events values
       ('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001'),
       ('40000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002');
      insert into reservations.participants values
       ('60000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001'),
       ('60000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001');
      insert into reservations.booking_types values('70000000-0000-4000-8000-000000000001'),('70000000-0000-4000-8000-000000000002');
      insert into reservations.event_periods values('40000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','full','إقامة كاملة');
      insert into reservations.bookings values
       ('80000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','RES-1','60000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','Full',500,array['full'],now()-interval '1 day'),
       ('80000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000001','RES-2','60000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000002','Second',250,array['full'],now()),
       ('80000000-0000-4000-8000-000000000003','50000000-0000-4000-8000-000000000002','LEAK','60000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000002','Other Conference',999,array['other'],now());`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migration]);
    assert.match(query(`select reservations_private.read_scoped(gen_random_uuid(),'probe','{}')`),/"gender": "male"/);
    assert.match(query(`select pg_get_functiondef('reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure)`),/participants_canonical/);
    const result=JSON.parse(query(`select public.list_conference_participations(gen_random_uuid(),'30000000-0000-4000-8000-000000000001')`));
    assert.equal(result.items.length,2);
    const booked=result.items.find(item=>item.person.fullName==='One');
    const unbooked=result.items.find(item=>item.person.fullName==='No Booking');
    assert.equal(booked.bookings.length,2);
    assert.deepEqual(booked.bookings.map(booking=>booking.bookingNumber),['RES-2','RES-1']);
    assert.equal(booked.bookings[0].attendancePeriods[0].label,'إقامة كاملة');
    assert.equal(unbooked.bookings.length,0);
    assert.equal(JSON.stringify(result).includes('LEAK'),false);
  }finally{command('dropdb',['--if-exists',database]);}
});
