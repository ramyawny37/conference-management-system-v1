'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const root=path.join(__dirname,'..');
const migration='supabase/migrations/20260929170000_canonical_conference_core_read_edge_foundation.sql';
const sql=fs.readFileSync(path.join(root,migration),'utf8');
const conferenceEdge=fs.readFileSync(path.join(root,'supabase/functions/conference-device-operation/index.ts'),'utf8');
const platformEdge=fs.readFileSync(path.join(root,'supabase/functions/platform-device-operation/index.ts'),'utf8');
const canonicalOperations=[
  'create_canonical_conference','mutate_conference_core','get_conference_core',
  'list_conference_participations','create_conference_participation',
  'set_conference_participation_status','delete_conference_participation',
  'get_conference_accommodation','create_accommodation_house',
  'update_accommodation_house','delete_accommodation_house',
  'create_accommodation_floor','update_accommodation_floor',
  'delete_accommodation_floor','create_accommodation_room',
  'update_accommodation_room','delete_accommodation_room',
  'assign_conference_accommodation','move_conference_accommodation',
  'remove_conference_accommodation'
];

test('P6B0 adds one exact-authority canonical read without stored derivatives',()=>{
  assert.match(sql,/create function public\.get_conference_core\(/);
  assert.match(sql,/conference\.access\.view/);
  assert.match(sql,/validated_phase1c_device_authorization/);
  assert.match(sql,/CONFERENCE_CORE_NOT_FOUND/);
  assert.match(sql,/conferences\.deleted_at is null/);
  assert.match(sql,/generate_series\(/);
  assert.doesNotMatch(sql,/add column|create table|conference_snapshots|conference_members/);
  assert.equal((sql.match(/create function public\.get_conference_core\(/g)||[]).length,1);
  assert.match(sql,/revoke all on function public\.get_conference_core\(uuid,uuid\)[\s\S]*from public,anon,authenticated,service_role/);
  assert.match(sql,/public\.get_conference_core\(p_actor_device_id/);
});

test('both existing Edge boundaries expose the exact canonical P3-P5 operation set',()=>{
  for(const operation of canonicalOperations){
    assert.ok(conferenceEdge.includes(`'${operation}'`),`conference Edge: ${operation}`);
    assert.ok(platformEdge.includes(`'${operation}'`),`platform Edge: ${operation}`);
  }
  assert.match(conferenceEdge,/execute_conference_device_operation/);
  assert.match(platformEdge,/execute_device_operation/);
  assert.doesNotMatch(conferenceEdge,/get_conference_core\s*[:=]\s*(?:async\s*)?function/);
  assert.doesNotMatch(platformEdge,/get_conference_core\s*[:=]\s*(?:async\s*)?function/);
});

const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(postgresAppBin,'psql'))?postgresAppBin:'';
const database=`conference_p6b0_${process.pid}_${Date.now()}`;
const validationHost=process.env.PGHOST;
const connection=validationHost?['-h',validationHost,'-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username]:['-h','/tmp','-p','5432','-U',os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
if(process.env.PGPASSWORD) env.PGPASSWORD=process.env.PGPASSWORD;
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function rejectsCall(call,pattern){assert.throws(call,error=>pattern.test(String(error.stderr)));}

test('disposable PostgreSQL proves read fields, authority, session and privileges',()=>{
  try{command('psql',['-X','-At','-d','postgres','-c','select 1']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  const actor='10000000-0000-0000-0000-000000000001';
  const device='20000000-0000-0000-0000-000000000001';
  const authorization='30000000-0000-0000-0000-000000000001';
  const organization='40000000-0000-0000-0000-000000000001';
  const conference='50000000-0000-0000-0000-000000000001';
  const other='50000000-0000-0000-0000-000000000002';
  const deleted='50000000-0000-0000-0000-000000000003';
  const roles=['anon','authenticated','service_role'];
  const created=[];
  command('createdb',[database]);
  try{
    for(const role of roles){if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}}
    query(`create schema platform; create schema platform_private;
      create table public.p6b0_context(actor uuid,device uuid,authorization_id uuid,granted_conference uuid,permission_ok boolean,device_ok boolean);
      insert into public.p6b0_context values('${actor}','${device}','${authorization}','${conference}',true,true);
      create table public.module_permission_catalog(permission_key text,module_key text,status text,allowed_scope_mode text,allowed_resource_type text);
      insert into public.module_permission_catalog values('conference.access.view','conference','active','resource','conference');
      create table public.conferences(id uuid primary key,organization_id uuid,name text,start_date date,end_date date,status text,completed_at timestamptz,revision bigint,created_at timestamptz,updated_at timestamptz,updated_by uuid,deleted_at timestamptz);
      insert into public.conferences values
        ('${conference}','${organization}','Completed','2026-10-01','2026-10-03','completed','2026-10-04',7,'2026-09-01','2026-10-04','${actor}',null),
        ('${other}','${organization}','Other','2026-11-01','2026-11-02','active',null,1,now(),now(),'${actor}',null),
        ('${deleted}','${organization}','Deleted','2026-12-01','2026-12-02','active',null,1,now(),now(),'${actor}',now());
      create function public.require_effective_module_permission(uuid,text,text,text,text) returns jsonb language plpgsql stable as \$\$ declare c public.p6b0_context%rowtype; begin select * into c from public.p6b0_context; if \$1<>c.device or \$2<>'conference' or \$3<>'conference.access.view' or \$4<>'conference' or \$5<>c.granted_conference::text or not c.permission_ok then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501'; end if; return jsonb_build_object('actorUserId',c.actor); end \$\$;
      create function platform_private.validated_phase1c_device_authorization(uuid,uuid) returns uuid language sql stable as \$\$ select case when device_ok and \$1=actor and \$2=device then authorization_id end from public.p6b0_context \$\$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language plpgsql immutable as \$\$ declare k text; begin foreach k in array \$2 loop if not \$1?k then raise exception 'MISSING_ARGUMENT' using errcode='22023'; end if; end loop; if exists(select 1 from jsonb_object_keys(\$1) x where not(x=any(\$2) or x=any(\$3))) then raise exception 'UNKNOWN_ARGUMENT' using errcode='22023'; end if; end \$\$;
      create function platform_private.route_canonical_conference_operation(p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_actor_device_id uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as \$\$ begin if p_operation='get_conference_accommodation' then return '{}'::jsonb; end if; raise exception 'CONFERENCE_OPERATION_NOT_ALLOWED' using errcode='42501'; end \$\$;
      revoke all on function platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb) from public,anon,authenticated,service_role;`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,migration)]);
    const dispatch=id=>JSON.parse(query(`select platform_private.route_canonical_conference_operation('${actor}',gen_random_uuid(),decode(repeat('00',32),'hex'),'${device}','get_conference_core',jsonb_build_object('p_conference_id','${id}'))`));
    const result=dispatch(conference);
    assert.equal(result.conferenceId,conference);
    assert.equal(result.organizationId,organization);
    assert.equal(result.status,'completed');
    assert.equal(result.revision,7);
    assert.equal(result.days,3);
    assert.equal(result.nights,2);
    assert.deepEqual(result.schedule,['2026-10-01','2026-10-02','2026-10-03']);
    rejectsCall(()=>dispatch(other),/MODULE_PERMISSION_REQUIRED/);
    query('update public.p6b0_context set permission_ok=false');
    rejectsCall(()=>dispatch(conference),/MODULE_PERMISSION_REQUIRED/);
    query('update public.p6b0_context set permission_ok=true,device_ok=false');
    rejectsCall(()=>dispatch(conference),/APPROVED_DEVICE_SESSION_REQUIRED/);
    query('update public.p6b0_context set device_ok=true');
    rejectsCall(()=>dispatch(deleted),/MODULE_PERMISSION_REQUIRED/);
    query(`update public.p6b0_context set granted_conference='${deleted}'`);
    rejectsCall(()=>dispatch(deleted),/CONFERENCE_CORE_NOT_FOUND/);
    query(`update public.p6b0_context set granted_conference='60000000-0000-0000-0000-000000000001'`);
    rejectsCall(()=>dispatch('60000000-0000-0000-0000-000000000001'),/CONFERENCE_CORE_NOT_FOUND/);
    const signature='public.get_conference_core(uuid,uuid)';
    for(const role of roles) assert.equal(query(`select has_function_privilege('${role}','${signature}','EXECUTE')`),'f');
    rejectsCall(()=>query(`set role authenticated; select public.get_conference_core('${device}','${conference}')`),/permission denied for function get_conference_core/i);
    assert.equal(query(`select count(*) from pg_proc where pronamespace='platform_private'::regnamespace and proname='route_canonical_conference_operation'`),'1');
    assert.equal(query(`select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='get_conference_core'`),'1');
  }finally{
    command('dropdb',['--if-exists',database]);
    for(const role of created) command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);
  }
});
