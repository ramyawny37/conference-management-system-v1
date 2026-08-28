const assert=require('assert');
const fs=require('fs');
const path=require('path');

const root=path.join(__dirname,'..');
const migrationPath=path.join(root,'supabase','migrations',
  '20260828120132_production_platform_foundation_lineage_bridge.sql');
const verificationPath=path.join(root,'supabase',
  'production-platform-foundation-lineage-bridge-readonly-verification.sql');
const migration=fs.readFileSync(migrationPath,'utf8');
const verification=fs.readFileSync(verificationPath,'utf8');
const platform620=fs.readFileSync(path.join(root,'supabase','migrations',
  '20260827_6_20_0_platform_privileged_device_administration.sql'),'utf8');

assert.match(migration,/begin;[\s\S]*do \$\$[\s\S]*commit;/i);
assert.match(migration,/PRODUCTION_PLATFORM_BRIDGE_EXACT_LINEAGE_REQUIRED/);
[
  ['20260824121653','cb5c461d6a8b0f20d814d2984ce5214f'],
  ['20260824180055','1776e168f18f0a587192ad0d60c621ae'],
  ['20260826191608','ca136f8ef4e70b7a74f43b47142bdc14'],
  ['20260826191920','699f1bf58271c8c75d6026ebc0436b28'],
  ['20260826193052','b62936c7a81c6a743b206d3ef37ff0e2']
].forEach(([version,digest])=>{
  assert.ok(migration.includes(version),`missing exact predecessor ${version}`);
  assert.ok(migration.includes(digest),`missing predecessor digest ${digest}`);
});
assert.match(migration,/\(select count\(\*\) from actual\)=5/);
assert.match(migration,/829e417fab214943e2b6d17376e45c59/);
assert.match(migration,/223e7c5b07516baf39328d71351be2bb/);
assert.match(migration,/8f7e36012b64b5280a895e288fff2948/);
assert.match(migration,/5059f8c84bc709b10cdc258660de52b9/);
assert.match(migration,/7ecaddcfc4b496a13aa1c27b82e1953f/);
assert.match(migration,/relrowsecurity/);
assert.match(migration,/prosecdef/);
assert.match(migration,/search_path=pg_catalog, public/);
assert.match(migration,/has_table_privilege\('anon'/);
assert.match(migration,/PRODUCTION_PLATFORM_BRIDGE_INERT_STATE_REQUIRED/);
assert.match(migration,/PRODUCTION_PLATFORM_BRIDGE_UNEXPECTED_RUNTIME_STATE/);
assert.match(migration,/PRODUCTION_PLATFORM_BRIDGE_6_19_RESULTING_CONTRACT_REQUIRED/);
assert.match(migration,/PRODUCTION_PLATFORM_BRIDGE_DATA_COMPATIBILITY_REQUIRED/);

const executable=migration.replace(/--[^\n]*/g,'');
assert.doesNotMatch(executable,/\b(?:create|alter|drop|truncate|grant|revoke)\s+(?:table|function|policy|trigger|index|type|schema)\b/i);
assert.doesNotMatch(executable,/\b(?:insert\s+into|update\s+public\.|delete\s+from|merge\s+into)\b/i);
assert.doesNotMatch(executable,/\b(?:enabled|enforcement_enabled)\s*=\s*true\b/i);

assert.match(verification,/where version<>'20260828120132'/);
assert.match(verification,/production_platform_foundation_lineage_bridge/);
assert.match(verification,/NOT_YET_APPLIED/);
assert.match(verification,/READY_FOR_INDEPENDENT_PREFLIGHT/);
['829e417fab214943e2b6d17376e45c59','223e7c5b07516baf39328d71351be2bb',
  '8f7e36012b64b5280a895e288fff2948','5059f8c84bc709b10cdc258660de52b9',
  '7ecaddcfc4b496a13aa1c27b82e1953f'].forEach(digest=>
  assert.ok(verification.includes(digest),`verification missing fingerprint ${digest}`));
assert.match(verification,/data_violations/);
assert.doesNotMatch(verification.replace(/--[^\n]*/g,''),
  /\b(?:insert|update|delete|alter|create|drop|truncate|grant|revoke|call)\s+/i);
assert.doesNotMatch(platform620,/supabase_migrations\.schema_migrations/,
  '6.20.0 unexpectedly acquired a migration-history predecessor guard');
assert.match(platform620,/update public\.webauthn_privileged_device_feature set enabled=true/,
  '6.20.0 feature activation boundary changed');

console.log('production platform foundation lineage bridge contract tests: passed');
