const assert=require('assert');
const fs=require('fs');
const path=require('path');

const dir=path.join(__dirname,'../supabase/production-migrations');
const artifacts=[
  'verify/20260828141000_production_webauthn_verification_material_base64_reconciliation_6_20_6.sql',
  'preflight/20260828142000_production_pending_device_listing_source_purpose_reconciliation_6_20_7.sql',
  '20260828150000_production_webauthn_privileged_device_final_activation.sql',
  'preflight/20260828150000_production_webauthn_privileged_device_final_activation.sql',
  'verify/20260828150000_production_webauthn_privileged_device_final_activation.sql',
].map(relative=>fs.readFileSync(path.join(dir,relative),'utf8'));
const signature='get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)';
const obsolete=`to_regprocedure('public.${signature}') is not null and position('translate(encode(credential.public_key_cose, ''base64''::text)'`;
const generatedEncodingPatterns=[];
for(const artifact of artifacts){
  assert.match(artifact,new RegExp(signature.replace(/[()]/g,'\\$&')));
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
  assert.match(artifact,/performpublic\.require_platform_device_backend\(\);/);
  assert.match(artifact,/credential:=public\.require_system_owner_webauthn_actor/);
  const encodingBlock=artifact.match(/select p\.prosrc ~\* \$step8_encoding\$([\s\S]*?)\$step8_encoding\$/);
  assert.ok(encodingBlock,'literal-preserving raw prosrc encoding predicate missing');
  assert.strictEqual(encodingBlock[1][0],"'",'generated regex must start at its first semantic token');
  assert.strictEqual(encodingBlock[1].at(-1),')','generated regex must end at its final semantic token');
  assert.doesNotMatch(encodingBlock[1],/^[\n\r \t]/,'generated regex has leading boundary whitespace');
  assert.doesNotMatch(encodingBlock[1],/[\n\r \t]$/,'generated regex has trailing boundary whitespace');
  assert.ok(encodingBlock[1].includes("'publicKeyCose'"));
  assert.ok(encodingBlock[1].includes('[[:space:]]*translate[[:space:]]*\\('));
  assert.ok(encodingBlock[1].includes('encode[[:space:]]*\\('));
  assert.ok(encodingBlock[1].includes('credential[[:space:]]*\\.[[:space:]]*public_key_cose'));
  assert.ok(encodingBlock[1].includes("'base64'"));
  assert.ok(encodingBlock[1].includes("E'\\\\n\\\\r'[[:space:]]*,[[:space:]]*''"));
  assert.ok(!encodingBlock[1].includes('regexp_replace'));
  assert.ok(!encodingBlock[1].includes('position('));
  assert.ok(!encodingBlock[1].includes("'base64'::text"));
  generatedEncodingPatterns.push(encodingBlock[1]);
  assert.ok(!artifact.includes(obsolete));
}

const normalizeNonliteral=value=>value.replace(/[\s]+/g,'').toLowerCase();
const canonicalExpression=/'publickeycose'[\s]*,[\s]*translate[\s]*\([\s]*encode[\s]*\([\s]*credential[\s]*\.[\s]*public_key_cose[\s]*,[\s]*'base64'[\s]*\)[\s]*,[\s]*E'\\n\\r'[\s]*,[\s]*''[\s]*\)/i;
const canonicalBody=body=>{
  const source=normalizeNonliteral(body);
  return source.includes('performpublic.require_platform_device_backend();')
    &&source.includes('wherechallenges.id=p_challenge_idandchallenges.user_id=p_actor_user_idandchallenges.actor_device_id=p_actor_device_idandchallenges.session_id=p_session_id;')
    &&source.includes('ifnotfoundorchallenge.credential_idisnullorchallenge.verified_atisnotnullorchallenge.consumed_atisnotnullorchallenge.failed_atisnotnullorchallenge.expires_at<=statement_timestamp()then')
    &&source.includes('credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,challenge.credential_id);')
    &&canonicalExpression.test(body);
};
const passes=value=>value.signature===signature&&value.returnType==='jsonb'
  &&value.language==='plpgsql'&&value.securityDefiner&&value.volatility==='v'
  &&value.parallel==='u'&&!value.strict&&value.ownerControlled
  &&value.searchPath==='pg_catalog, public'&&!value.publicExecute&&!value.anonExecute
  &&!value.authenticatedExecute&&value.serviceRoleExecute&&canonicalBody(value.body);
