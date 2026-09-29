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
const p5a='supabase/migrations/20260928170000_canonical_conference_accommodation_data_foundation.sql';
const p5b='supabase/migrations/20260929120000_canonical_conference_accommodation_protected_mutations.sql';
const migration='supabase/migrations/20260929160000_canonical_conference_participation_accommodation_propagation.sql';
const sql=fs.readFileSync(path.join(root,migration),'utf8');

test('P5C extends canonical participation lifecycle without new routing or ledger',()=>{
  assert.match(sql,/create or replace function public\.set_conference_participation_status/);
  assert.match(sql,/create or replace function public\.delete_conference_participation/);
  assert.match(sql,/create or replace function public\.assign_conference_accommodation/);
  assert.match(sql,/create or replace function public\.move_conference_accommodation/);
  assert.match(sql,/create function platform_private\.cleanup_conference_accommodation_for_participation/);
  assert.match(sql,/create trigger conference_accommodation_occupancy_parent_immutable/);
  assert.match(sql,/new\.participation_id is distinct from old\.participation_id/);
  assert.match(sql,/new\.conference_id is distinct from old\.conference_id/);
  assert.doesNotMatch(sql,/create table|execute_conference_device_operation|route_canonical_conference_operation|conference_snapshots|reservations\.|transport|warehouse\./i);
  assert.match(sql,/'permissionKey','conference\.people\.manage'/);
  assert.match(sql,/'cause',p_cause/);
  assert.match(sql,/where id=p_participation and conference_id=p_conference for update/);
  assert.match(sql,/order by id for update/);
  assert.equal((sql.match(/select \* into v_current from public\.conference_participations where id=p_participation_id for update;[\s\S]*?require_conference_participation_context\(\s*p_actor_device_id,v_current\.conference_id,'conference\.people\.manage',true\)/g)||[]).length,2);
});

