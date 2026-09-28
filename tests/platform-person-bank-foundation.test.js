'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {execFileSync} = require('node:child_process');
const test = require('node:test');
const root = path.join(__dirname, '..');
const migration = 'supabase/migrations/20260928120000_platform_person_bank_foundation.sql';
const sql = fs.readFileSync(path.join(root, migration), 'utf8');
const foundation = fs.readFileSync(path.join(root, 'supabase/migrations/20260907155000_production_structural_platform_foundation.sql'), 'utf8');
const postgresAppBin = '/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin = fs.existsSync(path.join(postgresAppBin, 'psql')) ? postgresAppBin : '';
const database = `platform_person_p2a_${process.pid}_${Date.now()}`;
// Use the isolated PostgreSQL selected by the validation environment when present.
// Local Postgres.app remains the developer fallback; never inherit a live connection URL.
const validationHost = process.env.PGHOST;
const validationPort = process.env.PGPORT;
const validationUser = process.env.PGUSER;
const validationPassword = process.env.PGPASSWORD;
const connection = validationHost
  ? ['-h', validationHost, '-p', validationPort || '5432', '-U', validationUser || os.userInfo().username]
  : ['-h', '/tmp', '-p', '5432', '-U', os.userInfo().username];
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('PG')));
if (validationPassword) env.PGPASSWORD = validationPassword;
const actor = '10000000-0000-0000-0000-000000000001';
function command(name, args) {
  return execFileSync(pgBin ? path.join(pgBin, name) : name, [...connection, ...args], {encoding:'utf8', env, stdio:'pipe'}).trim();
}
function query(statement) {
  return command('psql', ['-X', '-v', 'ON_ERROR_STOP=1', '-At', '-d', database, '-c', statement]);
}
function scalar(statement) { return JSON.parse(query(statement)); }
function createPerson(values) {
  return query(`insert into platform.people(full_name,created_by,updated_by${values.columns || ''})
    values(${values.name},'${actor}','${actor}'${values.values || ''}) returning id` ).split('\n')[0];
}
function rejectsSql(statement, pattern) {
  assert.throws(() => query(statement), error => pattern.test(String(error.stderr)));
}

test('P2A adds only private Person storage/search, with no legacy mutation or public API', () => {
  const executable = sql.replace(/--[^\n]*/g, '');
  assert.match(executable, /begin;[\s\S]*commit;/);
  assert.deepEqual([...executable.matchAll(/create table ([\w.]+)/g)].map(m => m[1]), ['platform.people']);
  assert.doesNotMatch(executable, /\b(?:insert into|update\s+\w+\.|delete from|create policy|grant\s|security definer)\b/i);
  assert.doesNotMatch(executable, /\b(?:organization_id|workspace_id|reservations\.|warehouse\.|conference_person_links)\b/);
  const names = [...executable.matchAll(/create function ([\w.]+)/g)].map(m => m[1]);
  assert.equal(new Set(names).size, 3);
  assert.ok(names.every(name => name.startsWith('platform_private.')));
  assert.match(executable, /execute function platform_private\.set_updated_at\(\)/);
  assert.match(foundation, /function platform_private\.set_updated_at\(\)/);
});

