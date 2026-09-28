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

test('disposable PostgreSQL proves protected Accommodation behavior and concurrency',async(t)=>{
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
    // Independent five-day fixtures exercise the temporal contract through protected RPCs.
    query(`update public.conferences set end_date='2027-01-05' where id='${conference}'`);
    let roomNumber=200;
    function newRoom(base=1,extra=1,closed=false,day=null){
      return mutate('create_room',`jsonb_build_object('p_conference_id','${conference}','p_floor_id','${floor.floorId}','p_room_number','${roomNumber++}','p_base_capacity',${base},'p_extra_bed_capacity',${extra},'p_notes',null,'p_is_closed',${closed},'p_closed_day',${day},'p_position',0)`).roomId;
    }
    function newParticipation(){
      return query(`with person as (insert into platform.people(id,full_name) values(extensions.gen_random_uuid(),'Temporal') returning id) insert into public.conference_participations(id,conference_id,person_id,status) select extensions.gen_random_uuid(),'${conference}',id,'active' from person returning id` ).split('\n')[0];
    }
    function assignSql(room,arrival,leave,bed='base'){
      return `select public.assign_conference_accommodation('${device}','${conference}','${room}','${newParticipation()}',${arrival},${leave},'${bed}',${bed==='extra'?"'adult'":'null'})`;
    }
    function assign(room,arrival,leave,bed='base'){return JSON.parse(query(assignSql(room,arrival,leave,bed)));}
    function moveSql(occupancy,room,arrival,leave,bed='base'){
      return `select public.move_conference_accommodation('${device}','${conference}','${occupancy.occupancyId}',${occupancy.revision},'${room}',${arrival},${leave},'${bed}',${bed==='extra'?"'adult'":'null'})`;
    }
    function updateSql(room,base,extra,closed=false,day=null){
      return `select public.mutate_conference_accommodation_structure('${device}','update_room',jsonb_build_object('p_conference_id','${conference}','p_room_id','${room}','p_expected_revision',(select revision from public.conference_accommodation_rooms where id='${room}'),'p_room_number',(select room_number from public.conference_accommodation_rooms where id='${room}'),'p_base_capacity',${base},'p_extra_bed_capacity',${extra},'p_notes',null,'p_is_closed',${closed},'p_closed_day',${day},'p_position',0))`;
    }
    await t.test('ASSIGN and MOVE accept departure after final day but reject invalid boundaries',()=>{
      for(const bed of ['base','extra']){
        for(const [arrival,leave] of [[4,6],[5,6],[4,null]]){
          const assigned=assign(newRoom(),arrival,leave,bed);
          const moved=JSON.parse(query(moveSql(assigned,newRoom(),arrival,leave,bed)));
          assert.equal(moved.occupancyId,assigned.occupancyId); assert.equal(moved.revision,2);
          assert.deepEqual(JSON.parse(query(`select jsonb_build_array(arrival_day,leave_day) from public.conference_accommodation_occupancies where id='${moved.occupancyId}'`)),[arrival,leave]);
        }
        const source=assign(newRoom(),1,3,bed),destination=newRoom();
        for(const [arrival,leave] of [[4,7],[6,null],[6,7],[4,4],[4,3],[0,6]]){
          rejects(assignSql(destination,arrival,leave,bed),/ACCOMMODATION_STAY_INVALID/);
          rejects(moveSql(source,destination,arrival,leave,bed),/ACCOMMODATION_STAY_INVALID/);
        }
        const sequential=newRoom(); assign(sequential,1,3,bed); assign(sequential,3,6,bed);
        rejects(assignSql(sequential,5,null,bed),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
        const moveDestination=newRoom(); assign(moveDestination,1,3,bed);
        assert.equal(JSON.parse(query(moveSql(source,moveDestination,3,6,bed))).occupancyId,source.occupancyId);
        query(updateSql(sequential,1,1));
      }
    });
    await t.test('explicit final departure retains scheduled closure boundaries',()=>{
      const closed=newRoom(2,1,true,5); assign(closed,4,5);
      const source=assign(newRoom(),4,6);
      rejects(assignSql(closed,4,6),/ACCOMMODATION_ROOM_UNAVAILABLE/);
      rejects(moveSql(source,closed,4,6),/ACCOMMODATION_ROOM_UNAVAILABLE/);
      assert.equal(JSON.parse(query(moveSql(source,closed,4,5))).occupancyId,source.occupancyId);
      const occupied=newRoom(); assign(occupied,4,6);
      rejects(updateSql(occupied,1,1,true,5),/ACCOMMODATION_CLOSURE_CONFLICT/);
    });
    await t.test('half-open sequential stays reuse base and extra capacity; overlaps reject',()=>{
      for(const bed of ['base','extra']){
        const room=newRoom(); assign(room,1,3,bed); assign(room,3,5,bed);
        rejects(assignSql(room,2,4,bed),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
        const overlapping=newRoom(); assign(overlapping,1,4,bed);
        rejects(assignSql(overlapping,3,5,bed),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
      }
    });
    await t.test('NULL leave occupies through final Conference day; bed capacities are independent',()=>{
      const room=newRoom(); assign(room,1,3); assign(room,3,null);
      assign(room,1,null,'extra');
      rejects(assignSql(room,5,null),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
      rejects(assignSql(room,5,null,'extra'),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
      const openEnded=newRoom(); assign(openEnded,3,5);
      rejects(assignSql(openEnded,1,null),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
    });
    await t.test('capacity reduction uses separate daily peaks including NULL leave',()=>{
      const room=newRoom(3,3);
      for(const bed of ['base','extra']){assign(room,1,3,bed); assign(room,3,null,bed);}
      query(updateSql(room,1,1));
      rejects(updateSql(room,0,1),/ACCOMMODATION_CAPACITY_CONFLICT/);
      rejects(updateSql(room,1,0),/ACCOMMODATION_CAPACITY_CONFLICT/);
      query(updateSql(room,3,3));
      assign(room,2,4); assign(room,2,4,'extra');
      rejects(updateSql(room,1,2),/ACCOMMODATION_CAPACITY_CONFLICT/);
      rejects(updateSql(room,2,1),/ACCOMMODATION_CAPACITY_CONFLICT/);
      query(updateSql(room,2,2));
      query(updateSql(newRoom(),0,0));
    });
    await t.test('scheduled and immediate closure enforce identical ASSIGN and MOVE boundaries',()=>{
      const room=newRoom(2,1,true,3); assign(room,1,3);
      const moving=assign(newRoom(),1,3);
      assert.equal(JSON.parse(query(moveSql(moving,room,1,3))).occupancyId,moving.occupancyId);
      for(const [arrival,leave] of [[1,4],[3,5],[4,5],[1,null]]){
        rejects(assignSql(room,arrival,leave),/ACCOMMODATION_ROOM_UNAVAILABLE/);
        const source=assign(newRoom(),1,3);
        rejects(moveSql(source,room,arrival,leave),/ACCOMMODATION_ROOM_UNAVAILABLE/);
      }
      const immediate=newRoom(2,2,true);
      rejects(assignSql(immediate,1,3),/ACCOMMODATION_ROOM_UNAVAILABLE/);
      rejects(moveSql(assign(newRoom(),1,3),immediate,1,3),/ACCOMMODATION_ROOM_UNAVAILABLE/);
    });
    await t.test('closure updates accept leave D, reject crossing, starting D, NULL and immediate occupancy',()=>{
      const boundary=newRoom(); assign(boundary,1,3); query(updateSql(boundary,1,1,true,3));
      rejects(updateSql(boundary,1,1,true,null),/ACCOMMODATION_CLOSURE_CONFLICT/);
      for(const [arrival,leave] of [[1,4],[3,5],[4,5],[1,null]]){
        const room=newRoom(); assign(room,arrival,leave);
        rejects(updateSql(room,1,1,true,3),/ACCOMMODATION_CLOSURE_CONFLICT/);
        assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where room_id='${room}'`),'1');
      }
      query(updateSql(newRoom(),1,1,true,null));
    });
    await t.test('MOVE rejects overlapping full destination, allows sequential destination and excludes itself',()=>{
      for(const bed of ['base','extra']){
        const destination=newRoom(); assign(destination,1,3,bed);
        const source=assign(newRoom(),1,3,bed);
        rejects(moveSql(source,destination,2,4,bed),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
        const moved=JSON.parse(query(moveSql(source,destination,3,5,bed)));
        assert.equal(moved.occupancyId,source.occupancyId); assert.equal(moved.revision,2);
        assert.equal(JSON.parse(query(moveSql(moved,destination,3,5,bed))).revision,3);
      }
    });
    async function waitForSession(name,event){
      for(let attempt=0;attempt<100;attempt++){
        if(query(`select exists(select 1 from pg_stat_activity where datname='${database}' and application_name='${name}' and ${event})`)==='t') return;
        await new Promise(resolve=>setTimeout(resolve,10));
      }
      assert.fail(`session ${name} did not reach ${event}`);
    }
    async function temporalRace(overlap){
      const room=newRoom();
      const firstSql=assignSql(room,1,3),secondSql=assignSql(room,overlap?2:3,5);
      // First transaction holds the destination lock; prove the second waits for it.
      const first=queryAsync(`begin; set application_name='p5b_first'; ${firstSql}; select pg_sleep(2); commit`);
      let second;
      try{
        await waitForSession('p5b_first',"wait_event='PgSleep'");
        second=queryAsync(`set application_name='p5b_second'; ${secondSql}`);
        // Attach rejection handling immediately, while observing the blocked backend.
        const results=Promise.allSettled([first,second]);
        await waitForSession('p5b_second',"wait_event_type='Lock'");
        const settled=await results;
        assert.equal(settled.filter(result=>result.status==='fulfilled').length,overlap?1:2);
        if(overlap) assert.match(String(settled[1].reason.stderr),/ACCOMMODATION_ROOM_CAPACITY_EXCEEDED/);
        assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where room_id='${room}'`),overlap?'1':'2');
      }finally{await Promise.allSettled([first,...(second?[second]:[])]);}
    }
    await t.test('overlapping final-slot concurrency: exactly one succeeds',()=>temporalRace(true));
    await t.test('non-overlapping same-slot concurrency: both succeed',()=>temporalRace(false));

  }finally{command('dropdb',['--if-exists',database]); for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);}
});
