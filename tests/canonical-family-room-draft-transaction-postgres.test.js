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
const database=`conference_family_draft_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(sql){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',sql]);}
function jsonb(value){return `'${JSON.stringify(value).replaceAll("'","''")}'::jsonb`;}

test('family room draft executes removal, key cleanup, capacity changes and reuse atomically',()=>{
  const actor='10000000-0000-0000-0000-000000000001';
  const device='11000000-0000-0000-0000-000000000001';
  const conference='20000000-0000-0000-0000-000000000001';
  const room='30000000-0000-0000-0000-000000000001';
  const otherRoom='30000000-0000-0000-0000-000000000002';
  command('createdb',[database]);
  try{
    for(const role of ['anon','authenticated','service_role'])if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f')query(`create role ${role} nologin`);
    query(`
      create extension if not exists pgcrypto;create schema platform;create schema platform_private;
      create table platform.people(id uuid primary key,full_name text,phone text,church text,gender text,date_of_birth date,created_by uuid,updated_by uuid);
      create table platform.audit_events(id uuid primary key default gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,operation_id uuid,source text);
      create table public.conferences(id uuid primary key,start_date date,end_date date,status text,deleted_at timestamptz);
      create table public.conference_participations(id uuid primary key,conference_id uuid,person_id uuid,status text default 'active',guardian_participation_id uuid,revision bigint default 1,created_by uuid,updated_by uuid,updated_at timestamptz default now());
      create table public.conference_accommodation_rooms(id uuid primary key,base_capacity integer,revision bigint default 1);
      create table public.conference_room_assignments(id uuid primary key default gen_random_uuid(),conference_id uuid,room_id uuid,extra_bed_capacity integer default 0,revision bigint default 1,key_holder_occupancy_id uuid,key_delivered_at timestamptz,key_delivered_by uuid,updated_at timestamptz default now(),updated_by uuid,unique(conference_id,room_id));
      create table public.conference_accommodation_occupancies(id uuid primary key,conference_id uuid,room_id uuid,participation_id uuid,arrival_day integer,leave_day integer,bed_type text,extra_bed_person_type text,revision bigint default 1,updated_at timestamptz default now(),updated_by uuid);
      create table public.conference_transport_assignments(id uuid primary key,conference_id uuid,participation_id uuid);
      create table public.family_draft_operations(operation_id uuid primary key,result jsonb);
      create table public.family_draft_trace(position bigint generated always as identity,action text);
      insert into public.conferences values('${conference}','2026-11-01','2026-11-04','active',null);
      insert into public.conference_accommodation_rooms values('${room}',2,1),('${otherRoom}',2,1);
      insert into public.conference_room_assignments(conference_id,room_id,extra_bed_capacity) values('${conference}','${room}',1),('${conference}','${otherRoom}',0);
      create function platform_private.require_conference_accommodation_context(uuid,uuid,text,boolean) returns jsonb language plpgsql as $$declare state text;begin select status into state from public.conferences where id=$2 and deleted_at is null;if state is null then raise exception 'CONFERENCE_NOT_FOUND';end if;if $4 and state<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE';end if;return jsonb_build_object('actorUserId','${actor}','authoritySource','test');end$$;
      create function platform_private.require_conference_participation_context(uuid,uuid,text,boolean) returns jsonb language sql as $$select '{}'::jsonb$$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql as $$select gen_random_uuid()$$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[]) returns void language sql as $$select$$;
      create function platform_private.require_conference_family_accommodation_leases(uuid,uuid,jsonb) returns uuid[] language sql as $$select array['${room}'::uuid,'${otherRoom}'::uuid]$$;
      create function platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid) returns uuid language plpgsql as $$declare changed uuid;begin insert into public.family_draft_trace(action) values('remove');delete from public.conference_accommodation_occupancies where participation_id=$1 returning id into changed;return changed;end$$;
      create function platform_private.clear_conference_room_key_on_stay_delete() returns trigger language plpgsql as $$begin update public.conference_room_assignments set key_holder_occupancy_id=null,key_delivered_at=null,key_delivered_by=null,revision=revision+1 where key_holder_occupancy_id=old.id;return old;end$$;
      create trigger clear_conference_room_key_on_stay_delete before delete on public.conference_accommodation_occupancies for each row execute function platform_private.clear_conference_room_key_on_stay_delete();
      create function public.trace_family_draft_removal() returns trigger language plpgsql as $$begin insert into public.family_draft_trace(action) values('remove');return old;end$$;
      create trigger trace_family_draft_removal before delete on public.conference_accommodation_occupancies for each row execute function public.trace_family_draft_removal();
      create function public.save_conference_accommodation_room_draft(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,jsonb,jsonb,jsonb) returns jsonb language plpgsql as $$declare occupied integer;begin
        if (select revision from public.conference_accommodation_rooms where id=$4)<>$5 then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;
        if (select revision from public.conference_room_assignments where conference_id=$3 and room_id=$4)<>$6 then raise exception 'ROOM_ASSIGNMENT_REVISION_CONFLICT' using errcode='40001';end if;
        select count(*) into occupied from public.conference_accommodation_occupancies where conference_id=$3 and room_id=$4 and bed_type<>'shared';
        if occupied>($7->>'baseCapacity')::integer+($7->>'extraBedCapacity')::integer then raise exception 'ACCOMMODATION_CAPACITY_CONFLICT';end if;
        insert into public.family_draft_trace(action) values('structure');
        update public.conference_accommodation_rooms set base_capacity=($7->>'baseCapacity')::integer,revision=revision+1 where id=$4;
        update public.conference_room_assignments set extra_bed_capacity=($7->>'extraBedCapacity')::integer,revision=revision+1 where conference_id=$3 and room_id=$4;
        return '{}'::jsonb;end$$;
      create function public.assign_conference_accommodation(uuid,uuid,uuid,uuid,integer,integer,text,text) returns jsonb language plpgsql as $$begin if $4='ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid then raise exception 'INJECTED_ASSIGN_FAILURE';end if;insert into public.family_draft_trace(action) values('assign');insert into public.conference_accommodation_occupancies values(gen_random_uuid(),$2,$3,$4,$5,$6,$7,$8,1,now(),'${actor}');return '{}'::jsonb;end$$;
      create function public.move_conference_accommodation(uuid,uuid,uuid,bigint,uuid,integer,integer,text,text) returns jsonb language plpgsql as $$begin insert into public.family_draft_trace(action) values('move');update public.conference_accommodation_occupancies set room_id=$5,arrival_day=$6,leave_day=$7,bed_type=$8,extra_bed_person_type=$9,revision=revision+1 where id=$3 and revision=$4;if not found then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;return '{}'::jsonb;end$$;
      create function public.replace_conference_accommodation(uuid,uuid,uuid,uuid,bigint,uuid,integer,text,text) returns jsonb language plpgsql as $$begin insert into public.family_draft_trace(action) values('replace');return '{}'::jsonb;end$$;
      create function public.remove_conference_accommodation(uuid,uuid,uuid,bigint) returns jsonb language plpgsql as $$begin delete from public.conference_accommodation_occupancies where id=$3 and revision=$4;if not found then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;return '{}'::jsonb;end$$;
      create function public.save_conference_family_accommodation_draft(p_device uuid,p_operation_id uuid,p_conference uuid,p_payload jsonb) returns jsonb language plpgsql as $$
      declare ctx jsonb;actor uuid;authz uuid;stay jsonb;child_draft jsonb;room_ids uuid[];v_room_id uuid;result jsonb;mutation jsonb;room_draft jsonb;resolved_children jsonb:='[]'::jsonb;mutation_results jsonb:='[]'::jsonb;guardian_draft jsonb;guardian_participation public.conference_participations%rowtype;child_participation public.conference_participations%rowtype;guardian_stay public.conference_accommodation_occupancies%rowtype;v_guardian_person_id uuid;v_child_person_id uuid;draft_room public.conference_accommodation_rooms%rowtype;draft_assignment public.conference_room_assignments%rowtype;
      begin
        select operation.result into result from public.family_draft_operations operation where operation.operation_id=p_operation_id;if result is not null then return result||jsonb_build_object('status','duplicate');end if;
        room_ids:=platform_private.require_conference_family_accommodation_leases(p_device,p_conference,p_payload);foreach v_room_id in array room_ids loop perform 1 from public.conference_accommodation_rooms where id=v_room_id for update;end loop;
        room_draft:=p_payload->'roomDraft';
        if room_draft is not null and jsonb_typeof(room_draft)<>'null' then
          select * into draft_assignment from public.conference_room_assignments where conference_id=p_conference and room_id=(room_draft->>'roomId')::uuid for update;
          if draft_assignment.revision<>(room_draft->>'expectedAssignmentRevision')::bigint then raise exception 'ROOM_ASSIGNMENT_REVISION_CONFLICT' using errcode='40001';end if;
          select * into draft_room from public.conference_accommodation_rooms where id=(room_draft->>'roomId')::uuid for update;
          if draft_room.revision<>(room_draft->>'expectedRevision')::bigint then raise exception 'ACCOMMODATION_REVISION_CONFLICT' using errcode='40001';end if;
        end if;
        if room_draft is not null and jsonb_typeof(room_draft)<>'null' and room_draft->'structure' is not null and jsonb_typeof(room_draft->'structure')<>'null' then
   perform public.save_conference_accommodation_room_draft(p_device,gen_random_uuid(),p_conference,(room_draft->>'roomId')::uuid,(room_draft->>'expectedRevision')::bigint,(room_draft->>'expectedAssignmentRevision')::bigint,room_draft->'structure','[]'::jsonb,'[]'::jsonb,'[]'::jsonb);
 end if;
        for stay in select value from jsonb_array_elements(p_payload->'stays') loop
          case stay->>'operation'
            when 'remove' then mutation:=public.remove_conference_accommodation(p_device,p_conference,(stay->>'occupancyId')::uuid,(stay->>'expectedRevision')::bigint);
            when 'move' then mutation:=public.move_conference_accommodation(p_device,p_conference,(stay->>'occupancyId')::uuid,(stay->>'expectedRevision')::bigint,(stay->>'targetRoomId')::uuid,(stay->>'arrivalDay')::integer,nullif(stay->>'leaveDay','')::integer,stay->>'bedType',nullif(stay->>'extraBedPersonType',''));
            when 'assign' then mutation:=public.assign_conference_accommodation(p_device,p_conference,(stay->>'targetRoomId')::uuid,(stay->>'participationId')::uuid,(stay->>'arrivalDay')::integer,nullif(stay->>'leaveDay','')::integer,stay->>'bedType',nullif(stay->>'extraBedPersonType',''));
            when 'replace' then mutation:=public.replace_conference_accommodation(p_device,gen_random_uuid(),p_conference,(stay->>'occupancyId')::uuid,(stay->>'expectedRevision')::bigint,(stay->>'participationId')::uuid,(stay->>'effectiveDay')::integer,stay->>'bedType',nullif(stay->>'extraBedPersonType',''));
          end case;
        end loop;
 for child_draft in select value from jsonb_array_elements(resolved_children) loop null;end loop;
        result:=jsonb_build_object('status','success');insert into public.family_draft_operations values(p_operation_id,result);return result;
      end$$;
    `);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,'supabase/migrations/20261124085051_canonical_family_room_draft_transaction_order.sql')]);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,'supabase/migrations/20261124101624_administrative_accommodation_removal_contract.sql')]);

    const holder='40000000-0000-0000-0000-000000000001',replacement='40000000-0000-0000-0000-000000000002';
    query(`insert into platform.people values('${holder}','holder',null,null,null,null,null,null),('${replacement}','replacement',null,null,null,null,null,null);insert into public.conference_participations(id,conference_id,person_id) values('${holder}','${conference}','${holder}'),('${replacement}','${conference}','${replacement}');insert into public.conference_accommodation_occupancies values('${holder}','${conference}','${room}','${holder}',1,5,'base',null,1,now(),'${actor}');update public.conference_room_assignments set key_holder_occupancy_id='${holder}',key_delivered_at=now(),key_delivered_by='${actor}' where conference_id='${conference}' and room_id='${room}';insert into public.conference_transport_assignments values(gen_random_uuid(),'${conference}','${holder}')`);
    const payload={roomDraft:{roomId:room,expectedRevision:1,expectedAssignmentRevision:1,structure:{baseCapacity:1,extraBedCapacity:0}},guardian:null,children:[],roomLeaseTokens:[],stays:[{operation:'assign',targetRoomId:room,participationId:replacement,arrivalDay:1,leaveDay:5,bedType:'base',extraBedPersonType:null},{operation:'remove',occupancyId:holder,expectedRevision:1}]};
    const operation='50000000-0000-0000-0000-000000000001';
    assert.match(query(`select public.save_conference_family_accommodation_draft('${device}','${operation}','${conference}',${jsonb(payload)})`),/success/);
    assert.equal(query(`select string_agg(action,',' order by position) from public.family_draft_trace`),'remove,structure,assign');
    assert.equal(query(`select revision||':'||extra_bed_capacity||':'||(key_holder_occupancy_id is null) from public.conference_room_assignments where conference_id='${conference}' and room_id='${room}'`),'3:0:true');
    assert.equal(query(`select count(*) from public.conference_transport_assignments where participation_id='${holder}'`),'1');
    assert.equal(query(`select count(*) from platform.audit_events where entity_id='${holder}' and metadata->>'administrativeCorrection'='true'`),'1');
    assert.match(query(`select public.save_conference_family_accommodation_draft('${device}','${operation}','${conference}',${jsonb(payload)})`),/duplicate/);

    query(`truncate public.family_draft_trace;update public.conference_accommodation_rooms set base_capacity=2,revision=revision+1 where id='${room}';update public.conference_room_assignments set extra_bed_capacity=0,revision=revision+1 where conference_id='${conference}' and room_id='${room}';insert into public.conference_accommodation_occupancies values(gen_random_uuid(),'${conference}','${room}','${holder}',1,5,'base',null,1,now(),'${actor}')`);
    const movingStay=query(`select id from public.conference_accommodation_occupancies where room_id='${room}' and participation_id='${holder}' limit 1`),roomRevision=query(`select revision from public.conference_accommodation_rooms where id='${room}'`),assignmentRevision=query(`select revision from public.conference_room_assignments where conference_id='${conference}' and room_id='${room}'`);
    const shrink={roomDraft:{roomId:room,expectedRevision:Number(roomRevision),expectedAssignmentRevision:Number(assignmentRevision),structure:{baseCapacity:1,extraBedCapacity:0}},guardian:null,children:[],roomLeaseTokens:[],stays:[{operation:'move',sourceRoomId:room,targetRoomId:otherRoom,roomId:room,occupancyId:movingStay,expectedRevision:1,arrivalDay:1,leaveDay:5,bedType:'base',extraBedPersonType:null}]};
    query(`select public.save_conference_family_accommodation_draft('${device}',gen_random_uuid(),'${conference}',${jsonb(shrink)})`);
    assert.equal(query(`select string_agg(action,',' order by position) from public.family_draft_trace`),'move,structure');

    const before=query(`select count(*)||':'||(select revision from public.conference_room_assignments where conference_id='${conference}' and room_id='${room}') from public.conference_accommodation_occupancies where conference_id='${conference}'`);
    const failing={roomDraft:{roomId:room,expectedRevision:Number(query(`select revision from public.conference_accommodation_rooms where id='${room}'`)),expectedAssignmentRevision:Number(query(`select revision from public.conference_room_assignments where conference_id='${conference}' and room_id='${room}'`)),structure:{baseCapacity:2,extraBedCapacity:0}},guardian:null,children:[],roomLeaseTokens:[],stays:[{operation:'assign',targetRoomId:room,participationId:'ffffffff-ffff-ffff-ffff-ffffffffffff',arrivalDay:1,leaveDay:5,bedType:'base',extraBedPersonType:null}]};
    assert.throws(()=>query(`select public.save_conference_family_accommodation_draft('${device}',gen_random_uuid(),'${conference}',${jsonb(failing)})`),/INJECTED_ASSIGN_FAILURE/);
    assert.equal(query(`select count(*)||':'||(select revision from public.conference_room_assignments where conference_id='${conference}' and room_id='${room}') from public.conference_accommodation_occupancies where conference_id='${conference}'`),before);
    const stale={...shrink,roomDraft:{...shrink.roomDraft,expectedRevision:1,expectedAssignmentRevision:Number(query(`select revision from public.conference_room_assignments where conference_id='${conference}' and room_id='${room}'`))}};
    assert.throws(()=>query(`select public.save_conference_family_accommodation_draft('${device}',gen_random_uuid(),'${conference}',${jsonb(stale)})`),/ACCOMMODATION_REVISION_CONFLICT/);

    const completedStay='60000000-0000-0000-0000-000000000001';
    query(`insert into public.conference_accommodation_occupancies values('${completedStay}','${conference}','${room}','${holder}',1,5,'base',null,1,now(),'${actor}');update public.conferences set status='completed' where id='${conference}'`);
    assert.throws(()=>query(`select public.remove_conference_accommodation('${device}','${conference}','${completedStay}',1)`),/COMPLETED_CONFERENCE_IMMUTABLE/);
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where id='${completedStay}'`),'1');

    query(`update public.conferences set status='active',start_date=current_date+10,end_date=current_date+14 where id='${conference}'`);
    assert.match(query(`select public.remove_conference_accommodation('${device}','${conference}','${completedStay}',1)`),/"deleted": true/);
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where id='${completedStay}'`),'0');

    const duringParticipation='70000000-0000-0000-0000-000000000001',duringStay='70000000-0000-0000-0000-000000000002';
    query(`insert into platform.people values('${duringParticipation}','during',null,null,null,null,null,null);insert into public.conference_participations(id,conference_id,person_id) values('${duringParticipation}','${conference}','${duringParticipation}');insert into public.conference_accommodation_occupancies values('${duringStay}','${conference}','${room}','${duringParticipation}',1,5,'base',null,1,now(),'${actor}');update public.conferences set start_date=current_date-1,end_date=current_date+3 where id='${conference}'`);
    assert.match(query(`select public.remove_conference_accommodation('${device}','${conference}','${duringStay}',1)`),/"deleted": true/);
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where id='${duringStay}'`),'0');

    const familyGuardian='80000000-0000-0000-0000-000000000001',familyChild='80000000-0000-0000-0000-000000000002',guardianStay='80000000-0000-0000-0000-000000000003',childStay='80000000-0000-0000-0000-000000000004';
    query(`insert into platform.people values('${familyGuardian}','guardian',null,null,null,null,null,null),('${familyChild}','child',null,null,null,null,null,null);insert into public.conference_participations(id,conference_id,person_id,guardian_participation_id) values('${familyGuardian}','${conference}','${familyGuardian}',null),('${familyChild}','${conference}','${familyChild}','${familyGuardian}');insert into public.conference_accommodation_occupancies values('${guardianStay}','${conference}','${room}','${familyGuardian}',1,5,'base',null,1,now(),'${actor}'),('${childStay}','${conference}','${otherRoom}','${familyChild}',1,5,'shared',null,1,now(),'${actor}');insert into public.conference_transport_assignments values(gen_random_uuid(),'${conference}','${familyGuardian}'),(gen_random_uuid(),'${conference}','${familyChild}')`);
    query(`select public.remove_conference_accommodation('${device}','${conference}','${guardianStay}',1)`);
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id in('${familyGuardian}','${familyChild}')`),'0');
    assert.equal(query(`select count(*) from public.conference_participations where id in('${familyGuardian}','${familyChild}')`),'2');
    assert.equal(query(`select count(*) from public.conference_transport_assignments where participation_id in('${familyGuardian}','${familyChild}')`),'2');

    const childOnly='90000000-0000-0000-0000-000000000001',childOnlyStay='90000000-0000-0000-0000-000000000002';
    query(`insert into platform.people values('${childOnly}','child only',null,null,null,null,null,null);insert into public.conference_participations(id,conference_id,person_id,guardian_participation_id) values('${childOnly}','${conference}','${childOnly}','${familyGuardian}');insert into public.conference_accommodation_occupancies values('${childOnlyStay}','${conference}','${otherRoom}','${childOnly}',1,5,'base',null,1,now(),'${actor}')`);
    query(`select public.remove_conference_accommodation('${device}','${conference}','${childOnlyStay}',1)`);
    assert.equal(query(`select count(*) from public.conference_participations where id='${familyGuardian}'`),'1');
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${childOnly}'`),'0');

    const historicalLifecycle='a0000000-0000-0000-0000-000000000001',historicalStay='a0000000-0000-0000-0000-000000000002';
    query(`insert into platform.people values('${historicalLifecycle}','historical',null,null,null,null,null,null);insert into public.conference_participations(id,conference_id,person_id) values('${historicalLifecycle}','${conference}','${historicalLifecycle}');insert into public.conference_accommodation_occupancies values('${historicalStay}','${conference}','${room}','${historicalLifecycle}',1,null,'base',null,1,now(),'${actor}');update public.conferences set start_date='2026-11-01',end_date='2026-11-04' where id='${conference}';select platform_private.cleanup_conference_accommodation_for_participation('${historicalLifecycle}','${actor}',gen_random_uuid(),'{}','participation_apologized',gen_random_uuid())`);
    assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where id='${historicalStay}'`),'1');
  }finally{
    try{command('dropdb',['--if-exists',database]);}catch{}
  }
});
