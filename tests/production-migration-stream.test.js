const assert=require('assert');
const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const root=path.join(__dirname,'..');
const dir=path.join(root,'supabase','production-migrations');
const manifest=JSON.parse(fs.readFileSync(path.join(dir,'manifest.json'),'utf8'));
const runner=require('../scripts/production-migration-runner');
const commandGuard=require('../scripts/production-supabase-command-guard');
const sha=v=>crypto.createHash('sha256').update(v).digest('hex');

runner.validateManifest(manifest);
assert.strictEqual(manifest.migrations.length,13);
assert.strictEqual(new Set(manifest.migrations.map(x=>x.version)).size,13);
manifest.migrations.forEach((entry,index)=>{
  assert.match(entry.version,/^\d{14}$/);
  assert.strictEqual(sha(fs.readFileSync(path.join(dir,entry.file),'utf8')),entry.productionSha256);
  assert.strictEqual(sha(fs.readFileSync(path.join(dir,entry.preflight),'utf8')),entry.preflightSha256);
  assert.doesNotMatch(fs.readFileSync(path.join(dir,entry.file),'utf8'),/^\+/m);
  if(entry.sourceCanonicalPath)
    assert.strictEqual(sha(fs.readFileSync(path.join(root,entry.sourceCanonicalPath),'utf8')),
      entry.canonicalSourceSha256);
  if(index<manifest.migrations.length-1){
    assert.strictEqual(entry.expectedWebAuthnBefore,false);
    assert.strictEqual(entry.expectedWebAuthnAfter,false);
  }
  assert.strictEqual(entry.expectedDeviceEnforcementBefore,false);
  assert.strictEqual(entry.expectedDeviceEnforcementAfter,false);
});
assert.deepStrictEqual(manifest.migrations.filter(x=>x.featureActivationPermitted)
  .map(x=>x.version),['20260828150000']);

const structural=manifest.migrations[1];
const production620=fs.readFileSync(path.join(dir,structural.file),'utf8');
const canonical620=fs.readFileSync(path.join(root,structural.sourceCanonicalPath),'utf8');
assert.doesNotMatch(production620,/set enabled=true/i);
assert.match(canonical620,/set enabled=true/i);
const canonicalCore=canonical620.replace(/^begin;\s*/i,'').replace(/\s*commit;\s*$/i,'')
  .replace(/\nupdate public\.webauthn_privileged_device_feature set enabled=true,updated_at=statement_timestamp\(\)\nwhere singleton_id=1 and enabled=false;/i,'').trim();
assert.ok(production620.includes(canonicalCore),'6.20.0 derivative has an unapproved canonical-body delta');

const bridge=fs.readFileSync(path.join(dir,manifest.migrations[0].file),'utf8');
assert.match(bridge,/PRODUCTION_PLATFORM_BRIDGE_6_19_SEMANTIC_CONTRACT_REQUIRED/);
assert.match(bridge,/t\.tgrelid=c\.oid and t\.tgname=expected\.trigger_name/);
assert.match(bridge,/server_version_num/);

assert.throws(()=>runner.assertTarget(manifest,''),/PRODUCTION_PROJECT_REF_REQUIRED/);
assert.throws(()=>runner.assertTarget(manifest,'gppwltrifgfxrkzvvxoe'),/DEVELOPMENT_PROJECT_FORBIDDEN/);
assert.throws(()=>runner.assertTarget(manifest,'wrong'),/WRONG_PRODUCTION_PROJECT/);
const configuredManifest={...manifest,productionDatabaseIdentity:{
  systemIdentifier:'prod-system-1',databaseName:'postgres',postgresMajor:17}};
assert.strictEqual(runner.assertDatabaseIdentity(configuredManifest,manifest.productionProjectRef,
  {systemIdentifier:'prod-system-1',databaseName:'postgres',postgresMajor:17}),true);
assert.throws(()=>runner.assertDatabaseIdentity(configuredManifest,manifest.productionProjectRef,
  {systemIdentifier:'development-system',databaseName:'postgres',postgresMajor:17}),/IDENTITY_MISMATCH/);
assert.throws(()=>runner.assertDatabaseIdentity(configuredManifest,manifest.productionProjectRef,
  {systemIdentifier:'unknown',databaseName:'postgres',postgresMajor:17}),/IDENTITY_MISMATCH/);
assert.throws(()=>runner.assertDatabaseIdentity(configuredManifest,'gppwltrifgfxrkzvvxoe',
  {systemIdentifier:'prod-system-1',databaseName:'postgres',postgresMajor:17}),/DEVELOPMENT_PROJECT_FORBIDDEN/);