test('isolated PostgreSQL Person foundation', async t => {
  try {
    command('psql', ['-X', '-At', '-d', 'postgres', '-c', 'select 1']);
  } catch {
    assert.fail('local PostgreSQL is required; do not silently skip');
  }
  command('createdb', [database]);
  try {
    // Minimal Supabase-shaped fixture: the production migration revokes these API roles,
    // so the isolated database must define them before executing the real migration.
    query(`do $$ begin
        if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
        if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
        if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
      end $$;
      create schema auth; create schema platform; create schema platform_private; create schema extensions;
      create extension pgcrypto with schema extensions;
      create table auth.users(id uuid primary key);`);
    // Use actual Platform profile schema and timestamp trigger; only auth.users is a minimal fixture.
    const profiles = foundation.match(/create table platform\.profiles \([\s\S]*?\n\);/)[0];
    const trigger = foundation.match(/create or replace function platform_private\.set_updated_at\(\)[\s\S]*?\$\$;/)[0];
    query(profiles + trigger);
    query(`insert into auth.users values('${actor}'); insert into platform.profiles(user_id) values('${actor}');`);
    command('psql', ['-X', '-v', 'ON_ERROR_STOP=1', '-d', database, '-f', path.join(root, migration)]);
    let first;
    await t.test('minimum creation needs no Person login, phone, gender, birth date, or church', () => {
      first = createPerson({name:"'Same Name'"});
      assert.match(first, /^[0-9a-f-]{36}$/);
      assert.equal(query(`select (phone is null and gender is null and date_of_birth is null and church is null and revision=1 and created_at is not null and updated_at is not null)::text from platform.people where id='${first}'`), 'true');
      assert.equal(query(`select count(*) from auth.users where id='${first}'`), '0');
    });
    await t.test('trusted system storage permits absent actors without creating a fake profile', () => {
      const profilesBefore = query('select count(*) from platform.profiles');
      const id = query("insert into platform.people(full_name) values('System import') returning id").split('\n')[0];
      assert.equal(query(`select created_by is null and updated_by is null from platform.people where id='${id}'`), 't');
      assert.equal(query('select count(*) from platform.profiles'), profilesBefore);
      query(`update platform.people set updated_by='${actor}' where id='${id}'`);
      assert.equal(query(`select created_by is null and updated_by='${actor}' from platform.people where id='${id}'`), 't');
      rejectsSql(`insert into platform.people(full_name,created_by) values('Invalid actor','ffffffff-ffff-ffff-ffff-ffffffffffff')`, /foreign key constraint/);
      rejectsSql(`update platform.people set updated_by='ffffffff-ffff-ffff-ffff-ffffffffffff' where id='${id}'`, /foreign key constraint/);
      query(`delete from platform.people where id='${id}'`);
    });
    await t.test('duplicate names and shared phones remain distinct; no implicit merge', () => {
      const second = createPerson({name:"'Same Name'", columns:',phone,gender', values:",'٠١٢٣ ٤٥٦','male'"});
      const third = createPerson({name:"'Same Name'", columns:',phone,gender', values:",'0123-456','female'"});
      assert.notEqual(first, second); assert.notEqual(second, third);
      assert.equal(query("select count(*) from platform_private.search_people(' same   NAME ')").trim(), '3');
      assert.equal(query('select count(*) from platform.people'), '3');
    });
    await t.test('canonical male/female filters and invalid gender rejection', () => {
      for (const gender of ['male', 'female']) {
        assert.equal(query(`select count(*) from platform_private.search_people('same','${gender}')`), '1');
      }
      rejectsSql(`insert into platform.people(full_name,gender,created_by,updated_by) values('Invalid','other','${actor}','${actor}')`, /check constraint/);
      rejectsSql("select * from platform_private.search_people('','other')", /PLATFORM_PERSON_GENDER_INVALID/);
    });
    await t.test('Arabic whitespace, Latin case and phone digit/format normalization are search-only', () => {
      const id = createPerson({name:"E'  مريم  \\t حنا  '", columns:',phone,date_of_birth,church', values:",'۰۱۲۳ (۴۵۶)',date '1990-02-03','Shared church'"});
      assert.equal(query("select count(*) from platform_private.search_people('مريم حنا')"), '1');
      assert.equal(query("select count(*) from platform_private.search_people('٠١٢٣-٤٥٦')"), '3');
      assert.equal(query(`select full_name=E'  مريم  \\t حنا  ' and phone='۰۱۲۳ (۴۵۶)' and date_of_birth=date '1990-02-03' from platform.people where id='${id}'`), 't');
      assert.equal(query("select count(*) from platform_private.search_people('%')"), '0');
      assert.equal(query("select count(*) from platform_private.search_people('_')"), '0');
    });
    await t.test('name and mixed queries cannot accidentally match unrelated phone digits', () => {
      const id = createPerson({name:"'Search Person 0123'"});
      for (const input of ['Search Person', 'Search Person 0123', 'SEARCH   PERSON 0123']) {
        assert.equal(query(`select jsonb_agg(id) from platform_private.search_people('${input}')`), JSON.stringify([id]));
      }
      for (const input of ['Unrelated', 'Unrelated 0123', '0123abc', 'phone:0123', '٠١٢٣مريم']) {
        assert.equal(query(`select count(*) from platform_private.search_people('${input}')`), '0');
      }
      for (const input of ['0123', '+٠١٢٣ (٤٥٦)', '۰۱۲۳.۴۵۶', ' 0123-456 ']) {
        assert.equal(query(`select count(*) from platform_private.search_people('${input}')`), '3');
      }
    });
    await t.test('LIKE metacharacters are literal even alongside digits', () => {
      const fixtures = [["'Literal%0123'", 'Literal%'], ["'Literal_0123'", 'Literal_'], [String.raw`E'Literal\\0123'`, 'Literal\\']];
      for (const [name, prefix] of fixtures) {
        const id = createPerson({name});
        const quoted = "'" + prefix.replaceAll("'", "''") + "'";
        assert.equal(query(`select jsonb_agg(id) from platform_private.search_people(${quoted})`), JSON.stringify([id]));
      }
      for (const input of ['%0123', '_0123', '0123%']) {
        assert.equal(query(`select count(*) from platform_private.search_people('${input}')`), '0');
      }
    });
    await t.test('blank names and digitless phones are rejected', () => {
      rejectsSql(`insert into platform.people(full_name,created_by,updated_by) values(E' \\t ','${actor}','${actor}')`, /check constraint/);
      rejectsSql(`insert into platform.people(full_name,phone,created_by,updated_by) values('Name','---','${actor}','${actor}')`, /check constraint/);
    });
    await t.test('bounded deterministic lookup never merges or mutates identities', () => {
      query(`insert into platform.people(full_name,created_by,updated_by) select 'Repeated','${actor}','${actor}' from generate_series(1,60)`);
      for (const [limit, expected] of [['10000','50'], ['null','20'], ['-1','1'], ['0','1'], ['3','3']]) {
        assert.equal(query(`select count(*) from platform_private.search_people('',null,${limit})`), expected);
      }
      const before = query('select jsonb_agg(p order by id) from platform.people p');
      const results = query("select jsonb_agg(id) from platform_private.search_people('Repeated',null,50)");
      assert.equal(results, query("select jsonb_agg(id) from platform_private.search_people('Repeated',null,50)"));
      const ids = JSON.parse(results); assert.deepEqual(ids, [...ids].sort());
      assert.equal(query('select jsonb_agg(p order by id) from platform.people p'), before);
      assert.equal(query("select count(*) from platform.people where full_name='Repeated'"), '60');
    });
    await t.test('exact schema excludes organization, participation and all module data', () => {
      const columns = scalar("select json_agg(column_name order by ordinal_position) from information_schema.columns where table_schema='platform' and table_name='people'");
      assert.deepEqual(columns, ['id','full_name','phone','gender','date_of_birth','church','name_search','phone_search','revision','created_at','updated_at','created_by','updated_by']);
      assert.equal(query("select count(*) from pg_constraint where conrelid='platform.people'::regclass and contype='u'"), '0');
      assert.equal(query("select count(*) from pg_index where indrelid='platform.people'::regclass and not indisprimary and not indisunique"), '3');
    });
    await t.test('anon/authenticated/service_role have no direct read, mutation or helper privileges', () => {
      assert.equal(query("select relrowsecurity and relforcerowsecurity from pg_class where oid='platform.people'::regclass"), 't');
      for (const role of ['anon','authenticated','service_role']) {
        for (const privilege of ['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) {
          assert.equal(query(`select has_table_privilege('${role}','platform.people','${privilege}')`), 'f');
        }
        for (const signature of ['person_name_key(text)','person_phone_key(text)','search_people(text,text,integer)']) {
          assert.equal(query(`select has_function_privilege('${role}','platform_private.${signature}','EXECUTE')`), 'f');
        }
        for (const statement of ["select * from platform.people", `insert into platform.people(full_name,created_by,updated_by) values('Denied','${actor}','${actor}')`, "insert into platform.people(full_name) values('Denied system impersonation')", "update platform.people set created_by=null,updated_by=null", "update platform.people set full_name='Denied'", 'delete from platform.people', 'truncate platform.people', "select * from platform_private.search_people('')"]) {
          rejectsSql(`set role ${role}; ${statement}`, /permission denied/);
        }
      }
    });
    await t.test('Platform actor references and timestamp trigger are reused, with no invented mutation ledger', () => {
      assert.equal(query("select count(*) from pg_constraint where conrelid='platform.people'::regclass and contype='f' and confrelid='platform.profiles'::regclass and confdeltype='r'"), '2');
      query(`update platform.people set updated_at='2000-01-01' where id='${first}'`);
      assert.equal(query(`select updated_at>'2000-01-02' from platform.people where id='${first}'`), 't');
      rejectsSql(`delete from platform.profiles where user_id='${actor}'`, /foreign key constraint/);
    });
    await t.test('future restrictive references block Person deletion; removing a reference preserves Person', () => {
      // Test-only contract probe, NOT a new production module or lifecycle mechanism.
      query('create table public.person_reference_probe(person_id uuid references platform.people(id) on delete restrict)');
      query(`insert into public.person_reference_probe values('${first}')`);
      rejectsSql(`delete from platform.people where id='${first}'`, /foreign key constraint/);
      query('delete from public.person_reference_probe');
      assert.equal(query(`select count(*) from platform.people where id='${first}'`), '1');
    });
  } finally {
    command('dropdb', ['--if-exists', database]);
  }
});