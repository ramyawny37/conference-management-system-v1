const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const cp=require('child_process');
const identityPolicy=require('./lab-derivation-identity');
const {checkedStdout,parseJsonEvidence}=require('./evidence-json');

const root=path.resolve(__dirname,'../..');
const streamDir=path.join(root,'supabase/production-migrations');
const manifest=JSON.parse(fs.readFileSync(path.join(streamDir,'manifest.json'),'utf8'));
const psql=process.env.PHASE2AL_PSQL;
const url=process.env.PHASE2AL_LAB_DATABASE_URL;
const outputDir=process.env.PHASE2AL_EVIDENCE_DIR;
const startVersion=process.env.PHASE2AL_START_VERSION||null;
const evidenceOnly=process.env.PHASE2AL_EVIDENCE_ONLY==='true';
const fail=message=>{throw new Error(`PHASE_2AL_DERIVATION_REFUSED: ${message}`);};
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const run=(args,input)=>{
  const result=cp.spawnSync(psql,['-X','-v','ON_ERROR_STOP=1','--dbname',url,...args],
    {cwd:root,encoding:'utf8',input});
  try{return checkedStdout(result,'PSQL').trim();}
  catch(error){fail(error.message);}
};
const dollarQuote=value=>{
  let tag='$phase2al_history$';
  while(value.includes(tag)) tag=tag.replace('$','$x');
  return `${tag}${value}${tag}`;
};
if(!psql||!url||!outputDir) fail('ENV_REQUIRED');
if(!identityPolicy.isApprovedLabUrl(url)) fail('LOCAL_ONLY');
const identity=parseJsonEvidence(run(['-At','-c',`select json_build_object('database',current_database(),
  'system_identifier',(select system_identifier::text from pg_control_system()),
  'major',current_setting('server_version_num')::integer/10000,
  'address',inet_server_addr()::text,'currentUser',current_user,
  'sessionUser',session_user,'databaseOwner',pg_get_userbyid(d.datdba))::text
  from pg_database d where d.datname=current_database()`]),{label:'IDENTITY',expectedType:'object'});
const identityFailure=identityPolicy.canonicalLabIdentityFailure(identity);
if(identityFailure) fail(identityFailure);
if(identity.system_identifier==='7662742571317219726') fail('IDENTITY');
fs.mkdirSync(outputDir,{recursive:true});

