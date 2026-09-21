'use strict';
const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const postgresAppBin='/Applications/Postgres.app/Contents/Versions/latest/bin';
const pgBin=process.env.PG_BIN||(fs.existsSync(postgresAppBin)?postgresAppBin:'');
const tool=name=>pgBin?path.join(pgBin,name):name;
const database=`platform_rerequest_${process.pid}_${Date.now()}`;

test('same-key revoked-device rerequest is transactional, exact, and replay-safe',()=>{
  assert.doesNotThrow(()=>execFileSync(tool('psql'),['--version'],{stdio:'pipe'}),'local PostgreSQL client is required');
  execFileSync(tool('createdb'),['-T','template0',database]);
  try{
    const result=execFileSync(tool('psql'),['-X','-v','ON_ERROR_STOP=1','-d',database,'-f','tests/sql/platform-revoked-device-native-key-rerequest-rehearsal.sql'],{encoding:'utf8'});
    assert.match(result,/"status": "pending"/);
  }finally{execFileSync(tool('dropdb'),['--if-exists',database]);}
});
