const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const cp=require('child_process');
const identityPolicy=require('./lab-derivation-identity');

const root=path.resolve(__dirname,'../..');
const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'baseline-order.json'),'utf8'));
const expectedFirst=[
  'supabase/migrations/20260728_3_3_0_online_schema.sql',
  'supabase/migrations/20260728_3_3_0_conflict_resolution.sql',
  'supabase/migrations/20260728_3_3_0_conference_locks.sql',
  'supabase/migrations/20260728_3_3_0_idempotent_conference_creation.sql'
];
const fail=message=>{throw new Error(`PHASE_2AL_BASELINE_REFUSED: ${message}`);};
const run=(command,args,input)=>{
  const result=cp.spawnSync(command,args,{cwd:root,encoding:'utf8',input,stdio:input===undefined?'inherit':['pipe','inherit','inherit']});
  if(result.status!==0) fail(`SQL_OR_COMMAND_FAILED status=${result.status}`);
};
const capture=(command,args)=>{
  const result=cp.spawnSync(command,args,{cwd:root,encoding:'utf8'});
  if(result.status!==0) fail(result.stderr||`COMMAND_FAILED status=${result.status}`);
  return result.stdout;
};
const md5=value=>crypto.createHash('md5').update(value).digest('hex');

function readCanonicalIdentity(){
  const raw=capture(psql,['-X','-At','-v','ON_ERROR_STOP=1','--dbname',url,'-c',
    `select json_build_object('database',current_database(),
      'major',current_setting('server_version_num')::integer/10000,
      'address',inet_server_addr()::text,'currentUser',current_user,
      'sessionUser',session_user,'databaseOwner',pg_get_userbyid(d.datdba))::text
     from pg_database d where d.datname=current_database()`]);
  try{return JSON.parse(raw);}
  catch(error){fail('IDENTITY_JSON');}
}

if(manifest.schema!=='PHASE_2AL_BASELINE_ORDER_V1'
  ||manifest.declaration!=='LAB_ONLY_NOT_PRODUCTION_MIGRATION_HISTORY'
  ||manifest.postgresMajor!==17||manifest.autoDiscoveryPermitted!==false) fail('MANIFEST_POLICY');
if(manifest.expectedMigrationCount!==41||manifest.migrations.length!==41) fail('WRONG_COUNT');
const keys=manifest.migrations.map(entry=>typeof entry==='string'?entry:entry.path);
if(new Set(keys).size!==keys.length) fail('DUPLICATE_ENTRY');
if(JSON.stringify(keys.slice(0,4))!==JSON.stringify(expectedFirst)) fail('WRONG_3_3_0_ORDER');
const fixture=path.join(root,manifest.fixture);
if(!fs.existsSync(fixture)) fail('MISSING_FIXTURE');
const identityFixture=path.join(root,manifest.bootstrapIdentityFixture||'');
if(!fs.existsSync(identityFixture)) fail('MISSING_BOOTSTRAP_IDENTITY_FIXTURE');
if(!Array.isArray(manifest.postMigrationCheckpoints)||manifest.postMigrationCheckpoints.length!==2)
  fail('CHECKPOINT_POLICY');
const expectedCheckpoints=[
  ['supabase/migrations/20260730_5_0_0_system_access_foundation.sql',
    'audit/phase-2al/post-5-0-bootstrap-approval-checkpoint.sql','LAB_ONLY_SYNTHETIC_BOOTSTRAP_IDENTITY'],
  ['supabase/migrations/20260801_5_4_1_device_guarded_rpc_foundation.sql',
    'audit/phase-2al/pre-5-4-2-legacy-acl-checkpoint.sql','LAB_ONLY_CANONICAL_5_4_2_INCOMING_ACL_CONTRACT']
];
manifest.postMigrationCheckpoints.forEach((checkpoint,index)=>{
  if(JSON.stringify([checkpoint.after,checkpoint.file,checkpoint.classification])
      !==JSON.stringify(expectedCheckpoints[index])||!fs.existsSync(path.join(root,checkpoint.file)))
    fail('CHECKPOINT_POLICY');
});
if(!Array.isArray(manifest.historicalSources)||manifest.historicalSources.length!==5)
  fail('HISTORICAL_SOURCE_POLICY');
const historicalBodies={};
for(const source of manifest.historicalSources){
  const body=capture('git',['show',source.gitSelector]);
  if(capture('git',['rev-parse',source.gitSelector]).trim()!==source.blob||md5(body)!==source.md5)
    fail(`HISTORICAL_SOURCE_INTEGRITY ${source.version}`);
  historicalBodies[source.variable]=body;
}
const preHistory=manifest.preHistoricalMigrationCheckpoint;
const postHistory=manifest.postHistoricalMigrationCheckpoint;
if(!preHistory||!postHistory||preHistory.before!==keys.at(-1)||postHistory.after!==keys.at(-1))
  fail('HISTORY_CHECKPOINT_ORDER');
for(const checkpoint of [preHistory,postHistory]){
  if(!checkpoint.classification.startsWith('LAB_ONLY_')
    ||!fs.existsSync(path.join(root,checkpoint.file))) fail('HISTORY_CHECKPOINT_POLICY');
}
const historyArgs=variables=>Object.entries(variables).flatMap(([name,value])=>['-v',`${name}=${value}`]);
for(const entry of manifest.migrations){
  if(typeof entry==='string'&&!fs.existsSync(path.join(root,entry))) fail(`MISSING_FILE ${entry}`);
  if(typeof entry!=='string'&&(!entry.gitSelector||entry.provenance!=='HISTORICAL_PRODUCTION_BODY'))
    fail('INVALID_HISTORICAL_SELECTOR');
}

const url=process.env.PHASE2AL_LAB_DATABASE_URL;
const psql=process.env.PHASE2AL_PSQL;
if(!url||!psql) fail('LAB_CONNECTION_ENV_REQUIRED');
if(!identityPolicy.isApprovedLabUrl(url)) fail('NON_LOCALHOST_OR_HOSTED_TARGET');
const identity=readCanonicalIdentity();
const identityFailure=identityPolicy.canonicalLabIdentityFailure(identity);
if(identityFailure) fail(identityFailure);

run(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url,'-f',fixture]);
run(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url,'-f',identityFixture]);
for(const entry of manifest.migrations){
  if(typeof entry==='string'){
    run(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url,'-f',path.join(root,entry)]);
    const checkpoint=manifest.postMigrationCheckpoints.find(item=>item.after===entry);
    if(checkpoint) run(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url,
      '-f',path.join(root,checkpoint.file)]);
  }
  else{
    const body=capture('git',['show',entry.gitSelector]);
    const digest=md5(body);
    if(digest!==entry.md5) fail(`HISTORICAL_6_19_HASH ${digest}`);
    run(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url,
      ...historyArgs({history_6_18_body:historicalBodies.history_6_18_body}),
      '-f',path.join(root,preHistory.file)]);
    run(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url],body);
    run(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url,
      ...historyArgs(historicalBodies),'-f',path.join(root,postHistory.file)]);
  }
}
console.log(JSON.stringify({status:'BASELINE_APPLIED_LAB_ONLY',count:keys.length,
  declaration:manifest.declaration}));