assert.throws(()=>runner.assertDatabaseIdentity(configuredManifest,manifest.productionProjectRef,null),
  /IDENTITY_UNAVAILABLE/);
assert.throws(()=>runner.assertDatabaseIdentity({...manifest,productionDatabaseIdentity:null},manifest.productionProjectRef,
  {systemIdentifier:'prod-system-1',databaseName:'postgres',postgresMajor:17}),/IDENTITY_NOT_CONFIGURED/);
const history=[manifest.initialPredecessor];
assert.throws(()=>runner.selectNext(manifest,'not-listed',history),/OUT_OF_MANIFEST/);
assert.throws(()=>runner.selectNext(manifest,manifest.migrations[1].version,history),/SKIP_FORBIDDEN/);
assert.throws(()=>runner.selectNext(manifest,manifest.migrations[0].version,
  [...history,{version:manifest.migrations[0].version,name:manifest.migrations[0].name}]),/REPLAY_FORBIDDEN/);
assert.throws(()=>runner.parseArgs(['--dry-run','--apply']),/EXACTLY_ONE_MODE/);
assert.throws(()=>runner.parseArgs(['--dry-run','--version','1','--version','2']),/UNSUPPORTED|EXACTLY|./);

const streamRow=(entry,overrides={})=>({version:entry.version,name:entry.name,
  digest:crypto.createHash('md5').update(fs.readFileSync(path.join(dir,entry.file),'utf8')).digest('hex'),
  ...overrides});
assert.strictEqual(runner.verifyLatestCommitted(manifest,history,()=>{throw new Error('not called');}).status,
  'NO_COMMITTED_PRODUCTION_MIGRATION');
const firstCommitted=[...history,streamRow(manifest.migrations[0])];
let verifierCalls=0;
let recovery=runner.verifyLatestCommitted(manifest,firstCommitted,entry=>{
  verifierCalls++;assert.strictEqual(entry.version,manifest.migrations[0].version);return true;});
assert.strictEqual(recovery.status,'COMMITTED_VERIFICATION_RECOVERED');
assert.strictEqual(recovery.next.version,manifest.migrations[1].version);
assert.strictEqual(verifierCalls,1);
recovery=runner.verifyLatestCommitted(manifest,firstCommitted,()=>false);
assert.strictEqual(recovery.status,'COMMITTED_POST_VERIFICATION_FAILED');
assert.strictEqual(recovery.next.version,manifest.migrations[1].version);
assert.throws(()=>runner.selectNext(manifest,manifest.migrations[0].version,firstCommitted),
  /REPLAY_FORBIDDEN/);
assert.strictEqual(runner.selectNext(manifest,manifest.migrations[1].version,firstCommitted).version,
  manifest.migrations[1].version);
assert.throws(()=>runner.verifyLatestCommitted(manifest,
  [...history,streamRow(manifest.migrations[0],{digest:'0'.repeat(32)})],()=>true),/DIGEST_MISMATCH/);
assert.throws(()=>runner.verifyLatestCommitted(manifest,
  [...history,streamRow(manifest.migrations[0],{name:'wrong'})],()=>true),/NAME_MISMATCH/);
assert.throws(()=>runner.verifyLatestCommitted(manifest,
  [...history,streamRow(manifest.migrations[1])],()=>true),/SEQUENCE_MISMATCH/);

// Exercise the same recovery-before-plan order used by runner.main(), while making every
// mutating capability an explicit spy so committed recovery cannot silently replay SQL.
function recoverThenPlan({committedHistory,requestedVersion,verify,mutations}){
  const recovered=runner.verifyLatestCommitted(manifest,committedHistory,verify);
  if(recovered.status==='COMMITTED_POST_VERIFICATION_FAILED')
    return {recovered,eligible:null};
  const eligible=runner.plan({target:manifest.productionProjectRef,
    version:requestedVersion,history:committedHistory});
  // Recovery classification and dry-run planning deliberately receive no mutation callback.
  // These calls represent the only mutation boundary used after an authorized apply.
  if(mutations.applyAuthorized===true){
    mutations.executeMigration();
    mutations.insertHistory();
  }
  return {recovered,eligible};
}

const recoveryMutationCalls={sql:0,insert:0,update:0,delete:0,ledger:0};
const recoveryMutations={applyAuthorized:false,
  executeMigration:()=>recoveryMutationCalls.sql++,
  insertHistory:()=>recoveryMutationCalls.insert++};
const step3=manifest.migrations[2];
const step4=manifest.migrations[3];
const committedThroughStep3=[...history,...manifest.migrations.slice(0,3).map(streamRow)];
const authoritativeHistoryBefore=JSON.stringify(committedThroughStep3);

