const fs=require('fs');
const os=require('os');
const path=require('path');
const crypto=require('crypto');
const childProcess=require('child_process');

const root=path.join(__dirname,'..');
const streamDir=path.join(root,'supabase','production-migrations');
const manifestPath=path.join(streamDir,'manifest.json');
const catalogSnapshotPath=path.join(root,'audit','phase-2al','catalog-snapshot.sql');
const catalogConstantsPath=path.join(streamDir,'catalog-contracts.json');
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const readManifest=()=>JSON.parse(fs.readFileSync(manifestPath,'utf8'));
const readCatalogConstants=()=>JSON.parse(fs.readFileSync(catalogConstantsPath,'utf8'));

function validateManifest(manifest=readManifest()){
  if(manifest.schemaVersion!==1||manifest.normalSupabaseBulkCommandsPermitted!==false)
    throw new Error('PRODUCTION_MANIFEST_SCHEMA_INVALID');
  const versions=new Set();
  const catalogConstants=readCatalogConstants();
  if(catalogConstants.schema!=='PHASE_2CG_CATALOG_CONTRACTS_V1')
    throw new Error('PRODUCTION_CATALOG_CONSTANTS_REQUIRED');
  let previous=manifest.initialPredecessor;
  for(const entry of manifest.migrations){
    if(!/^\d{14}$/.test(entry.version)||versions.has(entry.version))
      throw new Error('PRODUCTION_MANIFEST_VERSION_INVALID');
    if(entry.predecessor.version!==previous.version||entry.predecessor.name!==previous.name)
      throw new Error('PRODUCTION_MANIFEST_ORDER_INVALID');
    const index=manifest.migrations.indexOf(entry);
    if(!catalogConstants.states[catalogConstants.labels[index]]
      ||!catalogConstants.states[catalogConstants.labels[index+1]])
      throw new Error('PRODUCTION_CATALOG_STATE_INVALID');
    const sql=fs.readFileSync(path.join(streamDir,entry.file),'utf8');
    if(sha(sql)!==entry.productionSha256) throw new Error('PRODUCTION_MIGRATION_HASH_MISMATCH');
    const verifier=fs.readFileSync(path.join(streamDir,entry.verifier),'utf8');
    if(sha(verifier)!==entry.verifierSha256) throw new Error('PRODUCTION_VERIFIER_HASH_MISMATCH');
    const preflight=fs.readFileSync(path.join(streamDir,entry.preflight),'utf8');
    if(sha(preflight)!==entry.preflightSha256) throw new Error('PRODUCTION_PREFLIGHT_HASH_MISMATCH');
    if(entry.sourceCanonicalPath){
      const canonical=fs.readFileSync(path.join(root,entry.sourceCanonicalPath),'utf8');
      if(sha(canonical)!==entry.canonicalSourceSha256)
        throw new Error('PRODUCTION_CANONICAL_HASH_MISMATCH');
    }
    versions.add(entry.version); previous={version:entry.version,name:entry.name};
  }
  if(manifest.migrations.filter(x=>x.featureActivationPermitted).length!==1
    ||!manifest.migrations.at(-1).featureActivationPermitted)
    throw new Error('PRODUCTION_ACTIVATION_BOUNDARY_INVALID');
  return manifest;
}

