const assert=require('assert');
const fs=require('fs');
const path=require('path');

const sql=fs.readFileSync(path.join(__dirname,'../supabase/production-migrations',
  '20260828150000_production_webauthn_privileged_device_final_activation.sql'),'utf8');
const activation=`update public.webauthn_privileged_device_feature
set enabled=true,updated_at=statement_timestamp()
where singleton_id=1 and enabled=false;`;

assert.strictEqual((sql.match(/^update\b/gmi)||[]).length,1);
assert.ok(sql.includes(activation));
assert.doesNotMatch(sql,/^\s*(?:insert|delete|merge|truncate)\b/im);
assert.doesNotMatch(sql,/^\s*(?:create|alter|drop|grant|revoke)\b/im);
assert.match(sql,/bool_and\(not enforcement_enabled\)/);
assert.match(sql,/PRODUCTION_ACTIVATION_EXACT_FULL_LINEAGE_REQUIRED/);
assert.match(sql,/PRODUCTION_STREAM_UNEXPECTED_OPERATIONAL_STATE/);
[
  'device_security_credentials','device_possession_challenges',
  'device_possession_challenge_consumers','privileged_device_listing_sessions',
  'system_owner_credential_bootstrap_authorizations',
  'system_owner_credential_recovery_authorizations',
  'privileged_device_authorization_audit_log','system_owner_device_authorization_operations',
].forEach(relation=>assert.match(sql,new RegExp(`not exists\\(select 1 from public\\.${relation}\\)`)));
const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,
  '../supabase/production-migrations/manifest.json'),'utf8'));
manifest.migrations.slice(0,-1).forEach(entry=>assert.match(sql,new RegExp(entry.version)));
assert.match(sql,/regexp_replace\(p\.prosrc,'\[\[:space:\]\]\+','','g'\)/);
assert.match(sql,/p_environment,now\(\)\+interval''2minutes''\)/);

console.log('STEP13_ACTIVATION_MUTATION_SEMANTICS_UNCHANGED');