let step3VerifierCalls=0;
let step3Gate=recoverThenPlan({committedHistory:committedThroughStep3,
  requestedVersion:step4.version,verify:entry=>{
    step3VerifierCalls++;
    assert.strictEqual(entry.version,step3.version);
    return false;
  },mutations:recoveryMutations});
assert.strictEqual(step3Gate.recovered.status,'COMMITTED_POST_VERIFICATION_FAILED');
assert.strictEqual(step3Gate.eligible,null,'Step 4 became eligible before Step-3 recovery');
assert.strictEqual(step3VerifierCalls,1);
assert.deepStrictEqual(recoveryMutationCalls,{sql:0,insert:0,update:0,delete:0,ledger:0});
assert.strictEqual(JSON.stringify(committedThroughStep3),authoritativeHistoryBefore);
assert.throws(()=>runner.selectNext(manifest,step3.version,committedThroughStep3),
  /PRODUCTION_MIGRATION_REPLAY_FORBIDDEN/);

step3Gate=recoverThenPlan({committedHistory:committedThroughStep3,
  requestedVersion:step4.version,verify:entry=>{
    step3VerifierCalls++;
    assert.strictEqual(entry.version,step3.version);
    return true;
  },mutations:recoveryMutations});
assert.strictEqual(step3Gate.recovered.status,'COMMITTED_VERIFICATION_RECOVERED');
assert.strictEqual(step3Gate.recovered.next.version,step4.version);
assert.strictEqual(step3Gate.eligible.selected.version,step4.version);
assert.deepStrictEqual(recoveryMutationCalls,{sql:0,insert:0,update:0,delete:0,ledger:0});
assert.strictEqual(JSON.stringify(committedThroughStep3),authoritativeHistoryBefore);

const firstReadOnlyRecovery=recoverThenPlan({committedHistory:committedThroughStep3,
  requestedVersion:step4.version,verify:()=>true,mutations:recoveryMutations});
const secondReadOnlyRecovery=recoverThenPlan({committedHistory:committedThroughStep3,
  requestedVersion:step4.version,verify:()=>true,mutations:recoveryMutations});
assert.deepStrictEqual(firstReadOnlyRecovery,secondReadOnlyRecovery,
  'Repeated recovery against unchanged state was not deterministic');
assert.strictEqual(firstReadOnlyRecovery.recovered.status,'COMMITTED_VERIFICATION_RECOVERED');
assert.deepStrictEqual(recoveryMutationCalls,{sql:0,insert:0,update:0,delete:0,ledger:0});
assert.strictEqual(JSON.stringify(committedThroughStep3),authoritativeHistoryBefore);

['supabase db push','supabase db push --include-all','supabase migration up',
  'supabase migration up --include-all','supabase --include-all migration up',
  'npx supabase db push','npx supabase migration up','/usr/local/bin/supabase db push',
  './node_modules/.bin/supabase migration up','"supabase" db push',
  'supabase --debug db --include-all push','psql -f supabase/migrations/all.sql',
  'psql -f ./supabase/migrations/one.sql','supabase migration repair --status applied'].forEach(command=>
  assert.throws(()=>commandGuard.guard(command,commandGuard.productionRef),/FORBIDDEN/));
assert.strictEqual(commandGuard.guard('supabase db push','gppwltrifgfxrkzvvxoe'),true);
assert.strictEqual(commandGuard.guard('node scripts/production-migration-runner.js --dry-run',
  commandGuard.productionRef),true);

const historyContract={columns:manifest.migrationHistoryEvidence.columns,
  constraints:manifest.migrationHistoryEvidence.constraints,
  sampleDigests:[{version:'1',name:'baseline',digest:'0123456789abcdef0123456789abcdef'}]};
const historyManifest={...manifest};
assert.strictEqual(runner.assertHistoryCompatibility(historyManifest,historyContract),true);
assert.throws(()=>runner.assertHistoryCompatibility(
  {...manifest,migrationHistoryContractSha256:null},historyContract),/CONTRACT_NOT_CONFIGURED/);
assert.throws(()=>runner.assertHistoryCompatibility(historyManifest,{...historyContract,columns:[]}),
  /CONTRACT_MISMATCH/);

const committedFailure=runner.committedPostVerificationFailure(manifest.migrations[0],
  new Error('simulated verifier failure'));
assert.strictEqual(committedFailure.code,'COMMITTED_POST_VERIFICATION_FAILED');
assert.deepStrictEqual(committedFailure.committed,{version:manifest.migrations[0].version,
  name:manifest.migrations[0].name});