function assertCatalogContract(manifest,label,evidence){
  const constants=readCatalogConstants();
  const expected=constants.states[label];
  if(!expected||!evidence||!evidence.hashes||!evidence.components)
    throw new Error('PRODUCTION_CATALOG_EVIDENCE_UNAVAILABLE');
  for(const component of ['columns','constraints','indexes','triggers','functions','security'])
    if(evidence.hashes[component]!==expected[component])
      throw new Error(`PRODUCTION_CATALOG_${component.toUpperCase()}_MISMATCH`);
  if(evidence.combined_sha256!==expected.combined)
    throw new Error('PRODUCTION_CATALOG_COMBINED_MISMATCH');
  const identities=constants.productionSemanticIdentities;
  const functionGrantees=new Set(identities.functionAclGrantees);
  const relationGrantees=new Set(identities.relationAclGrantees);
  const policyRoles=new Set(identities.policyRoles);
  for(const record of evidence.components.functions){
    if(record.owner!==identities.functionOwner)
      throw new Error('PRODUCTION_FUNCTION_OWNER_MISMATCH');
    for(const acl of record.acl){
      if(acl.grantor!==identities.aclGrantor)
        throw new Error('PRODUCTION_FUNCTION_ACL_GRANTOR_MISMATCH');
      if(!functionGrantees.has(acl.grantee))
        throw new Error('PRODUCTION_FUNCTION_ACL_GRANTEE_MISMATCH');
    }
  }
  for(const record of evidence.components.security){
    if(record.owner!==identities.relationOwner)
      throw new Error('PRODUCTION_RELATION_OWNER_MISMATCH');
    for(const acl of record.acl){
      if(acl.grantor!==identities.aclGrantor)
        throw new Error('PRODUCTION_RELATION_ACL_GRANTOR_MISMATCH');
      if(!relationGrantees.has(acl.grantee))
        throw new Error('PRODUCTION_RELATION_ACL_GRANTEE_MISMATCH');
    }
    for(const policy of record.policies) for(const role of policy.roles)
      if(!policyRoles.has(role)) throw new Error('PRODUCTION_POLICY_ROLE_MISMATCH');
  }
  return true;
}

function catalogLabelForEntry(manifest,entry,after=false){
  const index=manifest.migrations.findIndex(item=>item.version===entry.version);
  if(index<0) throw new Error('PRODUCTION_CATALOG_STATE_INVALID');
  return readCatalogConstants().labels[index+(after?1:0)];
}

function assertTarget(manifest,target){
  if(!target) throw new Error('PRODUCTION_PROJECT_REF_REQUIRED');
  if(manifest.forbiddenProjectRefs.includes(target)) throw new Error('DEVELOPMENT_PROJECT_FORBIDDEN');
  if(target!==manifest.productionProjectRef) throw new Error('WRONG_PRODUCTION_PROJECT');
}

function identityQuery(){
  return `select json_build_object(
    'databaseName',current_database(),
    'systemIdentifier',(select system_identifier::text from pg_control_system()),
    'serverAddress',coalesce(inet_server_addr()::text,''),
    'serverPort',inet_server_port(),
    'postgresMajor',current_setting('server_version_num')::integer/10000
  )::text`;
}

function inspectDatabaseIdentity(dbUrl){
  return JSON.parse(psql(dbUrl,['--tuples-only','--no-align','--command',identityQuery()]));
}

function assertDatabaseIdentity(manifest,target,identity){
  assertTarget(manifest,target);
  const expected=manifest.productionDatabaseIdentity;
  if(!expected||!expected.systemIdentifier)
    throw new Error('PRODUCTION_DATABASE_IDENTITY_NOT_CONFIGURED_READONLY_PROOF_REQUIRED');
  if(!identity||!identity.systemIdentifier)
    throw new Error('PRODUCTION_DATABASE_IDENTITY_UNAVAILABLE');
  if(String(identity.systemIdentifier)!==String(expected.systemIdentifier)
    ||identity.databaseName!==expected.databaseName
    ||Number(identity.postgresMajor)!==Number(expected.postgresMajor))
    throw new Error('PRODUCTION_DATABASE_IDENTITY_MISMATCH');
  return true;
}

function historyContractQuery(){
  return `with columns as (
    select json_agg(json_build_object('ordinal',ordinal_position,'name',column_name,'type',data_type,
      'udtSchema',udt_schema,'udtName',udt_name,'nullable',is_nullable='YES',
      'default',column_default,'identity',coalesce(identity_generation,''),'generated',is_generated)
      order by ordinal_position) value
    from information_schema.columns
    where table_schema='supabase_migrations' and table_name='schema_migrations'
  ), constraints as (
    select json_agg(json_build_object('name',c.conname,'type',c.contype,
      'definition',pg_get_constraintdef(c.oid,true)) order by c.conname) value
    from pg_constraint c where c.conrelid=to_regclass('supabase_migrations.schema_migrations')
  ) select json_build_object('columns',columns.value,'constraints',constraints.value,
    'sampleDigests',(select coalesce(json_agg(json_build_object('version',version,
      'name',name,'digest',md5(coalesce(array_to_string(statements,E'\\n'),'')))
      order by version),'[]'::json) from supabase_migrations.schema_migrations))::text
    from columns,constraints`;
}

