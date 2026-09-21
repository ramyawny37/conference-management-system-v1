'use strict';

const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const path=require('node:path');
const test=require('node:test');

const pgBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const psql=path.join(pgBin,'psql');
const createdb=path.join(pgBin,'createdb');
const dropdb=path.join(pgBin,'dropdb');
const database=`platform_provenance_${process.pid}_${Date.now()}`;

function query(sql){
  return execFileSync(psql,['-X','-v','ON_ERROR_STOP=1','-Atq','-d',database,'-c',sql],{encoding:'utf8'}).trim();
}

test('PostgreSQL NOT VALID preserves history and enforces every prospective write',()=>{
  assert.equal(require('node:fs').existsSync(psql),true,'local PostgreSQL client is required');
  execFileSync(createdb,['-T','template0',database],{encoding:'utf8'});
  try{
    query(`
      create table canonical_authorizations(user_id uuid not null,device_id uuid not null,primary key(user_id,device_id));
      create table historical_provenance(id uuid primary key,user_id uuid not null,device_id uuid not null,note text not null);
      insert into historical_provenance values
        ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','pre-canonical');
      alter table historical_provenance add constraint historical_provenance_canonical_fk
        foreign key(user_id,device_id) references canonical_authorizations(user_id,device_id)
        on delete restrict not valid;
    `);
    assert.equal(query("select count(*) from historical_provenance where note='pre-canonical'"),'1');
    assert.equal(query("select convalidated from pg_constraint where conname='historical_provenance_canonical_fk'"),'f');
    assert.throws(()=>query("insert into historical_provenance values('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','invalid-new')"),/foreign key constraint/i);
    query("insert into canonical_authorizations values('20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002')");
    query("insert into historical_provenance values('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','canonical-new')");
    assert.throws(()=>query("update historical_provenance set device_id='30000000-0000-0000-0000-000000000099' where note='pre-canonical'"),/foreign key constraint/i);
    assert.throws(()=>query("delete from canonical_authorizations where user_id='20000000-0000-0000-0000-000000000002'"),/foreign key constraint/i);
    assert.equal(query("select count(*) from historical_provenance h left join canonical_authorizations a using(user_id,device_id) where h.note='canonical-new' and a.user_id is null"),'0');

    query(`
      create table fresh_provenance(id uuid primary key,user_id uuid not null,device_id uuid not null);
      alter table fresh_provenance add constraint fresh_provenance_canonical_fk
        foreign key(user_id,device_id) references canonical_authorizations(user_id,device_id)
        on delete restrict not valid;
    `);
    assert.equal(query('select count(*) from fresh_provenance f left join canonical_authorizations a using(user_id,device_id) where a.user_id is null'),'0');
    assert.equal(query("select convalidated from pg_constraint where conname='fresh_provenance_canonical_fk'"),'f');
  }finally{
    execFileSync(dropdb,['--if-exists',database],{encoding:'utf8'});
  }
});
