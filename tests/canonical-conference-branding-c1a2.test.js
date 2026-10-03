'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');
const root=path.join(__dirname,'..');
const migrationPath=path.join(root,'supabase/migrations/20261006120000_canonical_conference_branding_foundation.sql');
const sql=fs.readFileSync(migrationPath,'utf8');
const script=fs.readFileSync(path.join(root,'script.js'),'utf8');
const contract=fs.readFileSync(path.join(root,'js/supabase/platform-device-operation-contract.js'),'utf8');

test('C1A.2 source audit fixes the active Branding facts, defaults, and preparation contract',()=>{
  for(const fact of ['banner','service_logo','auto_colors','banner_position','card_theme','primary_color','secondary_color','text_color'])assert.match(sql,new RegExp(`\\b${fact}\\b`));
  assert.match(sql,/default false/);assert.match(sql,/default 'center'/);assert.match(sql,/default 'classic'/);assert.match(sql,/default '#6C3483'/);assert.match(sql,/default '#8E44AD'/);assert.match(sql,/default '#1A2A3A'/);
  assert.match(script,/maxWidth:isBanner\?1200:500/);assert.match(script,/maxHeight:isBanner\?600:500/);assert.match(script,/quality:isBanner\?\.72:\.75/);assert.match(script,/canvas\.width=900[\s\S]*canvas\.height=252/);
  assert.doesNotMatch(sql,/bannerPrepared|banner_prepared|bannerFit|banner_fit|fontFamily|font_family|\blogo\b|watermark|conference_snapshots|activityLog|saveAppData|\bsave\(/);
});

test('C1A.2 has one typed owner, shared ledger, protected operations, and no generic document authority',()=>{
  assert.equal((sql.match(/create table public\.conference_branding\(/g)||[]).length,1);
  assert.match(sql,/conference_id uuid primary key references public\.conferences\(id\) on delete cascade/);
  assert.match(sql,/conference_branding_mutation/);assert.doesNotMatch(sql,/create table[^;]*(operation|ledger|blob|attachment)/i);
  assert.doesNotMatch(sql,/branding jsonb|settings jsonb|payload jsonb[^)]*conference_branding/i);
  assert.match(contract,/get_conference_branding/);assert.match(contract,/mutate_conference_branding/);
  assert.match(sql,/'conference\.cards\.view'/);assert.match(sql,/'conference\.lifecycle\.manage'/);
});

test('C1A.2 validates only prepared JPEG Data URLs without inventing a byte limit',()=>{
  assert.match(sql,/\^data:image\/jpeg;base64,/);assert.match(sql,/decode\(payload,'base64'\)/);assert.match(sql,/get_byte\(decoded,0\)=255[\s\S]*get_byte\(decoded,1\)=216[\s\S]*get_byte\(decoded,2\)=255/);
  assert.doesNotMatch(sql,/octet_length|byte_length|max_bytes|maxBytes/);
});

const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_c1a2_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&!/(?:^DIRECT_URL$|(?:DATABASE|DB|POSTGRES|SUPABASE).*URL)/i.test(key)));
function command(name,args){return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe',env}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function rejects(statement,pattern){assert.throws(()=>query(statement),error=>pattern.test(String(error.stderr)),String(pattern));}

test('C1A.2 disposable PostgreSQL proves complete Branding behavior and boundaries',()=>{
  const actor='10000000-0000-4000-8000-000000000001',denied='10000000-0000-4000-8000-000000000002';
  const device='20000000-0000-4000-8000-000000000001',wrong='20000000-0000-4000-8000-000000000002',revoked='20000000-0000-4000-8000-000000000003';
  const authz='30000000-0000-4000-8000-000000000001',conference='40000000-0000-4000-8000-000000000001';
  const jpeg='data:image/jpeg;base64,/9j/2Q==';let sequence=0;const op=()=>`50000000-0000-4000-8000-${String(++sequence).padStart(12,'0')}`;
  const roles=['anon','authenticated','service_role'],created=[];
  const context=(user,actorDevice)=>`set local platform.phase1c_context='${JSON.stringify({purpose:'PLATFORM_DEVICE_SESSION_DISPATCH',user_id:user,device_id:actorDevice})}';`;
  const mutate=(user,actorDevice,operation,action,revision,payload)=>`begin;${context(user,actorDevice)}select public.mutate_conference_branding('${actorDevice}','${operation}','${conference}','${action}',${revision},'${JSON.stringify(payload).replaceAll("'","''")}'::jsonb);commit;`;
  try{command('psql',['-X','-At','-d','postgres','-c','select 1']);}catch{assert.fail('isolated/local PostgreSQL is required; do not silently skip');}
  command('createdb',[database]);
  try{
    for(const role of roles)if(query(`select exists(select 1 from pg_roles where rolname='${role}')`)==='f'){query(`create role ${role} nologin`);created.push(role);}
    query(`create extension pgcrypto;create schema platform;create schema platform_private;
      create table platform.profiles(user_id uuid primary key,account_status text);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid,device_id uuid,status text,revoked_at timestamptz);
      create table platform.audit_events(id uuid primary key default gen_random_uuid(),actor_user_id uuid,actor_device_authorization_id uuid,domain text,module text,action text,entity_type text,entity_id uuid,scope_type text,old_values jsonb,new_values jsonb,metadata jsonb,operation_id uuid,source text);
      create table public.module_permission_catalog(permission_key text primary key,status text);
      insert into public.module_permission_catalog values('conference.cards.view','active'),('conference.lifecycle.manage','active');
      create table public.conferences(id uuid primary key,status text,deleted_at timestamptz);
      create table public.conference_participation_operations(actor_user_id uuid references platform.profiles(user_id),operation_id uuid,operation text constraint conference_participation_operations_operation_check check(operation in('create','create_with_person','set_status','set_guardian','delete','transport_vehicle_create','transport_vehicle_update','transport_vehicle_delete','transport_assignment_set','transport_assignment_remove','restaurant_mutation','accommodation_pricing_mutation','air_conditioning_mutation','finance_mutation','conference_core_mutation')),request jsonb,result jsonb,created_at timestamptz,primary key(actor_user_id,operation_id));
      create table public.test_access(user_id uuid primary key,can_view boolean,can_manage boolean,returned_actor uuid);
      create function platform_private.validated_phase1c_device_authorization(a uuid,d uuid) returns uuid language sql stable as $$select id from platform.user_device_authorizations where user_id=a and device_id=d and status='approved' and revoked_at is null$$;
      create function public.require_effective_module_permission(d uuid,m text,p text,s text,r text) returns jsonb language plpgsql stable as $$declare c jsonb;a uuid;x public.test_access%rowtype;begin c:=nullif(current_setting('platform.phase1c_context',true),'')::jsonb;a:=(c->>'user_id')::uuid;select * into x from public.test_access where user_id=a;if not found or (p='conference.cards.view' and not x.can_view) or (p='conference.lifecycle.manage' and not x.can_manage) then raise exception 'MODULE_PERMISSION_REQUIRED' using errcode='42501';end if;return jsonb_build_object('actorUserId',coalesce(x.returned_actor,a),'authoritySource','module_grant','grantId','60000000-0000-4000-8000-000000000001');end$$;
      create function platform_private.require_exact_jsonb_keys(p jsonb,required text[],optional text[] default '{}') returns void language plpgsql as $$declare actual text[];begin select coalesce(array_agg(key order by key),'{}') into actual from jsonb_object_keys(p) key;if actual<>coalesce((select array_agg(x order by x) from unnest(required||optional) x),'{}') then raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023';end if;end$$;
      create function platform_private.route_canonical_conference_operation(a uuid,b uuid,c bytea,d uuid,p_operation text,p_args jsonb) returns jsonb language plpgsql as $$begin if p_operation='get_conference_finance' then return '{}'::jsonb;end if;return '{}'::jsonb;end$$;
      insert into platform.profiles values('${actor}','approved'),('${denied}','approved');insert into public.test_access values('${actor}',true,true,null),('${denied}',false,false,null);
      insert into platform.user_device_authorizations values('${authz}','${actor}','${device}','approved',null),(gen_random_uuid(),'${actor}','${wrong}','approved',null),(gen_random_uuid(),'${actor}','${revoked}','revoked',now()),(gen_random_uuid(),'${denied}','${wrong}','approved',null);
      insert into public.conferences values('${conference}','active',null);`);
    command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migrationPath]);
    assert.equal(query(`select count(*) from public.conference_branding where conference_id='${conference}'`),'1');
    assert.equal(query(`select banner||':'||service_logo||':'||auto_colors||':'||banner_position||':'||card_theme||':'||primary_color||':'||secondary_color||':'||text_color||':'||revision from public.conference_branding where conference_id='${conference}'`),`::false:center:classic:#6C3483:#8E44AD:#1A2A3A:1`);
    assert.match(query(`begin;${context(actor,device)}select public.get_conference_branding('${device}','${conference}');commit;`),/"cardTheme": "classic"/);
    for(const role of roles){assert.equal(query(`select has_table_privilege('${role}','public.conference_branding','UPDATE')`),'f');assert.equal(query(`select has_function_privilege('${role}','public.mutate_conference_branding(uuid,uuid,uuid,text,bigint,jsonb)','EXECUTE')`),'f');}
    rejects(`set role authenticated;update public.conference_branding set card_theme='modern-banner'`,/permission denied/);rejects(`set role authenticated;select public.get_conference_branding('${device}','${conference}')`,/permission denied/);
    rejects(mutate(denied,wrong,op(),'SETTINGS_UPDATE',1,{autoColors:false,bannerPosition:'center',cardTheme:'classic',primaryColor:'#111111',secondaryColor:'#222222',textColor:'#333333'}),/MODULE_PERMISSION_REQUIRED/);
    rejects(`select public.get_conference_branding('${device}','${conference}')`,/APPROVED_DEVICE_SESSION_REQUIRED/);rejects(`begin;${context(actor,device)}select public.get_conference_branding('${wrong}','${conference}');commit;`,/APPROVED_DEVICE_SESSION_REQUIRED/);rejects(`begin;${context(actor,revoked)}select public.get_conference_branding('${revoked}','${conference}');commit;`,/APPROVED_DEVICE_SESSION_REQUIRED/);
    query(`update public.test_access set returned_actor='${denied}' where user_id='${actor}'`);rejects(mutate(actor,device,op(),'BANNER_SET',1,{image:jpeg}),/ACTOR_DEVICE_OVERRIDE_DENIED/);query(`update public.test_access set returned_actor=null where user_id='${actor}'`);
    const settingsOp=op(),settings={autoColors:true,bannerPosition:'top',cardTheme:'modern-banner',primaryColor:'#112233',secondaryColor:'#445566',textColor:'#778899'};query(mutate(actor,device,settingsOp,'SETTINGS_UPDATE',1,settings));assert.equal(query(`select auto_colors||':'||banner_position||':'||card_theme||':'||revision from public.conference_branding where conference_id='${conference}'`),'true:top:modern-banner:2');
    const bannerSet=op(),first=query(mutate(actor,device,bannerSet,'BANNER_SET',2,{image:jpeg}));assert.match(first,/data:image\/jpeg;base64/);assert.equal(query(mutate(actor,device,bannerSet,'BANNER_SET',2,{image:jpeg})),first);assert.equal(query(`select revision from public.conference_branding where conference_id='${conference}'`),'3');assert.equal(query(`select count(*) from platform.audit_events where operation_id='${bannerSet}'`),'1');assert.equal(query(`select actor_user_id from platform.audit_events where operation_id='${bannerSet}'`),actor);
    rejects(mutate(actor,device,bannerSet,'BANNER_REMOVE',3,{}),/CONFERENCE_PARTICIPATION_OPERATION_MISMATCH/);
    const ledgerBefore=query(`select count(*) from public.conference_participation_operations`),auditBefore=query(`select count(*) from platform.audit_events`);rejects(mutate(actor,device,op(),'BANNER_REMOVE',2,{}),/CONFERENCE_BRANDING_REVISION_CONFLICT/);assert.equal(query(`select revision from public.conference_branding where conference_id='${conference}'`),'3');assert.equal(query(`select count(*) from public.conference_participation_operations`),ledgerBefore);assert.equal(query(`select count(*) from platform.audit_events`),auditBefore);
    rejects(mutate(actor,device,op(),'BANNER_SET',3,{image:'data:image/png;base64,/9j/2Q=='}),/CONFERENCE_BRANDING_JPEG_DATA_URL_INVALID/);rejects(mutate(actor,device,op(),'BANNER_SET',3,{image:'data:image/jpeg;base64,@@@@'}),/CONFERENCE_BRANDING_JPEG_DATA_URL_INVALID/);rejects(mutate(actor,device,op(),'BANNER_SET',3,{image:jpeg,extra:true}),/PLATFORM_OPERATION_ARGUMENT_INVALID/);
    query(mutate(actor,device,op(),'BANNER_SET',3,{image:'data:image/jpeg;base64,/9j/4A=='}));query(mutate(actor,device,op(),'BANNER_REMOVE',4,{}));assert.equal(query(`select banner from public.conference_branding where conference_id='${conference}'`),'');
    query(mutate(actor,device,op(),'SERVICE_LOGO_SET',5,{image:jpeg}));query(mutate(actor,device,op(),'SERVICE_LOGO_SET',6,{image:'data:image/jpeg;base64,/9j/4Q=='}));query(mutate(actor,device,op(),'SERVICE_LOGO_REMOVE',7,{}));assert.equal(query(`select service_logo||':'||revision from public.conference_branding where conference_id='${conference}'`),':8');
    const failOp=op();query(`create function platform.fail_branding_audit() returns trigger language plpgsql as $$begin if new.operation_id='${failOp}' then raise exception 'INJECTED_BRANDING_AUDIT_FAILURE';end if;return new;end$$;create trigger fail_branding_audit before insert on platform.audit_events for each row execute function platform.fail_branding_audit()`);rejects(mutate(actor,device,failOp,'BANNER_SET',8,{image:jpeg}),/INJECTED_BRANDING_AUDIT_FAILURE/);assert.equal(query(`select banner||':'||revision from public.conference_branding where conference_id='${conference}'`),':8');assert.equal(query(`select count(*) from public.conference_participation_operations where operation_id='${failOp}'`),'0');assert.equal(query(`select count(*) from platform.audit_events where operation_id='${failOp}'`),'0');
  }finally{command('dropdb',['--if-exists',database]);for(const role of created)command('psql',['-X','-v','ON_ERROR_STOP=1','-d','postgres','-c',`drop role ${role}`]);}
});
