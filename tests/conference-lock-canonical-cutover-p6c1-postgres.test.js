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
      end $$;
      create table public.conferences(id uuid primary key);
      create table public.conference_members(conference_id uuid,user_id uuid,role text);
      create table public.conference_membership_operations(id uuid);
      create table public.conference_locks(
        conference_id uuid not null,section text not null,user_id uuid not null,
        device_id uuid not null,lock_token uuid not null,acquired_at timestamptz not null,
        expires_at timestamptz not null,last_renewed_at timestamptz not null,
        created_at timestamptz not null,primary key(conference_id,section)
      );
      create table public.p6c1_permission_calls(permission_key text not null);
      create function public.require_effective_module_permission(uuid,text,text,text,text)
      returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
      begin
        insert into public.p6c1_permission_calls values($3);
        return jsonb_build_object('actorUserId','10000000-0000-0000-0000-000000000001');
      end $$;
      create function public.is_conference_member(uuid) returns boolean language sql as $$select exists(select 1 from public.conference_members where conference_id=$1)$$;
      create function public.has_conference_role(uuid,text[]) returns boolean language sql as $$select exists(select 1 from public.conference_members where conference_id=$1 and role=any($2))$$;
      set check_function_bodies=false;
      create function public.acquire_conference_lock(uuid,uuid,uuid,integer default 120) returns jsonb language sql as $$select public.acquire_conference_section_lock($1,'conference',$2,$3,$4)$$;
      create function public.renew_conference_lock(uuid,uuid,uuid,integer default 120) returns jsonb language sql as $$select public.renew_conference_section_lock($1,'conference',$2,$3,$4)$$;
      create function public.release_conference_lock(uuid,uuid,uuid) returns jsonb language sql as $$select public.release_conference_section_lock($1,'conference',$2,$3)$$;
      create function public.get_conference_lock(uuid,uuid) returns jsonb language sql as $$select public.get_conference_section_lock($1,'conference',$2)$$;
      reset check_function_bodies;
    `);

    for(const migration of migrations)command('psql',['-X','-v','ON_ERROR_STOP=1','-d',database,'-f',migration]);

    assert.equal(query(`select to_regclass('public.conference_members') is null`),'t');
    assert.equal(query(`select to_regclass('public.conference_membership_operations') is null`),'t');
    assert.equal(query(`select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('is_conference_member','has_conference_role')`),'t');
    assert.equal(query(`select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and pg_get_functiondef(p.oid)~*'conference_members|is_conference_member|has_conference_role'`),'t');
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
