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
const migrations=[
  'supabase/migrations/20260928170000_canonical_conference_accommodation_data_foundation.sql',
  'supabase/migrations/20260929120000_canonical_conference_accommodation_protected_mutations.sql',
  'supabase/migrations/20260929160000_canonical_conference_participation_accommodation_propagation.sql',
  'supabase/migrations/20261002120000_canonical_conference_guardian_participation_relation.sql'
];
const sql=fs.readFileSync(path.join(root,migrations[3]),'utf8');
const integration=fs.readFileSync(path.join(root,'js/platform-integration.js'),'utf8');
const edges=['platform','conference'].map(name=>fs.readFileSync(path.join(root,`supabase/functions/${name}-device-operation/index.ts`),'utf8'));

test('P6E-B1 is a single canonical relation integrated through existing boundaries',()=>{
  assert.match(sql,/add column guardian_participation_id uuid null/);
  assert.match(sql,/foreign key\(conference_id,guardian_participation_id\)[\s\S]*on delete restrict/);
  assert.match(sql,/conference_participation_guardian_one_level/);
  assert.match(sql,/cleanup_conference_accommodation_for_participation/);
  assert.match(sql,/'deletedParticipationIds'/);
  assert.doesNotMatch(sql,/peopleDb|conference_snapshots|room\.guests|room\.children|create table[^;]*guardian/is);
  assert.match(integration,/setConferenceParticipationGuardian:setConferenceParticipationGuardian/);
  assert.match(integration,/deletedParticipationIds/);
  for(const source of edges) assert.match(source,/set_conference_participation_guardian/);
});