function inspectHistoryContract(dbUrl){
  return JSON.parse(psql(dbUrl,['--tuples-only','--no-align','--command',historyContractQuery()]));
}

function stableJson(value){
  if(Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if(value&&typeof value==='object') return `{${Object.keys(value).sort().map(key=>
    `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

function assertHistoryCompatibility(manifest,contract){
  if(!manifest.migrationHistoryContractSha256)
    throw new Error('PRODUCTION_MIGRATION_HISTORY_CONTRACT_NOT_CONFIGURED_READONLY_PROOF_REQUIRED');
  if(!contract||!Array.isArray(contract.columns)||!Array.isArray(contract.constraints)
    ||!Array.isArray(contract.sampleDigests)
    ||contract.sampleDigests.some(row=>!row.version||!row.name||!/^\w{32}$/.test(row.digest||'')))
    throw new Error('PRODUCTION_MIGRATION_HISTORY_CONTRACT_UNAVAILABLE');
  const evidence=manifest.migrationHistoryEvidence;
  if(!evidence||sha(JSON.stringify(evidence.columns)+JSON.stringify(evidence.constraints))
    !==manifest.migrationHistoryContractSha256)
    throw new Error('PRODUCTION_MIGRATION_HISTORY_EVIDENCE_HASH_MISMATCH');
  if(stableJson({columns:contract.columns,constraints:contract.constraints})
    !==stableJson({columns:evidence.columns,constraints:evidence.constraints}))
    throw new Error('PRODUCTION_MIGRATION_HISTORY_CONTRACT_MISMATCH');
  return true;
}

function selectNext(manifest,version,history){
  const entry=manifest.migrations.find(item=>item.version===version);
  if(!entry) throw new Error('OUT_OF_MANIFEST_MIGRATION');
  if(history.some(row=>row.version===entry.version)) throw new Error('PRODUCTION_MIGRATION_REPLAY_FORBIDDEN');
  const latest=history.at(-1);
  if(!latest||latest.version!==entry.predecessor.version||latest.name!==entry.predecessor.name)
    throw new Error('PRODUCTION_MIGRATION_SKIP_FORBIDDEN');
  return entry;
}

function historyQuery(){
  return "select coalesce(json_agg(json_build_object('version',version,'name',name,'digest',md5(coalesce(array_to_string(statements,E'\\n'),''))) order by version)::text,'[]') from supabase_migrations.schema_migrations";
}

function psql(dbUrl,args,input){
  const result=childProcess.spawnSync('psql',['--no-psqlrc','--set','ON_ERROR_STOP=1','--dbname',dbUrl,...args],
    {encoding:'utf8',input});
  if(result.status!==0) throw new Error(`PSQL_FAILED: ${result.stderr||result.stdout}`);
  return result.stdout.trim();
}

function inspectHistory(dbUrl){
  return JSON.parse(psql(dbUrl,['--tuples-only','--no-align','--command',historyQuery()]));
}

function inspectCatalogContract(dbUrl){
  const output=psql(dbUrl,['--tuples-only','--no-align','--file',catalogSnapshotPath]);
  const line=output.split(/\r?\n/).filter(value=>value.startsWith('{')).at(-1);
  if(!line) throw new Error('PRODUCTION_CATALOG_EVIDENCE_UNAVAILABLE');
  return JSON.parse(line);
}

function verifyLatestCommitted(manifest,history,verify){
  const applied=[];
  for(const entry of manifest.migrations){
    const row=history.find(item=>item.version===entry.version);
    if(!row) break;
    if(row.name!==entry.name) throw new Error('PRODUCTION_COMMITTED_HISTORY_NAME_MISMATCH');
    const expectedDigest=crypto.createHash('md5').update(
      fs.readFileSync(path.join(streamDir,entry.file),'utf8')).digest('hex');
    if(row.digest!==expectedDigest) throw new Error('PRODUCTION_COMMITTED_HISTORY_DIGEST_MISMATCH');
    applied.push(entry);
  }
  if(history.some(row=>manifest.migrations.some(entry=>entry.version===row.version)
    &&!applied.some(entry=>entry.version===row.version)))
    throw new Error('PRODUCTION_COMMITTED_HISTORY_SEQUENCE_MISMATCH');
  const latest=applied.at(-1);
  if(!latest) return {status:'NO_COMMITTED_PRODUCTION_MIGRATION',latest:null};
  const passed=verify(latest);
  return {status:passed?'COMMITTED_VERIFICATION_RECOVERED':'COMMITTED_POST_VERIFICATION_FAILED',
    latest:{version:latest.version,name:latest.name},next:manifest.migrations[applied.length]||null};
}

function runReadOnlyCheck(dbUrl,relative,expectedPrefix){
  const output=psql(dbUrl,['--tuples-only','--no-align','--field-separator','|',
    '--file',path.join(streamDir,relative)]);
  const line=output.split(/\r?\n/).filter(Boolean).at(-1)||'';
  if(!line.startsWith(expectedPrefix)) throw new Error(`PRODUCTION_READONLY_CHECK_FAILED: ${line}`);
  return line;
}

function dollarQuote(value){
  let tag='$production_sql$';
  while(value.includes(tag)) tag=tag.replace('$','$x');
  return `${tag}${value}${tag}`;
}

function buildTransaction(entry){
  const sql=fs.readFileSync(path.join(streamDir,entry.file),'utf8');
  return `begin;\n${sql}\ninsert into supabase_migrations.schema_migrations(version,name,statements)\nvalues('${entry.version}','${entry.name}',array[${dollarQuote(sql)}]::text[]);\ncommit;\n`;
}

function plan({target,version,history}){
  const manifest=validateManifest(); assertTarget(manifest,target);
  const entry=selectNext(manifest,version,history);
  return {target,currentHistory:history,expectedPredecessor:entry.predecessor,
    selected:{version:entry.version,name:entry.name,file:entry.file},
    productionSha256:entry.productionSha256,canonicalSourcePath:entry.sourceCanonicalPath,
    canonicalSourceSha256:entry.canonicalSourceSha256,intentionalDelta:entry.intentionalDelta,
    expectedWebAuthnBefore:entry.expectedWebAuthnBefore,
    expectedWebAuthnAfter:entry.expectedWebAuthnAfter,
    expectedDeviceEnforcementBefore:entry.expectedDeviceEnforcementBefore,
    expectedDeviceEnforcementAfter:entry.expectedDeviceEnforcementAfter,
    exactMutation:entry.intentionalDelta==='PRODUCTION_FINAL_ACTIVATION'
      ?'webauthn_privileged_device_feature.enabled: false -> true'
      :`execute exactly ${entry.file}; record exactly one history row`,
    preflightArtifact:entry.preflight};
}

function parseArgs(argv){
  const result={dryRun:false,apply:false};
  for(let i=0;i<argv.length;i++){
    if(argv[i]==='--dry-run') result.dryRun=true;
    else if(argv[i]==='--apply') result.apply=true;
    else if(argv[i]==='--version'){
      if(result.version) throw new Error('DUPLICATE_VERSION_ARGUMENT');
      result.version=argv[++i];
    }else if(argv[i]==='--project-ref'){
      if(result.target) throw new Error('DUPLICATE_PROJECT_ARGUMENT');
      result.target=argv[++i];
    }
    else throw new Error(`UNSUPPORTED_ARGUMENT: ${argv[i]}`);
  }
  if(result.dryRun===result.apply) throw new Error('EXACTLY_ONE_MODE_REQUIRED');
  return result;
}

function main(argv=process.argv.slice(2)){
  const args=parseArgs(argv);
  const dbUrl=process.env.PRODUCTION_DB_URL;
  if(!dbUrl) throw new Error('PRODUCTION_DB_URL_REQUIRED_FOR_HISTORY_INSPECTION');
  const manifest=validateManifest();
  assertTarget(manifest,args.target);
  const identity=inspectDatabaseIdentity(dbUrl);
  assertDatabaseIdentity(manifest,args.target,identity);
  const historyContract=inspectHistoryContract(dbUrl);
  assertHistoryCompatibility(manifest,historyContract);
  const history=inspectHistory(dbUrl);
  const recovery=verifyLatestCommitted(manifest,history,entry=>{
    const expected=`PASS|${entry.expectedWebAuthnAfter?'t':'f'}|${entry.expectedDeviceEnforcementAfter?'t':'f'}`;
    try{
      runReadOnlyCheck(dbUrl,entry.verifier,expected);
      assertCatalogContract(manifest,catalogLabelForEntry(manifest,entry,true),inspectCatalogContract(dbUrl));
      return true;
    }catch(error){return false;}
  });
  if(recovery.status==='COMMITTED_POST_VERIFICATION_FAILED'){
    if(args.dryRun){console.log(JSON.stringify({...recovery,mode:'DRY_RUN_NO_MUTATION'},null,2));return;}
    throw committedPostVerificationFailure(
      manifest.migrations.find(entry=>entry.version===recovery.latest.version),
      new Error('LATEST_COMMITTED_VERIFIER_BLOCKED'));
  }
  const inspection=plan({target:args.target,version:args.version,history});
  const entry=selectNext(manifest,args.version,history);
  assertCatalogContract(manifest,catalogLabelForEntry(manifest,entry),inspectCatalogContract(dbUrl));
  const preflightResult=runReadOnlyCheck(dbUrl,entry.preflight,'PASS');
  if(args.dryRun){ console.log(JSON.stringify({...inspection,recovery,preflightResult,
    mode:'DRY_RUN_NO_MUTATION'},null,2)); return; }
  if(process.env.PRODUCTION_MIGRATION_AUTHORIZATION!==args.version)
    throw new Error('EXPLICIT_SINGLE_MIGRATION_AUTHORIZATION_REQUIRED');
  psql(dbUrl,[],buildTransaction(entry));
  try{
    const after=inspectHistory(dbUrl);
    const recorded=after.filter(row=>row.version===entry.version&&row.name===entry.name);
    if(recorded.length!==1) throw new Error('PRODUCTION_HISTORY_POSTVERIFY_FAILED');
    const storedDigest=psql(dbUrl,['--tuples-only','--no-align','--command',
      `select md5(coalesce(array_to_string(statements,E'\\n'),'')) from supabase_migrations.schema_migrations where version='${entry.version}'`]);
    const expectedDigest=crypto.createHash('md5').update(
      fs.readFileSync(path.join(streamDir,entry.file),'utf8')).digest('hex');
    if(storedDigest!==expectedDigest) throw new Error('PRODUCTION_HISTORY_CONTENT_DIGEST_MISMATCH');
    const expectedPost=`PASS|${entry.expectedWebAuthnAfter?'t':'f'}|${entry.expectedDeviceEnforcementAfter?'t':'f'}`;
    runReadOnlyCheck(dbUrl,entry.verifier,expectedPost);
    assertCatalogContract(manifest,catalogLabelForEntry(manifest,entry,true),inspectCatalogContract(dbUrl));
  }catch(cause){ throw committedPostVerificationFailure(entry,cause); }
  console.log(JSON.stringify({status:'APPLIED_ONE_AND_STOPPED',version:entry.version,name:entry.name}));
}

function committedPostVerificationFailure(entry,cause){
  const error=new Error(`COMMITTED_POST_VERIFICATION_FAILED: ${entry.version} ${entry.name}: ${cause.message}`);
  error.code='COMMITTED_POST_VERIFICATION_FAILED';
  error.committed={version:entry.version,name:entry.name};
  error.recovery='READ_ONLY_DIAGNOSIS_AND_EXPLICIT_RECOVERY_AUTHORIZATION_REQUIRED_NO_REPLAY';
  return error;
}

if(require.main===module){try{main();}catch(error){console.error(error.message);process.exitCode=1;}}
module.exports={validateManifest,assertTarget,assertDatabaseIdentity,assertHistoryCompatibility,
  selectNext,plan,parseArgs,buildTransaction,identityQuery,historyContractQuery,stableJson,
  committedPostVerificationFailure,verifyLatestCommitted,assertCatalogContract,
  inspectCatalogContract,catalogLabelForEntry};