function snapshot(label){
  const raw=run(['-At','-f',path.join(root,'audit/phase-2al/catalog-snapshot.sql')]);
  const value=parseJsonEvidence(raw.split(/\r?\n/).filter(line=>line.startsWith('{')).at(-1)||'',
    {label:`SNAPSHOT_${label}`,expectedType:'object'});
  value.database='PHASE2AL_NORMALIZED_DATABASE';
  const normalized=JSON.stringify(value);
  fs.writeFileSync(path.join(outputDir,`${label}.json`),normalized+'\n');
  return {label,...value.hashes,combined:value.combined_sha256,file_sha256:sha(normalized+'\n')};
}
if(evidenceOnly&&startVersion!==null) fail('EVIDENCE_ONLY_START_VERSION_FORBIDDEN');
const startIndex=startVersion===null?0:manifest.migrations.findIndex(entry=>entry.version===startVersion);
if(!evidenceOnly&&startIndex<0) fail('START_VERSION');
if(!evidenceOnly){
  const initialLabel=startIndex===0?'00-baseline':
    `${String(startIndex).padStart(2,'0')}-${manifest.migrations[startIndex-1].version}`;
  snapshot(initialLabel);
  for(let index=startIndex;index<manifest.migrations.length;index++){
  const entry=manifest.migrations[index];
  const sql=fs.readFileSync(path.join(streamDir,entry.file),'utf8');
  const preflight=fs.readFileSync(path.join(streamDir,entry.preflight),'utf8');
  const verifier=fs.readFileSync(path.join(streamDir,entry.verifier),'utf8');
  if(sha(sql)!==entry.productionSha256||sha(preflight)!==entry.preflightSha256
    ||sha(verifier)!==entry.verifierSha256) fail(`MANIFEST_HASH_${entry.version}`);
  const pre=run(['-At'],preflight).split(/\r?\n/).filter(Boolean).at(-1);
  if(!pre.startsWith('PASS')) fail(`PREFLIGHT_${entry.version}_${pre}`);
  run([],`begin;\n${sql}\ninsert into supabase_migrations.schema_migrations(version,name,statements)\n`+
    `values('${entry.version}','${entry.name}',array[${dollarQuote(sql)}]::text[]);\ncommit;\n`);
  const verified=run(['-At'],verifier).split(/\r?\n/).filter(Boolean).at(-1);
  if(!verified.startsWith('PASS')) fail(`VERIFIER_${entry.version}_${verified}`);
  const flags=run(['-At','-F','|','-c',`select enabled,enforcement_enabled
    from public.webauthn_privileged_device_feature cross join public.device_authorization_enforcement`]);
  const expected=index===manifest.migrations.length-1?'t|f':'f|f';
  if(flags!==expected) fail(`FLAGS_${entry.version}_${flags}`);
  snapshot(`${String(index+1).padStart(2,'0')}-${entry.version}`);
  console.log(`${entry.version}|PASS|${flags}`);
  }
}
const results=fs.readdirSync(outputDir).filter(file=>/^\d\d-.*\.json$/.test(file)).sort().map(file=>{
  const value=parseJsonEvidence(fs.readFileSync(path.join(outputDir,file),'utf8'),
    {label:`SNAPSHOT_FILE_${file}`,expectedType:'object'});
  return {label:file.replace(/\.json$/,''),...value.hashes,combined:value.combined_sha256,
    file_sha256:sha(JSON.stringify(value)+'\n')};
});
const history=parseJsonEvidence(run(['-At','-c',`select coalesce(json_agg(json_build_object(
  'version',version,'name',name,'statements_md5',md5(coalesce(array_to_string(statements,E'\\n'),'')))
  order by version),'[]'::json)::text from supabase_migrations.schema_migrations`]),
  {label:'HISTORY',expectedType:'array'});
const constraints6204=parseJsonEvidence(run(['-At','-c',`select coalesce(json_agg(json_build_object('relation',c.relname,
    'name',x.conname,'definition',pg_get_constraintdef(x.oid,true)) order by c.relname,x.conname),'[]'::json)::text
    from pg_constraint x join pg_class c on c.oid=x.conrelid where x.conname in
    ('device_security_credentials_non_backup_policy','privileged_device_audit_webauthn_policy')`]),
  {label:'CONSTRAINTS_6_20_4',expectedType:'array',allowEmpty:false});
if(constraints6204.length!==2) fail(`CONSTRAINTS_6_20_4_CARDINALITY_${constraints6204.length}`);
const step12Acl=parseJsonEvidence(run(['-At','-c',`select coalesce(json_agg(json_build_object('signature',p.oid::regprocedure::text,
    'public',has_function_privilege('public',p.oid,'execute'),'anon',has_function_privilege('anon',p.oid,'execute'),
    'authenticated',has_function_privilege('authenticated',p.oid,'execute'),'service_role',has_function_privilege('service_role',p.oid,'execute'))
    order by p.oid::regprocedure::text),'[]'::json)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('rls_auto_enable','enforce_launch_conference_member_contract',
    'prevent_null_conference_organization','acquire_conference_lock','renew_conference_lock','release_conference_lock',
    'get_conference_lock','get_conference_section_lock','is_conference_member','has_conference_role','is_conference_owner',
    'complete_system_owner_pending_device_operation')`]),{label:'STEP12_ACL',expectedType:'array',allowEmpty:false});
const activation=parseJsonEvidence(run(['-At','-c',`select json_build_object('webauthn',enabled,
    'device_enforcement',enforcement_enabled)::text from public.webauthn_privileged_device_feature
    cross join public.device_authorization_enforcement`]),{label:'ACTIVATION',expectedType:'object'});
const evidence={identity,history,fingerprints:results,constraints_6_20_4:constraints6204,
  step12_acl:step12Acl,activation};
fs.writeFileSync(path.join(outputDir,'evidence.json'),JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify({status:'DERIVATION_COMPLETE',outputDir,fingerprints:results}));