const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_p6e_b1_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
async function queryAsync(statement){return (await execFileAsync(pgBin?path.join(pgBin,'psql'):'psql',[...connection,'-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement],{encoding:'utf8',env})).stdout.trim();}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves strict one-level integrity, cascade, rollback and replay',async(t)=>{
  const actor='10000000-0000-0000-0000-000000000001',device='11000000-0000-0000-0000-000000000001',authz='12000000-0000-0000-0000-000000000001';
  const conference='20000000-0000-0000-0000-000000000001',otherConference='20000000-0000-0000-0000-000000000002';
  const roles=['anon','authenticated','service_role'],created=[];
  command('createdb',[database]);
  try{
    for(const role of roles) if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}
    query(`create schema extensions; create extension pgcrypto with schema extensions; create schema platform; create schema platform_private;
      create table platform.profiles(user_id uuid primary key);
      create table platform.people(id uuid primary key,full_name text,phone text,gender text,date_of_birth date,church text);
      create table public.conferences(id uuid primary key,start_date date,end_date date,status text,deleted_at timestamptz);
      create table public.conference_participations(id uuid primary key default extensions.gen_random_uuid(),conference_id uuid not null references public.conferences(id) on delete restrict,person_id uuid not null references platform.people(id) on delete restrict,status text not null default 'active',revision bigint not null default 1,created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),created_by uuid not null references platform.profiles(user_id),updated_by uuid not null references platform.profiles(user_id),unique(conference_id,person_id));
      create table public.conference_participation_operations(actor_user_id uuid not null references platform.profiles(user_id),operation_id uuid not null,operation text not null constraint conference_participation_operations_operation_check check(operation in('create','create_with_person','set_status','delete')),request jsonb not null,result jsonb not null,created_at timestamptz not null default statement_timestamp(),primary key(actor_user_id,operation_id));
      alter table public.conference_participations enable row level security; alter table public.conference_participations force row level security;
      alter table public.conference_participation_operations enable row level security; alter table public.conference_participation_operations force row level security;
      revoke all on public.conference_participations,public.conference_participation_operations from public,anon,authenticated,service_role;
      create table public.module_permission_catalog(permission_key text primary key,module_key text,status text,allowed_scope_mode text,allowed_resource_type text);
      create table public.p6e_context(people_manage boolean,enabled boolean,conference_id uuid);
      insert into public.p6e_context values(true,true,'${conference}');
      create table platform.audit_events(id uuid primary key default extensions.gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,subject_user_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,scope_id uuid,old_values jsonb,new_values jsonb,metadata jsonb,request_id uuid,operation_id uuid,source text,occurred_at timestamptz default now());
      insert into public.module_permission_catalog values
        ('conference.people.view','conference','active','resource','conference'),('conference.people.manage','conference','active','resource','conference'),
        ('conference.accommodation.view','conference','active','resource','conference'),('conference.accommodation.manage','conference','active','resource','conference');
      insert into platform.profiles values('${actor}');
      insert into public.conferences values('${conference}','2027-01-01','2027-01-05','active',null),('${otherConference}','2027-01-01','2027-01-05','active',null);
      create function public.require_effective_module_permission(uuid,text,text,text,text) returns jsonb language plpgsql stable as \$\$ declare c public.p6e_context%rowtype; begin select * into c from public.p6e_context; if not c.enabled or \$1<>'${device}' or \$5<>c.conference_id::text or (\$3='conference.people.manage' and not c.people_manage) then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if; return jsonb_build_object('actorUserId','${actor}','authoritySource','resource_grant','grantId','13000000-0000-0000-0000-000000000001'); end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql stable as \$\$ select case when \$1='${actor}' and \$2='${device}' and (select enabled from public.p6e_context) then '${authz}'::uuid end \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language sql immutable as \$\$ select \$\$;
      create function platform_private.require_conference_participation_context(uuid,uuid,text,boolean) returns jsonb language plpgsql stable security definer set search_path='' as \$\$ declare context jsonb; state text; begin context:=public.require_effective_module_permission(\$1,'conference',\$3,'conference',\$2::text); select status into state from public.conferences where id=\$2 and deleted_at is null; if state is null then raise exception 'CONFERENCE_NOT_FOUND'; end if; if \$4 and state<>'active' then raise exception 'COMPLETED_CONFERENCE_IMMUTABLE'; end if; return context; end \$\$;
      create function public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.mutate_conference_core(uuid,uuid,bigint,text,date,date,text) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.list_conference_participations(uuid,uuid) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.create_conference_participation(uuid,uuid,uuid,uuid) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.set_conference_participation_status(uuid,uuid,uuid,bigint,text) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function public.delete_conference_participation(uuid,uuid,uuid,bigint) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;
      create function platform_private.route_canonical_conference_operation(p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_actor_device_id uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as \$\$ begin if p_operation='get_conference_core' then return '{}'::jsonb; elsif p_operation='list_conference_participations' then return public.list_conference_participations(p_actor_device_id,(p_args->>'p_conference_id')::uuid); end if; return '{}'::jsonb; end \$\$;`);
    for(const migration of migrations) command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    query(`create function platform_private.p6e_delete(uuid,uuid,uuid,bigint) returns jsonb language plpgsql security definer set search_path='' as \$\$ begin perform set_config('platform.phase1c_context',jsonb_build_object('purpose','PLATFORM_DEVICE_SESSION_DISPATCH','user_id','${actor}','device_id',\$1)::text,true); return public.delete_conference_participation(\$1,\$2,\$3,\$4); end \$\$; revoke all on function platform_private.p6e_delete(uuid,uuid,uuid,bigint) from public,anon,authenticated,service_role;`);
    let sequence=1;
    function participant(conf=conference,status='active'){
      const suffix=String(sequence++).padStart(12,'0'),person=`30000000-0000-0000-0000-${suffix}`,part=`40000000-0000-0000-0000-${suffix}`;
      query(`insert into platform.people values('${person}','Person ${suffix}',null,null,null,null); insert into public.conference_participations(id,conference_id,person_id,status,created_by,updated_by) values('${part}','${conf}','${person}','${status}','${actor}','${actor}')`); return {person,part};
    }
    function operation(prefix='50'){return `${prefix}000000-0000-0000-0000-${String(sequence++).padStart(12,'0')}`;}
    function guardian(child,revision,parent,op=operation()){return JSON.parse(query(`select public.set_conference_participation_guardian('${device}','${op}','${child}',${revision},${parent?`'${parent}'`:'null'})`));}
    function deletion(part,revision,op=operation('60')){return JSON.parse(query(`select platform_private.p6e_delete('${device}','${op}','${part}',${revision})`));}
    const mutate=(op,args)=>JSON.parse(query(`select public.mutate_conference_accommodation_structure('${device}','${op}',${args})`));
    const house=mutate('create_house',`jsonb_build_object('p_conference_id','${conference}','p_name','H','p_description',null,'p_position',0)`);
    const floor=mutate('create_floor',`jsonb_build_object('p_conference_id','${conference}','p_house_id','${house.houseId}','p_name','F','p_position',0)`);
    const room=mutate('create_room',`jsonb_build_object('p_conference_id','${conference}','p_floor_id','${floor.floorId}','p_room_number','101','p_base_capacity',50,'p_extra_bed_capacity',0,'p_notes',null,'p_is_closed',false,'p_closed_day',null,'p_position',0)`).roomId;
    const assign=part=>JSON.parse(query(`select public.assign_conference_accommodation('${device}','${conference}','${room}','${part}',1,6,'base',null)`));

    await t.test('set, clear, change, projection, status preservation and scoped rejection',()=>{
      const child=participant(),first=participant(conference,'apologized'),second=participant(),outsider=participant(otherConference);
      let result=guardian(child.part,1,first.part); assert.equal(result.guardianParticipationId,first.part); assert.equal(result.guardianParticipationStatus,'apologized');
      let listed=JSON.parse(query(`select public.list_conference_participations('${device}','${conference}')`));
      assert.equal(listed.items.find(item=>item.participationId===child.part).guardianFullName,`Person ${first.person.slice(-12)}`);
      result=guardian(child.part,2,null); assert.equal(result.guardianParticipationId,null);
      result=guardian(child.part,3,second.part); assert.equal(result.guardianParticipationId,second.part);
      rejects(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${child.part}',4,'${child.part}')`,/CONFERENCE_GUARDIAN_SELF_REFERENCE/);
      rejects(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${child.part}',4,'${outsider.part}')`,/CONFERENCE_GUARDIAN_SAME_CONFERENCE_REQUIRED/);
      const occupancy=assign(child.part),accommodation=JSON.parse(query(`select public.get_conference_accommodation('${device}','${conference}')`));
      const projected=accommodation.houses[0].floors[0].rooms[0].occupancies.find(item=>item.occupancyId===occupancy.occupancyId);
      assert.equal(projected.guardianParticipationId,second.part); assert.equal(projected.guardianParticipationStatus,'active');
      const statusOp=operation('51'); query(`select public.set_conference_participation_status('${device}','${statusOp}','${child.part}',4,'apologized')`);
      assert.equal(query(`select guardian_participation_id from public.conference_participations where id='${child.part}'`),second.part);
      query(`select public.set_conference_participation_status('${device}',extensions.gen_random_uuid(),'${child.part}',5,'active')`);
      query(`select public.set_conference_participation_status('${device}',extensions.gen_random_uuid(),'${second.part}',1,'apologized')`);
      query(`select public.set_conference_participation_status('${device}',extensions.gen_random_uuid(),'${second.part}',2,'active')`);
      assert.equal(query(`select guardian_participation_id from public.conference_participations where id='${child.part}'`),second.part);
    });

    await t.test('both chain directions and cycles reject',()=>{
      const a=participant(),b=participant(),c=participant(); guardian(b.part,1,a.part);
      rejects(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${a.part}',1,'${c.part}')`,/CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED/);
      rejects(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${c.part}',1,'${b.part}')`,/CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED/);
      rejects(`update public.conference_participations set guardian_participation_id='${b.part}' where id='${a.part}'`,/CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED/);
    });

    await t.test('simultaneous opposite assignments serialize and cannot form a chain or cycle',async()=>{
      const a=participant(),b=participant(),c=participant();
      const first=queryAsync(`begin; select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${a.part}',1,'${b.part}'); select pg_sleep(1); commit`);
      await new Promise(resolve=>setTimeout(resolve,100));
      const results=await Promise.allSettled([first,queryAsync(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${b.part}',1,'${c.part}')`)]);
      assert.equal(results.filter(value=>value.status==='fulfilled').length,1);
      assert.match(String(results.find(value=>value.status==='rejected').reason.stderr),/CONFERENCE_GUARDIAN_ONE_LEVEL_REQUIRED/);
      assert.equal(query(`select count(*) from public.conference_participations p where p.guardian_participation_id is not null and exists(select 1 from public.conference_participations c where c.guardian_participation_id=p.id)`),'0');
      const x=participant(),y=participant();
      const cycle=await Promise.allSettled([
        queryAsync(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${x.part}',1,'${y.part}')`),
        queryAsync(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${y.part}',1,'${x.part}')`)
      ]);
      assert.equal(cycle.filter(value=>value.status==='fulfilled').length,1); assert.equal(cycle.filter(value=>value.status==='rejected').length,1);
    });

    await t.test('child delete and guardian cascade clean Accommodation, preserve Persons, audit and replay exactly once',()=>{
      const guardianRow=participant(),child1=participant(),child2=participant(); guardian(child1.part,1,guardianRow.part); guardian(child2.part,1,guardianRow.part);
      for(const item of [guardianRow,child1,child2]) assign(item.part);
      const peopleBefore=query('select count(*) from platform.people'),op=operation('61');
      const result=deletion(guardianRow.part,1,op); assert.equal(result.deletedParticipationIds.length,3);
      assert.equal(query(`select count(*) from public.conference_participations where id in('${guardianRow.part}','${child1.part}','${child2.part}')`),'0');
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id in('${guardianRow.part}','${child1.part}','${child2.part}')`),'0');
      assert.equal(query('select count(*) from platform.people'),peopleBefore);
      assert.equal(query(`select count(*) from platform.audit_events where operation_id='${op}' and action='conference.participation.deleted'`),'3');
      assert.equal(query(`select count(*) from platform.audit_events where operation_id='${op}' and action='conference.accommodation.participation_cleanup'`),'3');
      assert.deepEqual(deletion(guardianRow.part,1,op),result);
      assert.equal(query(`select count(*) from platform.audit_events where operation_id='${op}'`),'6');
      const parent=participant(),child=participant(); guardian(child.part,1,parent.part); assign(child.part); deletion(child.part,2);
      assert.equal(query(`select count(*) from public.conference_participations where id='${parent.part}'`),'1');
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id='${child.part}'`),'0');
      assert.equal(query(`select count(*) from platform.people where id in('${parent.person}','${child.person}')`),'2');
      const ordinary=participant(); deletion(ordinary.part,1); assert.equal(query(`select count(*) from public.conference_participations where id='${ordinary.part}'`),'0');
    });

    await t.test('revision conflict and injected failure leave all Participation and Accommodation state intact',()=>{
      const parent=participant(),child=participant(); guardian(child.part,1,parent.part); assign(parent.part); assign(child.part);
      rejects(`select platform_private.p6e_delete('${device}',extensions.gen_random_uuid(),'${parent.part}',2)`,/CONFERENCE_PARTICIPATION_REVISION_CONFLICT/);
      assert.equal(query(`select count(*) from public.conference_participations where id in('${parent.part}','${child.part}')`),'2');
      query(`create function public.p6e_fail_delete_audit() returns trigger language plpgsql as \$\$ begin if new.action='conference.participation.deleted' then raise exception 'P6E_INJECTED_FAILURE'; end if; return new; end \$\$; create trigger p6e_fail_delete_audit before insert on platform.audit_events for each row execute function public.p6e_fail_delete_audit()`);
      rejects(`select platform_private.p6e_delete('${device}',extensions.gen_random_uuid(),'${parent.part}',1)`,/P6E_INJECTED_FAILURE/);
      assert.equal(query(`select count(*) from public.conference_participations where id in('${parent.part}','${child.part}')`),'2');
      assert.equal(query(`select count(*) from public.conference_accommodation_occupancies where participation_id in('${parent.part}','${child.part}')`),'2');
      query('drop trigger p6e_fail_delete_audit on platform.audit_events');
    });

    query('update public.p6e_context set people_manage=false');
    const deniedChild=participant(),deniedGuardian=participant();
    rejects(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${deniedChild.part}',1,'${deniedGuardian.part}')`,/MODULE_PERMISSION_REQUIRED/);
    query(`update public.p6e_context set people_manage=true,conference_id='${otherConference}'`);
    rejects(`select public.set_conference_participation_guardian('${device}',extensions.gen_random_uuid(),'${deniedChild.part}',1,'${deniedGuardian.part}')`,/MODULE_PERMISSION_REQUIRED/);
    for(const role of roles){
      assert.equal(query(`select has_table_privilege('${role}','public.conference_participations','SELECT,INSERT,UPDATE,DELETE')`),'f');
      assert.equal(query(`select has_function_privilege('${role}','public.set_conference_participation_guardian(uuid,uuid,uuid,bigint,uuid)','EXECUTE')`),'f');
    }
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
  }
});