assert.match(committedFailure.message,/COMMITTED_POST_VERIFICATION_FAILED/);
assert.match(committedFailure.recovery,/READ_ONLY_DIAGNOSIS.*NO_REPLAY/);

function assertSubstantiveVerifierSource(source){
  assert.match(source,/pg_(?:proc|constraint|indexes)|information_schema|aclexplode|has_function_privilege/);
  assert.match(source,/then 'PASS' else 'BLOCKED'/);
}
assert.throws(()=>assertSubstantiveVerifierSource(
  "select case when exists(select 1 from supabase_migrations.schema_migrations) then 'PASS' else 'BLOCKED' end;"));

manifest.migrations.slice(1).forEach(entry=>{
  const verifier=fs.readFileSync(path.join(dir,entry.verifier),'utf8');
  const preflight=fs.readFileSync(path.join(dir,entry.preflight),'utf8');
  assert.match(verifier,/Independent read-only resulting-contract verifier/);
  assertSubstantiveVerifierSource(verifier);
  assert.doesNotMatch(verifier,/^\s*(?:insert|update|delete|alter|create|drop|grant|revoke)\b/im);
  assert.match(preflight,/Independent read-only predecessor-contract preflight/);
  assert.match(preflight,/md5\(coalesce\(array_to_string\(statements/);
  assert.doesNotMatch(preflight,/^\s*(?:insert|update|delete|alter|create|drop|grant|revoke)\b/im);
});

const finalEntry=manifest.migrations.at(-1);
const finalSql=fs.readFileSync(path.join(dir,finalEntry.file),'utf8');
const finalPreflight=fs.readFileSync(path.join(dir,finalEntry.preflight),'utf8');
const finalVerifier=fs.readFileSync(path.join(dir,finalEntry.verifier),'utf8');
assert.match(finalSql,/PRODUCTION_ACTIVATION_EXACT_FULL_LINEAGE_REQUIRED/);
assert.match(finalSql,/PRODUCTION_ACTIVATION_COMPLETE_SECURITY_CONTRACT_REQUIRED/);
assert.match(finalSql,/device_possession_challenge_consumers/);
assert.match(finalSql,/system_owner_credential_bootstrap_authorizations/);
assert.match(finalSql,/system_owner_credential_recovery_authorizations/);
manifest.migrations.slice(0,-1).forEach(entry=>{
  assert.match(finalSql,new RegExp(entry.version));
  assert.match(finalPreflight,new RegExp(entry.version));
});
assert.match(finalSql,/source_challenge_purpose/);
assert.match(finalSql,/expected_challenge_purpose/);
assert.match(finalSql,/5059f8c84bc709b10cdc258660de52b9/);
assert.match(finalVerifier,/expected_challenge_purpose/);
assert.strictEqual((finalSql.match(/^update public\.webauthn_privileged_device_feature/gmi)||[]).length,1);
assert.doesNotMatch(finalSql,/^\s*(?:insert|delete|merge|truncate)\b/im);

const grantEntry=manifest.migrations.find(entry=>entry.version==='20260828145000');
const grantSql=fs.readFileSync(path.join(dir,grantEntry.file),'utf8');
const grantPreflight=fs.readFileSync(path.join(dir,grantEntry.preflight),'utf8');
const grantVerifier=fs.readFileSync(path.join(dir,grantEntry.verifier),'utf8');
assert.strictEqual(grantEntry.intentionalDelta,
  'PRODUCTION_OPTIONAL_HISTORICAL_RLS_AUTO_ENABLE_ABSENCE');
assert.match(grantSql,/to_regprocedure\('public\.rls_auto_enable\(\)'\) is not null/);
assert.match(grantSql,/execute 'revoke execute on function public\.rls_auto_enable\(\)/);
assert.doesNotMatch(grantSql,/create(?: or replace)? function public\.rls_auto_enable/i);
assert.strictEqual((grantSql.match(/^grant\b/gmi)||[]).length,0);
assert.match(grantPreflight,/Approved Production evidence expects absence/);
assert.match(grantVerifier,/acl\.grantee=0/);
assert.doesNotMatch(grantVerifier,/has_function_privilege\('public'/i);
assert.doesNotMatch(finalVerifier,/has_function_privilege\('public'/i);

const before=fs.readFileSync(path.join(dir,'manifest.json'),'utf8');
const inspection=runner.plan({target:manifest.productionProjectRef,
  version:manifest.migrations[0].version,history});
assert.strictEqual(inspection.selected.version,manifest.migrations[0].version);
assert.strictEqual(fs.readFileSync(path.join(dir,'manifest.json'),'utf8'),before,
  'offline dry-run planning mutated repository state');

console.log('production migration stream architecture tests: passed');