const body=`PERFORM public.require_platform_device_backend();
  WHERE challenges.id=p_challenge_id AND challenges.user_id=p_actor_user_id
    AND challenges.actor_device_id=p_actor_device_id AND challenges.session_id=p_session_id;
  IF NOT FOUND OR challenge.credential_id IS NULL OR challenge.verified_at IS NOT NULL
    OR challenge.consumed_at IS NOT NULL OR challenge.failed_at IS NOT NULL
    OR challenge.expires_at<=statement_timestamp() THEN
  credential:=public.require_system_owner_webauthn_actor(
    p_actor_user_id,p_actor_device_id,challenge.credential_id);
  'publicKeyCose',translate(encode(credential.public_key_cose,'base64'),E'\\n\\r','')`;
assert.ok(body.includes("E'\\n\\r'"),'valid fixture must contain literal PostgreSQL newline/carriage-return escapes');
assert.ok(!body.includes("E'\n\r'"),'valid fixture must not contain an actual newline/carriage-return pair');
assert.ok(canonicalExpression.test(body));
assert.ok(canonicalExpression.test(body.replace('translate(encode(',`TRANSLATE (
    ENCODE (`).replace("public_key_cose,'base64'","public_key_cose , 'base64'").replace("),E'\\n\\r','')",") , E'\\n\\r' , '' )")));
assert.ok(!canonicalExpression.test(body.replace("E'\\n\\r',''","E'\\n\\r',' '")));
assert.ok(!canonicalExpression.test(body.replace("E'\\n\\r',''","E'\\n\\r','  '")));
assert.ok(!canonicalExpression.test(body.replace("E'\\n\\r',''","E'\\n\\r',E' '")));
assert.ok(!canonicalExpression.test(body.replace("E'\\n\\r',''","E'\\n\\r',E'\\t'")));
const generatedRegexNegatives=[
  body.replace("E'\\n\\r',''","E'\\n\\r',' '"),
  body.replace("E'\\n\\r',''","E'\\n\\r','  '"),
  body.replace("E'\\n\\r',''","E'\\n\\r',E' '"),
  body.replace("E'\\n\\r',''","E'\\n\\r',E'\\t'"),
  body.replace("E'\\n\\r'","E'\\n'"),
  body.replace("E'\\n\\r'","E'\\r'"),
  body.replace("E'\\n\\r'","E'\\r\\n'"),
  body.replace("encode(credential.public_key_cose,'base64')","encode('base64',credential.public_key_cose)"),
  body.replace("'base64'","'hex'"),
  body.replace("'base64'","'escape'"),
  body.replace('credential.public_key_cose','credential.webauthn_credential_id'),
];
for(const generatedPattern of generatedEncodingPatterns){
  const runtimeGeneratedRegex=new RegExp(generatedPattern.replaceAll('[[:space:]]','\\s'),'i');
  assert.ok(runtimeGeneratedRegex.test(body),'exact generated regex must match canonical fixture');
  generatedRegexNegatives.forEach(candidate=>assert.ok(!runtimeGeneratedRegex.test(candidate)));
}
const valid={signature,returnType:'jsonb',language:'plpgsql',securityDefiner:true,
  volatility:'v',parallel:'u',strict:false,ownerControlled:true,searchPath:'pg_catalog, public',
  publicExecute:false,anonExecute:false,authenticatedExecute:false,serviceRoleExecute:true,body};
assert.strictEqual(passes(valid),true);
[
  ['body',body.replace("'base64'","'hex'")],
  ['body',body.replace("'base64'","'escape'")],
  ['body',body.replace('credential.public_key_cose','credential.webauthn_credential_id')],
  ['body',body.replace('translate(encode','encode')],
  ['body',body.replace("E'\\n\\r'","E'\\n'")],
  ['body',body.replace("E'\\n\\r'","E'\\r'")],
  ['body',body.replace("E'\\n\\r',''","E'\\n\\r',' '")],
  ['body',body.replace("E'\\n\\r',''","E'\\n\\r','  '")],
  ['body',body.replace("E'\\n\\r',''","E'\\n\\r',E' '")],
  ['body',body.replace("E'\\n\\r',''","E'\\n\\r',E'\\t'")],
  ['body',body.replace("E'\\n\\r'","E'\\r\\n'")],
  ['body',body.replace("encode(credential.public_key_cose,'base64')","encode('base64',credential.public_key_cose)")],
  ['body',body.replace("translate(encode(credential.public_key_cose,'base64'),E'\\n\\r','')","'base64'")],
  ['signature','get_system_owner_device_challenge_verification_material()'],['returnType','text'],
  ['securityDefiner',false],['volatility','s'],['parallel','s'],['strict',true],
  ['ownerControlled',false],['searchPath','public'],['publicExecute',true],
  ['anonExecute',true],['authenticatedExecute',true],['serviceRoleExecute',false],
].forEach(([property,value])=>assert.strictEqual(passes({...valid,[property]:value}),false,property));

console.log('production shared 6.20.6 Step-8 verifier tests: passed');
