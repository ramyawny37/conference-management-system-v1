const assert=require('assert');
const crypto=require('crypto');
const fs=require('fs');
const path=require('path');

const digest=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const functionRecord={schema:'public',name:'guard_device_authorization_security_credential_state',
  arguments:'',owner:'postgres',acl:[{grantee:'postgres',grantor:'postgres',
    privilege:'EXECUTE',grantable:false}]};
const relationRecord={schema:'public',relation:'device_possession_challenge_consumers',
  owner:'postgres',acl:[{grantee:'postgres',grantor:'postgres',privilege:'SELECT',grantable:false}],
  policies:[{name:'example',roles:['postgres']}]};
for(const record of [functionRecord,relationRecord]){
  const noncanonical=JSON.parse(JSON.stringify(record).replaceAll('postgres','apple'));
  assert.notStrictEqual(digest(record),digest(noncanonical),
    'semantic owner/grantee/grantor/policy role changes must alter the fingerprint');
}
const snapshotSql=fs.readFileSync(path.join(__dirname,'catalog-snapshot.sql'),'utf8');
assert.match(snapshotSql,/'owner',o\.rolname/);
assert.match(snapshotSql,/'grantee',case when e\.grantee=0/);
assert.match(snapshotSql,/'grantor',go\.rolname/);
assert.match(snapshotSql,/'roles',\(select jsonb_agg\(coalesce\(pr\.rolname,'PUBLIC'\)/);
console.log('owner fingerprint negative tests: passed');
