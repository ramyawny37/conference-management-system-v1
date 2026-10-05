'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const test=require('node:test');

const migrations=[
  '20261009120000_retire_conference_role_membership_authority.sql',
  '20261009120000_retire_linked_whole_snapshot_infrastructure.sql',
  '20261009121000_cut_conference_locks_to_canonical_permissions.sql',
  '20261009121500_final_conference_membership_consumer_demolition.sql',
  '20261009122000_retire_conference_membership_plane.sql'
].map(name=>path.resolve('supabase/migrations',name));
const pgApp='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=fs.existsSync(path.join(pgApp,'psql'))?pgApp:'';
const database=`conference_p6c1_${process.pid}_${Date.now()}`;
const connection=['-h',process.env.PGHOST||'/tmp','-p',process.env.PGPORT||'5432','-U',process.env.PGUSER||os.userInfo().username];

function command(name,args){
  return execFileSync(pgBin?path.join(pgBin,name):name,[...connection,...args],{encoding:'utf8',stdio:'pipe'}).trim();
}
function query(sql){
  return command('psql',['-X','-v','ON_ERROR_STOP=1','-At','-d',database,'-c',sql]);
}

test('P6C1 lock cutover executes deterministically and uses only canonical permissions',()=>{
  command('createdb',[database]);
  try{
    query(`
      do $$ begin
        if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
        if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
        if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
      end $$;
      create schema auth; create schema platform; create schema platform_private;
      create function auth.role() returns text language sql stable as $$select 'service_role'::text$$;
      create table auth.users(id uuid primary key,email text);
      create table public.profiles(id uuid primary key,display_name text);
      create table public.system_user_access(user_id uuid primary key,account_status text,can_create_conferences boolean);
      create table public.system_user_roles(user_id uuid,role text);
      create table public.organizations(id uuid primary key,display_name text,status text);
      create table public.organization_members(organization_id uuid,user_id uuid,role text,created_at timestamptz default now());
      create table public.conferences(id uuid primary key,name text,owner_id uuid,organization_id uuid,deleted_at timestamptz);
      create table public.conference_members(conference_id uuid,user_id uuid,role text);
      create table public.conference_membership_operations(id uuid);
      create table public.conference_locks(
        conference_id uuid not null,section text not null,user_id uuid not null,
        device_id uuid not null,lock_token uuid not null,acquired_at timestamptz not null,
        expires_at timestamptz not null,last_renewed_at timestamptz not null,
        created_at timestamptz not null,primary key(conference_id,section)
      );
      create table platform.profiles(user_id uuid primary key,account_status text);
      create table platform.devices(id uuid primary key,user_id uuid,lifecycle_status text,retired_at timestamptz,compromised_at timestamptz);
      create table platform.user_device_authorizations(id uuid primary key,user_id uuid,device_id uuid,status text,revoked_at timestamptz);
      create table platform.device_key_bindings(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,public_key_thumbprint text,lifecycle_status text,revoked_at timestamptz,retired_at timestamptz);
      create table platform_private.device_sessions(id uuid primary key,user_id uuid,device_id uuid,device_authorization_id uuid,binding_id uuid,token_hash bytea,public_key_thumbprint text,revoked_at timestamptz,expires_at timestamptz);
      create table public.p6c1_permission_calls(permission_key text not null);
      create function public.require_current_approved_device(uuid) returns uuid language sql stable as $$select '10000000-0000-0000-0000-000000000001'::uuid$$;
      create function public.is_system_owner(uuid) returns boolean language sql stable as $$select true$$;
      create function platform_private.canonical_device_count(uuid) returns bigint language sql stable as $$select 0::bigint$$;
      create function platform_private.require_exact_jsonb_keys(jsonb,text[],text[] default '{}') returns void language sql as $$select$$;
      create function public.require_effective_module_permission(uuid,text,text,text,text)
      returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
      begin
        insert into public.p6c1_permission_calls values($3);
        return jsonb_build_object('actorUserId','10000000-0000-0000-0000-000000000001');
      end $$;
      create function public.is_conference_member(uuid) returns boolean language sql as $$select exists(select 1 from public.conference_members where conference_id=$1)$$;
      create function public.has_conference_role(uuid,text[]) returns boolean language sql as $$select exists(select 1 from public.conference_members where conference_id=$1 and role=any($2))$$;
      create function public.add_conference_owner_membership() returns trigger language plpgsql as $$begin insert into public.conference_members values(new.id,new.owner_id,'owner');return new;end$$;
      create trigger conferences_add_owner_membership after insert on public.conferences for each row execute function public.add_conference_owner_membership();
      create function public.enforce_conference_lock_manager() returns trigger language plpgsql as $$begin if not public.has_conference_role(new.conference_id,array['owner','manager']) then raise exception 'DENIED';end if;return new;end$$;
      create trigger conference_locks_require_manager before insert or update on public.conference_locks for each row execute function public.enforce_conference_lock_manager();
      create function public.prevent_invalid_conference_organization_change() returns trigger language plpgsql as $$begin if exists(select 1 from public.conference_members where conference_id=old.id) then return new;end if;return new;end$$;
      create trigger conferences_prevent_invalid_organization_change before update of organization_id on public.conferences for each row execute function public.prevent_invalid_conference_organization_change();
      create table public.legacy_conference_organization_assignments(operation_id uuid primary key);
      create function public.create_organization_conference_idempotent(uuid,uuid,uuid,text,jsonb) returns jsonb language sql as $$select jsonb_build_object('legacyMembers',(select count(*) from public.conference_members))$$;
      create function public.device_guarded_create_organization_conference_idempotent(uuid,uuid,uuid,uuid,text,jsonb) returns jsonb language sql as $$select public.create_organization_conference_idempotent($2,$3,$4,$5,$6)$$;
      create function public.device_guarded_get_conference_creation_operation(uuid,uuid) returns jsonb language sql as $$select '{}'::jsonb$$;
      create function public.device_guarded_list_available_conferences(uuid) returns jsonb language sql as $$select jsonb_build_object('members',(select count(*) from public.conference_members))$$;
      create function public.device_guarded_list_eligible_legacy_conference_organizations(uuid,uuid) returns jsonb language sql as $$select jsonb_build_object('members',(select count(*) from public.conference_members))$$;
      create function public.device_guarded_assign_legacy_conference_organization(uuid,uuid,uuid,uuid) returns jsonb language sql as $$select jsonb_build_object('members',(select count(*) from public.conference_members))$$;
      set check_function_bodies=false;
      create function platform.execute_conference_device_operation_phase1c_core(uuid,uuid,bytea,text,jsonb) returns jsonb language sql as $$select '{}'::jsonb$$;
      create function public.acquire_conference_lock(uuid,uuid,uuid,integer default 120) returns jsonb language sql as $$select public.acquire_conference_section_lock($1,'conference',$2,$3,$4)$$;
      create function public.renew_conference_lock(uuid,uuid,uuid,integer default 120) returns jsonb language sql as $$select public.renew_conference_section_lock($1,'conference',$2,$3,$4)$$;
      create function public.release_conference_lock(uuid,uuid,uuid) returns jsonb language sql as $$select public.release_conference_section_lock($1,'conference',$2,$3)$$;
      create function public.get_conference_lock(uuid,uuid) returns jsonb language sql as $$select public.get_conference_section_lock($1,'conference',$2)$$;
      reset check_function_bodies;
      insert into auth.users values('10000000-0000-0000-0000-000000000001','actor@example.test'),('11000000-0000-0000-0000-000000000001','target@example.test');
      insert into public.profiles values('10000000-0000-0000-0000-000000000001','Actor'),('11000000-0000-0000-0000-000000000001','Target');
      insert into public.system_user_access values('10000000-0000-0000-0000-000000000001','approved',true),('11000000-0000-0000-0000-000000000001','approved',false);
    `);

    for(const migration of migrations)command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migration]);

    assert.equal(query(`select to_regclass('public.conference_members') is null`),'t');
    assert.equal(query(`select to_regclass('public.conference_membership_operations') is null`),'t');
    assert.equal(query(`select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('is_conference_member','has_conference_role')`),'t');
    assert.equal(query(`select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and pg_get_functiondef(p.oid)~*'conference_members|is_conference_member|has_conference_role'`),'t');
    assert.equal(query(`select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('add_conference_owner_membership','enforce_conference_lock_manager','prevent_invalid_conference_organization_change','device_guarded_create_organization_conference_idempotent','create_organization_conference_idempotent','device_guarded_get_conference_creation_operation','device_guarded_list_available_conferences','device_guarded_list_eligible_legacy_conference_organizations','device_guarded_assign_legacy_conference_organization')`),'t');
    assert.equal(query(`select count(*)=0 from pg_trigger where not tgisinternal and tgname in ('conferences_add_owner_membership','conference_locks_require_manager','conferences_prevent_invalid_organization_change')`),'t');
    assert.equal(query(`select to_regclass('public.legacy_conference_organization_assignments') is null`),'t');
    assert.equal(query(`select not (public.search_user_management_users('30000000-0000-0000-0000-000000000001','','approved',50)#>'{users,0}') ?| array['conferenceCount','conferenceRole','isMember']`),'t');
    assert.equal(query(`select not public.get_user_management_overview('30000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000001') ?| array['conferences','conferenceCount']`),'t');
    assert.equal(query(`select not (public.get_user_management_overview('30000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000001')->'capabilities') ?| array['canViewConferences','canManageConferenceMembership']`),'t');
    assert.equal(query(`select count(*)=9 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('require_conference_section_lock_writer','acquire_conference_section_lock','renew_conference_section_lock','release_conference_section_lock','get_conference_section_lock','acquire_conference_lock','renew_conference_lock','release_conference_lock','get_conference_lock')`),'t');
    assert.equal(query(`select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%conference%lock%' and pg_get_functiondef(p.oid)~*'''owner''|''manager''|''viewer'''`),'t');
    assert.equal(query(`select not has_function_privilege('public','public.acquire_conference_section_lock(uuid,text,uuid,uuid,integer)','execute') and not has_function_privilege('anon','public.acquire_conference_section_lock(uuid,text,uuid,uuid,integer)','execute') and has_function_privilege('authenticated','public.acquire_conference_section_lock(uuid,text,uuid,uuid,integer)','execute')`),'t');

    query(`insert into public.conferences values('20000000-0000-0000-0000-000000000001')`);
    assert.equal(query(`select public.acquire_conference_section_lock('20000000-0000-0000-0000-000000000001','accommodation','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',120)->>'status'`),'acquired');
    assert.equal(query(`select public.get_conference_section_lock('20000000-0000-0000-0000-000000000001','accommodation','30000000-0000-0000-0000-000000000001')->>'owned'`),'true');
    assert.equal(query(`select public.renew_conference_section_lock('20000000-0000-0000-0000-000000000001','accommodation','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',120)->>'status'`),'renewed');
    assert.equal(query(`select public.release_conference_section_lock('20000000-0000-0000-0000-000000000001','accommodation','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001')->>'status'`),'released');
    assert.equal(query(`select public.acquire_conference_lock('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',120)->>'status'`),'acquired');
    assert.equal(query(`select string_agg(distinct permission_key,',' order by permission_key) from public.p6c1_permission_calls`),'conference.accommodation.manage,conference.sync.write');
  }finally{
    command('dropdb',['--if-exists',database]);
  }
});