const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_p5c_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
async function queryAsync(statement){return (await execFileAsync(pgBin?path.join(pgBin,'psql'):'psql',[...connection,'-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement],{encoding:'utf8',env})).stdout.trim();}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves lifecycle propagation, replay, authority and lock races',async(t)=>{
  const actor='10000000-0000-0000-0000-000000000001',device='11000000-0000-0000-0000-000000000001',authz='12000000-0000-0000-0000-000000000001';
  const conference='20000000-0000-0000-0000-000000000001';
  const roles=['anon','authenticated','service_role'],created=[];
  command('createdb',[database]);
  try{
    for(const role of roles) if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}
    query(`create schema extensions; create extension pgcrypto with schema extensions; create schema platform; create schema platform_private;
      create table platform.profiles(user_id uuid primary key);
      create table platform.people(id uuid primary key,full_name text,phone text,gender text,date_of_birth date,church text);
      create table public.conferences(id uuid primary key,start_date date,end_date date,status text,deleted_at timestamptz);
      create table public.conference_participations(id uuid primary key default extensions.gen_random_uuid(),conference_id uuid not null references public.conferences(id) on delete restrict,person_id uuid not null references platform.people(id) on delete restrict,status text not null default 'active',revision bigint not null default 1,created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(conference_id,person_id));
      create table public.conference_participation_operations(actor_user_id uuid not null references platform.profiles(user_id),operation_id uuid not null,operation text not null,request jsonb not null,result jsonb not null,created_at timestamptz not null default statement_timestamp(),primary key(actor_user_id,operation_id));
      alter table public.conference_participations enable row level security; alter table public.conference_participations force row level security;
      alter table public.conference_participation_operations enable row level security; alter table public.conference_participation_operations force row level security;
      revoke all on public.conference_participations,public.conference_participation_operations from public,anon,authenticated,service_role;
      create table public.module_permission_catalog(permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text);
      create table public.p5c_context(people_manage boolean,accommodation_manage boolean,enabled boolean);
      insert into public.p5c_context values(true,true,true);
      create table platform.audit_events(id uuid primary key default extensions.gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,request_id uuid,operation_id uuid,source text,occurred_at timestamptz default now());
      insert into public.module_permission_catalog values
        ('conference.people.view','conference','active','resource','conference'),
        ('conference.people.manage','conference','active','resource','conference'),
        ('conference.accommodation.view','conference','active','resource','conference'),
        ('conference.accommodation.manage','conference','active','resource','conference');
      insert into platform.profiles values('${actor}');
      insert into public.conferences values('${conference}','2027-01-01','2027-01-05','active',null);
      create function public.require_effective_module_permission(uuid,text,text,text,text) returns jsonb language plpgsql stable as \$\$ declare allowed boolean; begin select enabled and case \$3 when 'conference.people.manage' then people_manage when 'conference.people.view' then true when 'conference.accommodation.manage' then accommodation_manage when 'conference.accommodation.view' then true else false end into allowed from public.p5c_context; if not coalesce(allowed,false) then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if; return jsonb_build_object('actorUserId','${actor}','authoritySource','resource_grant','grantId','13000000-0000-0000-0000-000000000001'); end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql stable as \$\$ select case when \$1='${actor}' and \$2='${device}' and (select enabled from public.p5c_context) then '${authz}'::uuid end \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language sql immutable as \$\$ select \$\$;
      create function platform_private.require_conference_participation_context(uuid,uuid,text,boolean) returns jsonb language plpgsql stable security definer set search_path='' as \$\$ declare context jsonb; state text; begin context:=public.require_effective_module_permission(\$1,'conference',\$3,'conference',\$2::text); select status into state from public.conferences where id=\$2 and deleted_at is null; if state is null then raise exception 'CONFERENCE_NOT_FOUND'; end if; if \$4 and state<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE'; end if; return context; end \$\$;
      create function public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.list_conference_participations(uuid,uuid) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.create_conference_participation(uuid,uuid,uuid,uuid) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.delete_conference_participation(uuid,uuid,uuid,bigint) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,p5a)]);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,p5b)]);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    query(`create function platform_private.p5c_delete(uuid,uuid,uuid,bigint) returns jsonb language plpgsql security definer set search_path='' as \$\$ begin perform set_config('platform.phase1c_context',jsonb_build_object('purpose','PLATFORM_DEVICE_SESSION_DISPATCH','user_id','${actor}','device_id',\$1)::text,true); return public.delete_conference_participation(\$1,\$2,\$3,\$4); end \$\$; revoke all on function platform_private.p5c_delete(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;`);
    const mutate=(op,args)=>JSON.parse(query(`select public.mutate_conference_accommodation_structure('${device}','${op}',${args})`));
    const house=mutate('create_house',`jsonb_build_object('p_conference_id','${conference}','p_name','H','p_description',null,'p_position',0)`);
    const floor=mutate('create_floor',`jsonb_build_object('p_conference_id','${conference}','p_house_id','${house.houseId}','p_name','F','p_position',0)`);
    const room1=mutate('create_room',`jsonb_build_object('p_conference_id','${conference}','p_floor_id','${floor.floorId}','p_room_number','101','p_base_capacity',50,'p_extra_bed_capacity',0,'p_notes',null,'p_is_closed',false,'p_closed_day',null,'p_position',0)`).roomId;
    const room2=mutate('create_room',`jsonb_build_object('p_conference_id','${conference}','p_floor_id','${floor.floorId}','p_room_number','102','p_base_capacity',50,'p_extra_bed_capacity',0,'p_notes',null,'p_is_closed',false,'p_closed_day',null,'p_position',1)`).roomId;
    let sequence=1;
    function participant(){
      const suffix=String(sequence++).padStart(12,'0'),person=`30000000-0000-0000-0000-${suffix}`,part=`40000000-0000-0000-0000-${suffix}`;
      query(`insert into platform.people(id,full_name) values('${person}','Person ${suffix}'); insert into public.conference_participations(id,conference_id,person_id,created_by,updated_by) values('${part}','${conference}','${person}','${actor}','${actor}')`);
      return {person,part};
    }
    function assign(part,room=room1){return JSON.parse(query(`select public.assign_conference_accommodation('${device}','${conference}','${room}','${part}',1,6,'base',null)`));}
    function status(part,revision,value,operation=`50000000-0000-0000-0000-${String(sequence++).padStart(12,'0')}`){return JSON.parse(query(`select public.set_conference_participation_status('${device}','${operation}','${part}',${revision},'${value}')`));}
    function remove(occupancy,revision=1){return query(`select public.remove_conference_accommodation('${device}','${conference}','${occupancy}',${revision})`);}
    function deletion(part,revision,operation=`60000000-0000-0000-0000-${String(sequence++).padStart(12,'0')}`){return JSON.parse(query(`select platform_private.p5c_delete('${device}','${operation}','${part}',${revision})`));}
    function cleanupCount(part,cause){return query(`select count(*) from platform.audit_events where action='conference.accommodation.participation_cleanup' and metadata->>'participationId'='${part}' and metadata->>'cause'='${cause}'`);}

    await t.test('apology cleanup, no-op cleanup absence, reactivation and replay',()=>{
      const withStay=participant(),occupancy=assign(withStay.part),op='51000000-0000-0000-0000-000000000001';
      const apologized=status(withStay.part,1,'apologized',op);
      assert.equal(apologized.status,'apologized'); assert.equal(apologized.revision,2);
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${withStay.part}'`),'0');
      assert.equal(query(`select count(*) from platform.people where id='${withStay.person}'`),'1');
      assert.equal(cleanupCount(withStay.part,'participation_apologized'),'1');
      assert.equal(query(`select count(*) from platform.audit_events where action='conference.participation.status_changed' and operation_id='${op}'`),'1');
      const cleanupAudit=JSON.parse(query(`select jsonb_build_object('actor',actor_user_id,'authorization',actor_device_authorization_id,'oldOccupancy',old_values->>'id','conference',metadata->>'conferenceId','participation',metadata->>'participationId','occupancy',metadata->>'occupancyId','room',metadata->>'previousRoomId','permission',metadata->>'permissionKey','source',metadata->>'authoritySource','grant',metadata->>'grantId') from platform.audit_events where action='conference.accommodation.participation_cleanup' and operation_id='${op}'`));
      assert.deepEqual(cleanupAudit,{actor,authorization:authz,oldOccupancy:occupancy.occupancyId,conference,participation:withStay.part,occupancy:occupancy.occupancyId,room:room1,permission:'conference.people.manage',source:'resource_grant',grant:'13000000-0000-0000-0000-000000000001'});
      assert.deepEqual(status(withStay.part,1,'apologized',op),apologized);
      assert.equal(cleanupCount(withStay.part,'participation_apologized'),'1');
      assert.equal(query(`select count(*) from platform.audit_events where action='conference.participation.status_changed' and operation_id='${op}'`),'1');
      const active=status(withStay.part,2,'active'); assert.equal(active.status,'active'); assert.equal(active.revision,3);
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${withStay.part}'`),'0');
      const withoutStay=participant(); status(withoutStay.part,1,'apologized');
      assert.equal(cleanupCount(withoutStay.part,'participation_apologized'),'0');
      assert.ok(occupancy.occupancyId);
    });

    await t.test('delete cleanup, restrictive FK, Person survival and replay',()=>{
      const withStay=participant(); assign(withStay.part); const op='61000000-0000-0000-0000-000000000001';
      const deleted=deletion(withStay.part,1,op); assert.equal(deleted.deleted,true);
      assert.equal(query(`select count(*) from public.conference_participations where id='${withStay.part}'`),'0');
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${withStay.part}'`),'0');
      assert.equal(query(`select count(*) from platform.people where id='${withStay.person}'`),'1');
      assert.equal(cleanupCount(withStay.part,'participation_deleted'),'1');
      assert.equal(query(`select count(*) from platform.audit_events where action='conference.participation.deleted' and operation_id='${op}'`),'1');
      assert.deepEqual(deletion(withStay.part,1,op),deleted); assert.equal(cleanupCount(withStay.part,'participation_deleted'),'1');
      assert.equal(query(`select count(*) from platform.audit_events where action='conference.participation.deleted' and operation_id='${op}'`),'1');
      const withoutStay=participant(); deletion(withoutStay.part,1); assert.equal(cleanupCount(withoutStay.part,'participation_deleted'),'0');
      assert.equal(query(`select confdeltype from pg_constraint where conname='conference_accommodation_occupancies_participation_fk'`),'r');
    });

    await t.test('people.manage authorizes lifecycle consequence while explicit Accommodation stays protected',()=>{
      const apology=participant(),deleting=participant(),explicit=participant();
      const apologyOccupancy=assign(apology.part),deleteOccupancy=assign(deleting.part),explicitOccupancy=assign(explicit.part);
      query(`update public.p5c_context set accommodation_manage=false`);
      status(apology.part,1,'apologized'); deletion(deleting.part,1);
      assert.equal(cleanupCount(apology.part,'participation_apologized'),'1'); assert.equal(cleanupCount(deleting.part,'participation_deleted'),'1');
      rejects(`select public.assign_conference_accommodation('${device}','${conference}','${room1}','${participant().part}',1,6,'base',null)`,/MODULE_PERMISSION_REQUIRED/);
      rejects(`select public.move_conference_accommodation('${device}','${conference}','${explicitOccupancy.occupancyId}',1,'${room2}',1,6,'base',null)`,/MODULE_PERMISSION_REQUIRED/);
      rejects(`select public.remove_conference_accommodation('${device}','${conference}','${explicitOccupancy.occupancyId}',1)`,/MODULE_PERMISSION_REQUIRED/);
      query(`update public.p5c_context set accommodation_manage=true`);
      assert.ok(apologyOccupancy.occupancyId); assert.ok(deleteOccupancy.occupancyId); remove(explicitOccupancy.occupancyId);
    });

    await t.test('occupancy parent identity is structurally immutable',()=>{
      const owner=participant(),other=participant(),occupancy=assign(owner.part);
      rejects(`update public.conference_accommodation_occupancies set participation_id='${other.part}' where id='${occupancy.occupancyId}'`,/ACCOMMODATION_OCCUPANCY_PARENT_IMMUTABLE/);
      assert.equal(query(`select participation_id from public.conference_accommodation_occupancies where id='${occupancy.occupancyId}'`),owner.part);
      remove(occupancy.occupancyId);
    });

    for(const role of roles){
      assert.equal(query(`select has_function_privilege('${role}','platform_private.prevent_conference_accommodation_occupancy_reparenting()','EXECUTE')`),'f');
      assert.equal(query(`select has_function_privilege('${role}','platform_private.cleanup_conference_accommodation_for_participation(uuid,uuid,uuid,jsonb,text,uuid)','EXECUTE')`),'f');
      assert.equal(query(`select has_table_privilege('${role}','public.conference_accommodation_occupancies','INSERT,UPDATE,DELETE')`),'f');
    }

    async function waitFor(name,predicate){
      for(let attempt=0;attempt<100;attempt++){
        if(query(`select exists(select 1 from pg_stat_activity where datname='${database}' and application_name='${name}' and ${predicate})`)==='t') return;
        await new Promise(resolve=>setTimeout(resolve,10));
      }
      assert.fail(`${name} did not reach ${predicate}`);
    }
    async function race(kind,cause){
      const item=participant(); let occupancy;
      if(kind==='move') occupancy=assign(item.part,room1);
      const suffix=String(sequence++).padStart(12,'0');
      const operation=`70000000-0000-0000-0000-${suffix}`;
      const firstCall=kind==='assign'
        ?`select public.assign_conference_accommodation('${device}','${conference}','${room1}','${item.part}',1,6,'base',null)`
        :`select public.move_conference_accommodation('${device}','${conference}','${occupancy.occupancyId}',1,'${room2}',1,6,'base',null)`;
      const lifecycle=cause==='apologized'
        ?`select public.set_conference_participation_status('${device}','${operation}','${item.part}',1,'apologized')`
        :`select platform_private.p5c_delete('${device}','${operation}','${item.part}',1)`;
      const first=queryAsync(`begin; set application_name='p5c_first_${suffix}'; ${firstCall}; select pg_sleep(2); commit`);
      await waitFor(`p5c_first_${suffix}`,"wait_event='PgSleep'");
      const second=queryAsync(`set application_name='p5c_second_${suffix}'; ${lifecycle}`);
      const settled=Promise.allSettled([first,second]);
      await waitFor(`p5c_second_${suffix}`,"wait_event_type='Lock'");
      const results=await settled;
      assert.equal(results.filter(result=>result.status==='fulfilled').length,2);
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${item.part}'`),'0');
      if(cause==='apologized') assert.equal(query(`select status from public.conference_participations where id='${item.part}'`),'apologized');
      else assert.equal(query(`select count(*) from public.conference_participations where id='${item.part}'`),'0');
    }
    await t.test('ASSIGN vs APOLOGIZE waits without deadlock and ends clean',()=>race('assign','apologized'));
    await t.test('MOVE vs APOLOGIZE waits without deadlock and ends clean',()=>race('move','apologized'));
    await t.test('ASSIGN vs DELETE waits without deadlock and ends clean',()=>race('assign','deleted'));
    await t.test('MOVE vs DELETE waits without deadlock and ends clean',()=>race('move','deleted'));
    await t.test('MOVE vs MOVE serializes and rejects the stale revision',async()=>{
      const item=participant(),occupancy=assign(item.part,room1),suffix=String(sequence++).padStart(12,'0');
      const first=queryAsync(`begin; set application_name='p5c_move_first_${suffix}'; select public.move_conference_accommodation('${device}','${conference}','${occupancy.occupancyId}',1,'${room2}',1,6,'base',null); select pg_sleep(2); commit`);
      await waitFor(`p5c_move_first_${suffix}`,"wait_event='PgSleep'");
      const second=queryAsync(`set application_name='p5c_move_second_${suffix}'; select public.move_conference_accommodation('${device}','${conference}','${occupancy.occupancyId}',1,'${room1}',1,6,'base',null)`);
      const settled=Promise.allSettled([first,second]);
      await waitFor(`p5c_move_second_${suffix}`,"wait_event_type='Lock'");
      const results=await settled;
      assert.equal(results[0].status,'fulfilled'); assert.equal(results[1].status,'rejected');
      assert.match(String(results[1].reason.stderr),/ACCOMMODATION_REVISION_CONFLICT/);
      assert.equal(query(`select jsonb_build_array(revision,room_id,participation_id) from public.conference_accommodation_occupancies where id='${occupancy.occupancyId}'`),`[2, "${room2}", "${item.part}"]`);
      assert.equal(query(`select count(*) from platform.audit_events where action='conference.accommodation.moved' and entity_id='${occupancy.occupancyId}'`),'1');
    });
    await t.test('REMOVE vs MOVE serializes deletion without orphan or incorrect audit',async()=>{
      const item=participant(),occupancy=assign(item.part,room1),suffix=String(sequence++).padStart(12,'0');
      const first=queryAsync(`begin; set application_name='p5c_remove_first_${suffix}'; select public.remove_conference_accommodation('${device}','${conference}','${occupancy.occupancyId}',1); select pg_sleep(2); commit`);
      await waitFor(`p5c_remove_first_${suffix}`,"wait_event='PgSleep'");
      const second=queryAsync(`set application_name='p5c_move_after_remove_${suffix}'; select public.move_conference_accommodation('${device}','${conference}','${occupancy.occupancyId}',1,'${room2}',1,6,'base',null)`);
      const settled=Promise.allSettled([first,second]);
      await waitFor(`p5c_move_after_remove_${suffix}`,"wait_event_type='Lock'");
      const results=await settled;
      assert.equal(results[0].status,'fulfilled'); assert.equal(results[1].status,'rejected');
      assert.match(String(results[1].reason.stderr),/ACCOMMODATION_OCCUPANCY_NOT_FOUND/);
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where id='${occupancy.occupancyId}'`),'0');
      assert.equal(query(`select status from public.conference_participations where id='${item.part}'`),'active');
      assert.equal(query(`select count(*) from platform.audit_events where entity_id='${occupancy.occupancyId}' and action='conference.accommodation.removed'`),'1');
      assert.equal(query(`select count(*) from platform.audit_events where entity_id='${occupancy.occupancyId}' and action in('conference.accommodation.moved','conference.accommodation.participation_cleanup')`),'0');
    });
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
  }
});
