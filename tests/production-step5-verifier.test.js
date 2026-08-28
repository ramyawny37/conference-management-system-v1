const assert=require('assert');
const fs=require('fs');
const path=require('path');

const root=path.join(__dirname,'..');
const dir=path.join(root,'supabase','production-migrations');
const artifacts=[
  'verify/20260828134000_production_system_owner_synced_passkey_policy_reconciliation_6_20_3.sql',
  'preflight/20260828135000_production_system_owner_synced_passkey_policy_full_reconciliation_6_20_4.sql',
  '20260828150000_production_webauthn_privileged_device_final_activation.sql',
  'preflight/20260828150000_production_webauthn_privileged_device_final_activation.sql',
  'verify/20260828150000_production_webauthn_privileged_device_final_activation.sql',
].map(relative=>fs.readFileSync(path.join(dir,relative),'utf8'));

const signature='complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)';
const obsoleteMarkers=[
  "jsonb_typeof((p_verification_context -> ''backupEligible''::text))",
  "jsonb_typeof((p_verification_context -> ''backupState''::text))",
];
for(const artifact of artifacts){
  assert.match(artifact,new RegExp(signature.replace(/[()[\]]/g,'\\$&')));
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
  assert.match(artifact,/jsonb_typeof\(p_verification_context->''backupEligible''\)isdistinctfrom''boolean''/);
  assert.match(artifact,/jsonb_typeof\(p_verification_context->''backupState''\)isdistinctfrom''boolean''/);
  assert.match(artifact,/\(p_verification_context->>''backupEligible''\)::boolean/);
  assert.match(artifact,/\(p_verification_context->>''backupState''\)::boolean/);
  obsoleteMarkers.forEach(marker=>assert.ok(!artifact.includes(marker)));
}

const canonicalBody=body=>{
  const source=body.replace(/[\s]+/g,'');
  return source.includes("jsonb_typeof(p_verification_context->'backupEligible')isdistinctfrom'boolean'")
    &&source.includes("jsonb_typeof(p_verification_context->'backupState')isdistinctfrom'boolean'")
    &&source.includes("(p_verification_context->>'backupEligible')::boolean")
    &&source.includes("(p_verification_context->>'backupState')::boolean");
};
const passes=value=>value.signature===signature&&value.returnType==='jsonb'
  &&value.language==='plpgsql'&&value.securityDefiner&&value.volatility==='v'
  &&value.parallel==='u'&&!value.strict&&value.ownerControlled
  &&value.searchPath==='pg_catalog, public'&&!value.publicExecute&&!value.anonExecute
  &&!value.authenticatedExecute&&value.serviceRoleExecute&&canonicalBody(value.body);
const body=`
  or jsonb_typeof(p_verification_context->'backupEligible') is distinct from 'boolean'
  or jsonb_typeof(p_verification_context->'backupState') is distinct from 'boolean' then
  values((p_verification_context->>'backupEligible')::boolean,
    (p_verification_context->>'backupState')::boolean)`;
const valid={signature,returnType:'jsonb',language:'plpgsql',securityDefiner:true,
  volatility:'v',parallel:'u',strict:false,ownerControlled:true,searchPath:'pg_catalog, public',
  publicExecute:false,anonExecute:false,authenticatedExecute:false,serviceRoleExecute:true,body};
assert.strictEqual(passes(valid),true);
[
  ['body',body.replaceAll('backupEligible','renamedEligible')],
  ['body',body.replaceAll('backupState','renamedState')],
  ['body',body.replace("p_verification_context->'backupEligible'","p_verification_context->>'backupEligible'")],
  ['body',body.replace('jsonb_typeof','coalesce')],
  ['body',body.replaceAll('p_verification_context','other_context')],
  ['body',body.replace(/.*backupState.*\n/g,'')],
  ['returnType','text'],['securityDefiner',false],['volatility','s'],['parallel','s'],
  ['strict',true],['ownerControlled',false],['searchPath','public'],['publicExecute',true],
  ['anonExecute',true],['authenticatedExecute',true],['serviceRoleExecute',false],
].forEach(([property,value])=>assert.strictEqual(passes({...valid,[property]:value}),false,property));

console.log('production shared 6.20.3 Step-5 verifier tests: passed');
