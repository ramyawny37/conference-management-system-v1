'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {execFileSync}=require('node:child_process');
const test=require('node:test');
const root=path.join(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const migration='supabase/migrations/20260927180000_conference_platform_permission_foundation.sql';
const sql=read(migration);
const mapping=JSON.parse(read('tests/fixtures/unified-conference-permission-foundation.json'));
const foundation=read('supabase/migrations/20260829120000_module_authorization_foundation.sql');
const catalog=read('supabase/migrations/20260829130000_module_permission_catalog_and_grant_adapter.sql');
const effective=read('supabase/migrations/20260907140000_module_access_delegation_enforcement.sql');
const sandbox={window:{}};
vm.runInNewContext(read('js/sync/conference-permission-contract.js'),sandbox);
const legacy=sandbox.window.ConferencePermissionContract;
const keys=mapping.permissions.map(p=>p.key);

function functionSql(source,name){
  const value=source.match(new RegExp('create(?: or replace)? function public\\.'+name+'\\([\\s\\S]*?end;\\s*\\$\\$;','i'));
  assert.ok(value,name); return value[0];
}
function tableSql(source,name){
  const value=source.match(new RegExp('create table public\\.'+name+' \\([\\s\\S]*?\\n\\);','i'));
  assert.ok(value,name);return value[0];
}

test('one existing module; catalog-only migration introduces no runtime or authorization storage',()=>{
  assert.match(read('supabase/migrations/20260830120000_integrated_platform_module_registration.sql'),/\('conference', 'Conference Management', 'active'\)/);
  assert.match(sql,/from public\.platform_modules where module_key='conference' and status='active'/);
  const executable=sql.replace(/--[^\n]*/g,'');
  const statements=executable.replace(/'(?:''|[^'])*'/g,"''");
  assert.doesNotMatch(statements,/create\s+(?:or replace\s+)?(?:function|table|schema|policy|trigger)|alter\s|delete\s|update\s|grant\s|revoke\s/i);
  assert.deepEqual([...executable.matchAll(/insert into ([\w.]+)/gi)].map(m=>m[1]),['public.module_permission_catalog']);
  assert.doesNotMatch(executable,/organization|conference_members|reservations\.|warehouse\.|snapshot|locks|audit_events/i);
  assert.equal(legacy.enforcementEnabled,false);
  assert.equal(new Set(keys).size,29);
});

test('catalog keys and scope modes follow the existing Platform schema',()=>{
  for(const p of mapping.permissions){
    assert.match(p.key,/^conference\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/);
    assert.equal((sql.match(new RegExp("'"+p.key.replaceAll('.','\\.')+"'",'g'))||[]).length,1);
    assert.ok(p.label.length<=160&&p.description.length<=1000);
    assert.equal(p.scope,p.key==='conference.lifecycle.create'?'module':'resource');
    assert.equal(p.resourceType,p.scope==='resource'?'conference':null);
  }
  assert.match(sql,/CONFERENCE_PERMISSION_CATALOG_CONFLICT/);
  assert.match(sql,/on conflict \(permission_key\) do nothing/);
  assert.equal(mapping.grantTarget.table,'public.module_permission_grants');
  assert.equal(mapping.grantTarget.resource_id,'public.conferences.id::text');
  assert.ok(!keys.some(k=>/snapshot|lock|wildcard/.test(k)));
});

