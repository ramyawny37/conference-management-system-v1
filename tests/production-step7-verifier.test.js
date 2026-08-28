const assert=require('assert');
const fs=require('fs');
const path=require('path');

const root=path.join(__dirname,'..');
const dir=path.join(root,'supabase','production-migrations');
const artifacts=[
  'verify/20260828140000_production_webauthn_time_boundary_reconciliation_6_20_5.sql',
  'preflight/20260828141000_production_webauthn_verification_material_base64_reconciliation_6_20_6.sql',
  '20260828150000_production_webauthn_privileged_device_final_activation.sql',
  'preflight/20260828150000_production_webauthn_privileged_device_final_activation.sql',
  'verify/20260828150000_production_webauthn_privileged_device_final_activation.sql',
].map(relative=>fs.readFileSync(path.join(dir,relative),'utf8'));
const beginSignature='begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)';
const listingSignature='complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)';
const obsolete=[
  `to_regprocedure('public.${beginSignature}') is not null and position('now() + ''00:02:00''::interval'`,
  `to_regprocedure('public.${listingSignature}') is not null and position('now() + ''00:05:00''::interval'`,
];
for(const artifact of artifacts){
  [beginSignature,listingSignature].forEach(signature=>
    assert.match(artifact,new RegExp(signature.replace(/[()[\]]/g,'\\$&'))));
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
  assert.match(artifact,/p_environment,now\(\)\+interval''2minutes''\)returningidintochallenge_id/);
  assert.match(artifact,/p_environment,''SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY'',now\(\)\+interval''5minutes''\);/);
  assert.match(artifact,/require_system_owner_webauthn_actor/);
  assert.match(artifact,/challenges\.environment=p_environment/);
  obsolete.forEach(marker=>assert.ok(!artifact.includes(marker)));
}

const normalize=value=>value.replace(/[\s]+/g,'');
const canonicalBodies=(beginBody,listingBody)=>{
  const begin=normalize(beginBody),listing=normalize(listingBody);
  return begin.includes('credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,p_credential_id)')
    &&begin.includes("p_purposenotin('SYSTEM_OWNER_PENDING_DEVICE_LIST','SYSTEM_OWNER_PENDING_DEVICE_APPROVE','SYSTEM_OWNER_PENDING_DEVICE_REJECT')")
    &&begin.includes("p_environment,now()+interval'2minutes')returningidintochallenge_id")
    &&listing.includes('credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,p_credential_id)')
    &&listing.includes("challenges.purpose='SYSTEM_OWNER_PENDING_DEVICE_LIST'")
    &&listing.includes('challenges.environment=p_environment')
    &&listing.includes("p_environment,'SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY',now()+interval'5minutes');");
};
const passes=value=>value.beginSignature===beginSignature&&value.listingSignature===listingSignature
  &&value.returnType==='jsonb'&&value.language==='plpgsql'&&value.securityDefiner
  &&value.volatility==='v'&&value.parallel==='u'&&!value.strict&&value.ownerControlled
  &&value.searchPath==='pg_catalog, public'&&!value.publicExecute&&!value.anonExecute
  &&!value.authenticatedExecute&&value.serviceRoleExecute
  &&canonicalBodies(value.beginBody,value.listingBody);
const beginBody=`credential:=public.require_system_owner_webauthn_actor(
  p_actor_user_id,p_actor_device_id,p_credential_id);
  if p_purpose not in ('SYSTEM_OWNER_PENDING_DEVICE_LIST',
    'SYSTEM_OWNER_PENDING_DEVICE_APPROVE','SYSTEM_OWNER_PENDING_DEVICE_REJECT') then end if;
  values(...,p_environment,now()+interval '2 minutes') returning id into challenge_id;`;
const listingBody=`credential:=public.require_system_owner_webauthn_actor(
  p_actor_user_id,p_actor_device_id,p_credential_id);
  where challenges.purpose='SYSTEM_OWNER_PENDING_DEVICE_LIST'
    and challenges.environment=p_environment;
  values(...,p_environment,'SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY',
    now()+interval '5 minutes');`;
const valid={beginSignature,listingSignature,returnType:'jsonb',language:'plpgsql',
  securityDefiner:true,volatility:'v',parallel:'u',strict:false,ownerControlled:true,
  searchPath:'pg_catalog, public',publicExecute:false,anonExecute:false,
  authenticatedExecute:false,serviceRoleExecute:true,beginBody,listingBody};
assert.strictEqual(passes(valid),true);
[
  ['beginBody',beginBody.replace("interval '2 minutes'","interval '1 minute'")],
  ['beginBody',beginBody.replace("interval '2 minutes'","interval '3 minutes'")],
  ['beginBody',beginBody.replace('now()','statement_timestamp()')],
  ['beginBody',beginBody.replace('now()','clock_timestamp()')],
  ['beginBody',beginBody.replace('p_environment,now()','other_context,now()')],
  ['listingBody',listingBody.replace("interval '5 minutes'","interval '4 minutes'")],
  ['listingBody',listingBody.replace("interval '5 minutes'","interval '6 minutes'")],
  ['listingBody',listingBody.replace('now()','statement_timestamp()')],
  ['listingBody',listingBody.replace('now()','clock_timestamp()')],
  ['beginSignature','begin_system_owner_device_possession_challenge()'],
  ['listingSignature','complete_system_owner_pending_device_listing()'],['returnType','text'],
  ['securityDefiner',false],['volatility','s'],['parallel','s'],['strict',true],
  ['ownerControlled',false],['searchPath','public'],['publicExecute',true],
  ['anonExecute',true],['authenticatedExecute',true],['serviceRoleExecute',false],
].forEach(([property,value])=>assert.strictEqual(passes({...valid,[property]:value}),false,property));

console.log('production shared 6.20.5 Step-7 verifier tests: passed');
