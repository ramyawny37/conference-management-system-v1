const assert=require('assert');
const fs=require('fs');
const path=require('path');

const root=path.join(__dirname,'..');
const dir=path.join(root,'supabase','production-migrations');
const artifacts=[
  'verify/20260828133000_production_credential_enrollment_expiry_default_alignment_6_20_2.sql',
  'preflight/20260828134000_production_system_owner_synced_passkey_policy_reconciliation_6_20_3.sql',
  'preflight/20260828150000_production_webauthn_privileged_device_final_activation.sql',
  'verify/20260828150000_production_webauthn_privileged_device_final_activation.sql',
  '20260828150000_production_webauthn_privileged_device_final_activation.sql',
].map(relative=>fs.readFileSync(path.join(dir,relative),'utf8'));

const exactSignature='begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)';
const obsoleteEnrollmentPredicate=`to_regprocedure('public.${exactSignature}') is not null and `
  +`position('now() + ''00:02:00''::interval' in pg_get_functiondef(`
  +`to_regprocedure('public.${exactSignature}')))>0`;
for(const artifact of artifacts){
  assert.match(artifact,new RegExp(exactSignature.replace(/[()]/g,'\\$&')));
  assert.match(artifact,/pg_get_function_result\(p\.oid\)='jsonb'/);
  assert.match(artifact,/l\.lanname='plpgsql'/);
  assert.match(artifact,/p\.prosecdef/);
  assert.match(artifact,/p\.provolatile='v'/);
  assert.match(artifact,/p\.proparallel='u'/);
  assert.match(artifact,/not p\.proisstrict/);
  assert.match(artifact,/search_path=pg_catalog, public/);
  assert.match(artifact,/p\.proowner=.*user_device_authorizations/s);
  assert.match(artifact,/acl\.grantee=0/);
  assert.match(artifact,/rolname='anon'/);
  assert.match(artifact,/rolname='authenticated'/);
  assert.match(artifact,/rolname='service_role'/);
  assert.match(artifact,/regexp_replace\(p\.prosrc,'\[\[:space:\]\]\+','','g'\)/);
  assert.match(artifact,/p_environment,now\(\)\+interval''2minutes''\)/);
  assert.ok(!artifact.includes(obsoleteEnrollmentPredicate));
}

const deviceChallengeSignature=
  'begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)';
const listingSignature=
  'complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)';
const step13Artifacts=artifacts.slice(2);
assert.notStrictEqual(exactSignature,deviceChallengeSignature);
assert.notStrictEqual(exactSignature,listingSignature);
for(const artifact of step13Artifacts){
  assert.ok(artifact.includes(`to_regprocedure('public.${deviceChallengeSignature}')`));
  assert.ok(artifact.includes(`to_regprocedure('public.${listingSignature}')`));
  assert.match(artifact,/p_environment,now\(\)\+interval''2minutes''\)returningidintochallenge_id/);
  assert.match(artifact,
    /p_environment,''SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY'',now\(\)\+interval''5minutes''\);/);
}

const canonicalBody=body=>body.replace(/[\s]+/g,'')
  .includes("p_environment,now()+interval'2minutes')");
const passes=value=>value.signature===exactSignature
  &&value.returnType==='jsonb'&&value.language==='plpgsql'&&value.securityDefiner
  &&value.volatility==='v'&&value.parallel==='u'&&!value.strict
  &&value.ownerControlled&&value.searchPath==='pg_catalog, public'
  &&!value.publicExecute&&!value.anonExecute&&!value.authenticatedExecute
  &&value.serviceRoleExecute&&canonicalBody(value.body);
const valid={signature:exactSignature,returnType:'jsonb',language:'plpgsql',securityDefiner:true,
  volatility:'v',parallel:'u',strict:false,ownerControlled:true,searchPath:'pg_catalog, public',
  publicExecute:false,anonExecute:false,authenticatedExecute:false,serviceRoleExecute:true,
  body:"values(..., p_environment, now() + interval '2 minutes')"};
assert.strictEqual(passes(valid),true);
assert.strictEqual(passes({...valid,body:"values(...,p_environment,now()+interval '2 minutes')"}),true);
[
  ['body',"values(...,p_environment,now()+interval '1 minute')"],
  ['body',"values(...,p_environment,now()+interval '3 minutes')"],
  ['body',"values(...,p_environment,statement_timestamp()+interval '2 minutes')"],
  ['body',"values(...,p_environment,clock_timestamp()+interval '2 minutes')"],
  ['body',"values(...,p_environment,now()+make_interval(mins=>2))"],
  ['signature','begin_system_owner_credential_enrollment()'],['returnType','text'],
  ['securityDefiner',false],['volatility','s'],['parallel','s'],['strict',true],
  ['ownerControlled',false],['searchPath','public'],['publicExecute',true],
  ['anonExecute',true],['authenticatedExecute',true],['serviceRoleExecute',false],
].forEach(([property,value])=>assert.strictEqual(passes({...valid,[property]:value}),false,property));

console.log('production shared 6.20.2 Step-4 verifier tests: passed');