for(const role of legacy.roles){
  test(role+' has a migration/bootstrap mapping limited to verified Conference scope',()=>{
    const expected=[...legacy.roleBundles[role].conference];
    for(const [section,actions] of Object.entries(legacy.roleBundles[role].sections)){
      if(!mapping.deferredLegacySections.includes(section))expected.push(...actions.map(a=>section+'.'+a));
    }
    const permissions=mapping.rolePermissions[role];
    const mapped=mapping.permissions.filter(p=>permissions.includes(p.key));
    assert.deepEqual(mapped.flatMap(p=>p.legacy).sort(),expected.sort());
    assert.ok(mapped.every(p=>p.scope==='resource'&&p.resourceType==='conference'));
    assert.ok(!permissions.includes('module.manage'));
    assert.ok(!permissions.includes('conference.lifecycle.create'));
    assert.equal(permissions.includes('conference.members.manage'),role==='owner');
    assert.equal(permissions.includes('conference.sync.write'),['owner','manager'].includes(role));
    if(role.endsWith('viewer'))assert.ok(mapped.every(p=>p.sensitive===false));
    if(role==='accommodation_viewer')assert.deepEqual(permissions,['conference.access.view','conference.members.view','conference.accommodation.view']);
    if(role==='transport_viewer')assert.deepEqual(permissions,['conference.access.view','conference.members.view','conference.transport.view']);
  });
}

test('mapping distinguishes enforced backend authority from the descriptive section contract',()=>{
  const members=read('supabase/migrations/20260729_4_0_0_conference_membership.sql');
  assert.match(members,/'canManageMembers', membership.role = 'owner'/);
  for(const name of ['canSync','canResolveConflicts','canAcquireLock']){
    assert.ok(members.includes("'"+name+"', membership.role in ('owner', 'manager')"));
  }
  assert.match(members,/list_conference_members[\s\S]*is_conference_member/);
  assert.match(read('supabase/migrations/20260816_6_12_0_conference_section_lock_device_guard.sql'),/actor_role not in \('owner','manager'\)/);
  assert.match(read('supabase/migrations/20260815_6_11_0_launch_membership_integrity.sql'),/SECTION_VIEWER_ASSIGNMENT_DISABLED/);
  assert.match(mapping.lockPolicy,/Concurrency precondition/);
});

const pgBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const psql=path.join(pgBin,'psql');
const database=`conference_u2b_${process.pid}_${Date.now()}`;
const actor='10000000-0000-0000-0000-000000000001';
const resource='20000000-0000-0000-0000-000000000001';
const other='20000000-0000-0000-0000-000000000002';
function command(name,args){return execFileSync(path.join(pgBin,name),args,{encoding:'utf8',stdio:'pipe',env:{...Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG'))),PGHOST:'/tmp',PGPORT:'5432',PGDATABASE:database}}).trim();}
function query(statement){return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',statement]);}
function apply(file){return command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',path.join(root,file)]);}

test('isolated PostgreSQL uses actual catalog/grant schema and actual canonical permission resolvers',
  {skip:!fs.existsSync(psql)},()=>{
  command('createdb',[database]);
  try{
    // Only the outer identity/device admission is a fixture; no browser, live DB,
    // or alternative permission resolver is involved in this isolated test.
    query(`create schema auth; create schema platform;
      create table auth.users(id uuid primary key);
      create table public.user_device_authorizations(user_id uuid,device_id uuid,primary key(user_id,device_id));
      create table platform.user_device_authorizations(user_id uuid,device_id uuid,primary key(user_id,device_id));
      create function public.require_current_approved_device(uuid) returns uuid language plpgsql as $$
      begin if $1 is distinct from '${actor}'::uuid then raise exception 'DEVICE_DENIED' using errcode='42501'; end if; return $1; end $$;
      create function public.is_system_owner(uuid) returns boolean language sql as $$ select false $$;
      ${tableSql(foundation,'platform_modules')}
      ${tableSql(foundation,'module_permission_grants')}
      ${tableSql(catalog,'module_permission_catalog')}
      ${functionSql(foundation,'require_module_permission')}
      ${functionSql(catalog,'validate_module_permission_catalog')}
      ${functionSql(effective,'require_effective_module_permission')}
      insert into auth.users values('${actor}');
      insert into platform.user_device_authorizations values('${actor}','${actor}');
      insert into public.platform_modules(module_key,display_name) values('conference','Conference'),('reservations','Reservations');`);
    const deviceMigration=read('supabase/migrations/20260920221928_canonical_platform_device_authority_reconciliation.sql');
    query(deviceMigration.match(/alter table public\.module_permission_grants[\s\S]*?;/)[0]);
    apply('supabase/migrations/20260829140000_warehouse_module_permission_catalog.sql');
    // Load only historical catalog DML, through the current event-scope revision.
    // Do not apply Reservations runtime/schema migrations in this fixture.
    for(const file of [
      '20260908153405_reservations_v1_foundation.sql',
      '20260908171814_reservations_event_booking_domain_reconciliation.sql',
      '20260915220000_reservations_authorization_architecture_reconciliation.sql'
    ]){
      const statements=read('supabase/migrations/'+file).match(/(?:insert into|update) public\.module_permission_catalog[\s\S]*?;/g);
      assert.ok(statements&&statements.length,file+' catalog DML');
      for(const statement of statements)query(statement);
    }
    assert.equal(query("select allowed_scope_mode||':'||allowed_resource_type from public.module_permission_catalog where permission_key='reservations.booking.create'"),'both:event');
    const unchanged=()=>query(`select jsonb_build_object(
      'modules',(select jsonb_agg(to_jsonb(m) order by module_key) from public.platform_modules m),
      'grants',(select jsonb_agg(to_jsonb(g) order by grant_id) from public.module_permission_grants g),
      'otherCatalogs',(select jsonb_agg(to_jsonb(c) order by permission_key) from public.module_permission_catalog c where module_key<>'conference'),
      'functions',(select jsonb_agg(pg_get_functiondef(p.oid) order by p.proname) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('require_module_permission','require_effective_module_permission','validate_module_permission_catalog','require_current_approved_device')))`);
    const before=unchanged();
    apply(migration);
    assert.equal(unchanged(),before,'registration, grants, other modules and runtime resolvers unchanged');
    const actual=JSON.parse(query(`select jsonb_agg(jsonb_build_object('key',permission_key,'label',display_name,'description',description,'scope',allowed_scope_mode,'type',allowed_resource_type,'sensitive',sensitive_mutation,'version',catalog_version) order by permission_key) from public.module_permission_catalog where module_key='conference'`));
    assert.deepEqual(actual,mapping.permissions.map(p=>({key:p.key,label:p.label,description:p.description,scope:p.scope,type:p.resourceType,sensitive:p.sensitive,version:1})).sort((a,b)=>a.key.localeCompare(b.key)));
    const catalogBefore=query('select jsonb_agg(to_jsonb(c) order by permission_key) from public.module_permission_catalog c');
    apply(migration);
    assert.equal(query('select jsonb_agg(to_jsonb(c) order by permission_key) from public.module_permission_catalog c'),catalogBefore);
    assert.equal(unchanged(),before);

    // Test-only grants: the migration itself inserts no grant or membership rows.
    const grant=(key,type,id)=>query(`insert into public.module_permission_grants(user_id,module_key,permission_key,resource_type,resource_id,granted_by,granted_by_device_id)
      values('${actor}','conference','${key}',${type?"'"+type+"'":'null'},${id?"'"+id+"'":'null'},'${actor}','${actor}')`);
    const authorize=(key,id=resource,device=actor)=>query(`select public.require_effective_module_permission('${device}','conference','${key}','conference','${id}')->>'authoritySource'`);
    grant('conference.people.view','conference',resource);
    assert.throws(()=>authorize('conference.people.view'),/MODULE_PERMISSION_REQUIRED/,'module access required');
    grant('module.access',null,null);
    assert.equal(authorize('conference.people.view'),'resource_grant');
    assert.throws(()=>authorize('conference.people.view',other),/MODULE_PERMISSION_REQUIRED/);
    assert.throws(()=>authorize('conference.people.view',resource,other),/DEVICE_DENIED/);
    assert.throws(()=>query(`select public.validate_module_permission_catalog('conference','conference.people.view',null,null,'grant')`),/MODULE_PERMISSION_SCOPE_NOT_ALLOWED/);
    assert.throws(()=>query(`select public.validate_module_permission_catalog('conference','conference.people.view','store','${resource}','grant')`),/MODULE_PERMISSION_RESOURCE_TYPE_INVALID/);
    const create=()=>query(`select public.require_effective_module_permission('${actor}','conference','conference.lifecycle.create',null,null)->>'authoritySource'`);
    assert.throws(create,/MODULE_PERMISSION_REQUIRED/);
    grant('conference.lifecycle.create',null,null);
    assert.equal(create(),'module_grant');
    assert.throws(()=>query(`select public.validate_module_permission_catalog('conference','conference.lifecycle.create','conference','${resource}','grant')`),/MODULE_PERMISSION_SCOPE_NOT_ALLOWED/);
    for(const permission of mapping.permissions.filter(p=>p.scope==='resource')){
      assert.throws(()=>query(`select public.validate_module_permission_catalog('conference','${permission.key}',null,null,'grant')`),/MODULE_PERMISSION_SCOPE_NOT_ALLOWED/);
    }
    grant('module.manage',null,null);
    assert.throws(()=>authorize('conference.accounts.manage'),/MODULE_PERMISSION_REQUIRED/,'module administration never implies Conference business authority');
    for(const [role,permissions] of Object.entries(mapping.rolePermissions)){
      query("delete from public.module_permission_grants where permission_key<>'module.access'");
      for(const key of permissions)grant(key,'conference',resource);
      for(const key of keys.filter(k=>k!=='conference.lifecycle.create')){
        if(permissions.includes(key))assert.equal(authorize(key),'resource_grant',role+' '+key);
        else assert.throws(()=>authorize(key),/MODULE_PERMISSION_REQUIRED/,role+' denies '+key);
      }
      assert.throws(create,/MODULE_PERMISSION_REQUIRED/,'bootstrap role grants never imply creation');
      assert.throws(()=>authorize('conference.access.view',other),/MODULE_PERMISSION_REQUIRED/);
    }
    query("update public.module_permission_grants set revoked_at=now(),revoked_by=user_id,revoked_by_device_id=granted_by_device_id where permission_key='conference.access.view'");
    assert.throws(()=>authorize('conference.access.view'),/MODULE_PERMISSION_REQUIRED/);
    query("update public.module_permission_catalog set description='Conflicting pre-existing definition' where permission_key='conference.people.view'");
    const conflictBefore=query('select jsonb_agg(to_jsonb(c) order by permission_key) from public.module_permission_catalog c');
    assert.throws(()=>apply(migration),/CONFERENCE_PERMISSION_CATALOG_CONFLICT/);
    assert.equal(query('select jsonb_agg(to_jsonb(c) order by permission_key) from public.module_permission_catalog c'),conflictBefore);
  }finally{command('dropdb',['--if-exists',database]);}
});

test('each retained permission has a current operation consumer, not only a shadow role declaration',()=>{
  for(const permission of mapping.permissions){
    const evidence=permission.consumerEvidence;
    assert.ok(evidence&&evidence.file&&evidence.anchor,permission.key);
    assert.ok(read(evidence.file).includes(evidence.anchor),permission.key+' consumer reference');
  }
  assert.match(read('people.js'),/function getPeopleDb\(\)[\s\S]*?getCurrentConference\(\)[\s\S]*?return current\.peopleDb/);
  assert.match(read('script.js'),/function saveTemplate\(\)[\s\S]*?appData\.templates\.push/);
  assert.match(read('js/conference-template-houses-editor.js'),/global\.appData\.templates/);
  assert.deepEqual(Object.keys(mapping.removedPermissions).sort(),['conference.templates.manage','conference.templates.view']);
  assert.ok(keys.every(key=>!Object.hasOwn(mapping.removedPermissions,key)));
  assert.match(mapping.purpose,/MIGRATION\/BOOTSTRAP MAPPING/);
  assert.match(read('supabase/migrations/20260815_6_11_0_launch_membership_integrity.sql'),/can_user_create_conferences\(actor_id\)/);
  assert.match(read('supabase/migrations/20260730_5_0_0_system_access_foundation.sql'),/can_create_conferences/);
});

test('reuse has no second foundation, runtime imports, Person adoption, or revived inventory authority',()=>{
  const executable=sql.replace(/--[^\n]*/g,'');
  assert.doesNotMatch(executable.replace(/'(?:''|[^'])*'/g,"''"),/\b(create|alter|drop|update|delete|execute|grant|revoke)\s/i);
  assert.doesNotMatch(executable,/platform\.people|conference_person_links|organization|inventory\.|warehouse\.|reservations\./i);
  const migrations=fs.readdirSync(path.join(root,'supabase/migrations')).filter(name=>name.endsWith('.sql'));
  const foundations=migrations.filter(name=>{
    const source=read('supabase/migrations/'+name);
    return /insert into public\.module_permission_catalog/i.test(source)&&source.includes("'conference.lifecycle.create'");
  });
  assert.deepEqual(foundations,[path.basename(migration)],'exactly the existing U2B catalog migration');
  const runtimeFiles=execFileSync('git',['ls-files','-z'],{cwd:root,encoding:'utf8'}).split('\0')
    .filter(file=>/\.(?:js|ts|html)$/.test(file)&&! /^(?:tests|docs|tools|Releases)\//.test(file));
  for(const file of runtimeFiles){
    assert.ok(!read(file).includes('unified-conference-permission-foundation'),file+' must not load bootstrap fixture');
  }
  for(const dependency of [...sql.matchAll(/to_regprocedure\('public\.([a-z_]+)\(/g)].map(match=>match[1])){
    assert.ok([foundation,catalog,effective,read('supabase/migrations/20260920221928_canonical_platform_device_authority_reconciliation.sql')]
      .some(source=>new RegExp('create(?: or replace)? function public\\.'+dependency+'\\(').test(source)),dependency+' definition exists');
  }
  const declarations=[...read('tests/unified-conference-permission-foundation.test.js').matchAll(/^function\s+(\w+)\(/gm)].map(match=>match[1]);
  assert.equal(new Set(declarations).size,declarations.length,'no duplicate test helper definitions');
});

test('Warehouse and Reservations reuse the same engine; remaining Organization checks are cleanup consumers',()=>{
  const warehouse=read('supabase/migrations/20260829140200_warehouse_v1_guarded_rpc.sql');
  assert.match(warehouse,/public\.require_effective_module_permission\([\s\S]*?'warehouse'/);
  const reservations=read('supabase/migrations/20260915220000_reservations_authorization_architecture_reconciliation.sql');
  assert.match(reservations,/public\.require_effective_module_permission\(/);
  assert.match(reservations,/join public\.organization_members om on om\.organization_id=c\.organization_id and om\.user_id=v_actor/);
  const manifest=read('docs/unified-conference-permission-foundation-u2b.md');
  for(const phrase of ['KEEP','MIGRATE','REMOVE AFTER ZERO CONSUMERS','HISTORICAL ONLY',
    'warehouse.*','reservations.*','inventory.*','MIGRATION/BOOTSTRAP MAPPING',
    'reservations_private.conference_context',
    'reservations_private.booking_creation_context','reservations_private.resolve_event_scope',
    'reservations_private.effective_capabilities','Organization business data','authorization-only',
    'conference-permission-contract.js','conference-members-service.js','require_conference_section_lock_writer',
    'device_guarded_apply_conference_snapshot','zero remaining','allowlist']){
    assert.ok(manifest.includes(phrase),'manifest must identify '+phrase);
  }
});
