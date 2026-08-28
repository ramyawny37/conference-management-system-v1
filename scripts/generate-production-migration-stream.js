const fs=require('fs');
const path=require('path');
const crypto=require('crypto');

const root=path.join(__dirname,'..');
const outputDir=path.join(root,'supabase','production-migrations');
const verifyDir=path.join(outputDir,'verify');
const preflightDir=path.join(outputDir,'preflight');
const productionRef='mpezfbvcdfxpgflehuot';
const developmentRef='gppwltrifgfxrkzvvxoe';
const initial={version:'20260826193052',name:'snapshot_sync_account_authorization_hardening_6_19_0'};
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=relative=>fs.readFileSync(path.join(root,relative),'utf8');
const catalogLabels=['00-baseline','01-20260828130000','02-20260828131000',
  '03-20260828132000','04-20260828133000','05-20260828134000','06-20260828135000',
  '07-20260828140000','08-20260828141000','09-20260828142000','10-20260828143000',
  '11-20260828144000','12-20260828145000','13-20260828150000'];
const catalogContracts=Object.fromEntries(catalogLabels.map(label=>{
  const evidence=JSON.parse(read(`audit/phase-2al/evidence/run-1-canonical/${label}.json`));
  return [label,{...evidence.hashes,combined:evidence.combined_sha256}];
}));
const productionSemanticIdentities={source:'PHASE_2CG_PRODUCTION_READ_ONLY',
  functionOwner:'postgres',relationOwner:'postgres',aclGrantor:'postgres',
  functionAclGrantees:['PUBLIC','anon','authenticated','postgres','service_role'],
  relationAclGrantees:['authenticated','postgres','service_role'],policyRoles:['authenticated']};
const stripTransaction=sql=>sql.replace(/^begin;\s*/i,'').replace(/\s*commit;\s*$/i,'').trim()+'\n';

const definitions=[
  ['20260828130000','production_platform_foundation_lineage_bridge','6.19-production-bridge',null,'PRODUCTION_LINEAGE_BRIDGE'],
  ['20260828131000','production_platform_privileged_device_administration_structural_6_20_0','6.20.0','supabase/migrations/20260827_6_20_0_platform_privileged_device_administration.sql','PRODUCTION_ACTIVATION_DEFERRED'],
  ['20260828132000','production_credential_enrollment_challenge_expiry_reconciliation_6_20_1','6.20.1','supabase/migrations/20260827111559_credential_enrollment_challenge_expiry_reconciliation_6_20_1.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828133000','production_credential_enrollment_expiry_default_alignment_6_20_2','6.20.2','supabase/migrations/20260827112620_credential_enrollment_expiry_default_alignment_reconciliation_6_20_2.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828134000','production_system_owner_synced_passkey_policy_reconciliation_6_20_3','6.20.3','supabase/migrations/20260827121228_system_owner_synced_passkey_policy_reconciliation_6_20_3.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828135000','production_system_owner_synced_passkey_policy_full_reconciliation_6_20_4','6.20.4','supabase/migrations/20260827125056_system_owner_synced_passkey_policy_full_reconciliation_6_20_4.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828140000','production_webauthn_time_boundary_reconciliation_6_20_5','6.20.5','supabase/migrations/20260827130503_webauthn_time_boundary_reconciliation_6_20_5.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828141000','production_webauthn_verification_material_base64_reconciliation_6_20_6','6.20.6','supabase/migrations/20260827143343_webauthn_verification_material_base64_reconciliation_6_20_6.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828142000','production_pending_device_listing_source_purpose_reconciliation_6_20_7','6.20.7','supabase/migrations/20260827144122_pending_device_listing_source_purpose_reconciliation_6_20_7.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828143000','production_pending_device_operation_purpose_qualification_reconciliation_6_20_8','6.20.8','supabase/migrations/20260827145152_pending_device_operation_purpose_qualification_reconciliation_6_20_8.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828144000','production_pending_device_operation_purpose_variable_reconciliation_6_20_9','6.20.9','supabase/migrations/20260827155527_pending_device_operation_purpose_variable_reconciliation_6_20_9.sql','CANONICAL_SEMANTIC_EQUIVALENT'],
  ['20260828145000','production_platform_foundation_legacy_execute_grant_reconciliation','grant-reconciliation','supabase/migrations/20260828120000_platform_foundation_legacy_execute_grant_reconciliation.sql','PRODUCTION_OPTIONAL_HISTORICAL_RLS_AUTO_ENABLE_ABSENCE'],
  ['20260828150000','production_webauthn_privileged_device_final_activation','6.20-final-activation',null,'PRODUCTION_FINAL_ACTIVATION']
];

function historyLineageCondition(entries){
  const values=entries.map((entry,index)=>`(${index+1},'${entry.version}','${entry.name}','${crypto.createHash('md5').update(
    fs.readFileSync(path.join(outputDir,entry.file),'utf8')).digest('hex')}')`).join(',\n      ');
  return `(with expected(ordinal,version,name,digest) as (values ${values}), actual as (
      select row_number() over(order by version)::integer ordinal,version,name,
        md5(coalesce(array_to_string(statements,E'\\n'),'')) digest
      from supabase_migrations.schema_migrations
      where version between '${entries[0].version}' and '${entries.at(-1).version}')
    select count(*)=${entries.length} and bool_and(expected.ordinal is not null
      and actual.ordinal is not null and expected.version=actual.version
      and expected.name=actual.name and expected.digest=actual.digest)
    from expected full join actual using(ordinal))`;
}

function operationalEmptyCondition(){
  return `not exists(select 1 from public.device_security_credentials)
    and not exists(select 1 from public.device_possession_challenges)
    and not exists(select 1 from public.device_possession_challenge_consumers)
    and not exists(select 1 from public.privileged_device_listing_sessions)
    and not exists(select 1 from public.system_owner_credential_bootstrap_authorizations)
    and not exists(select 1 from public.system_owner_credential_recovery_authorizations)
    and not exists(select 1 from public.privileged_device_authorization_audit_log)
    and not exists(select 1 from public.system_owner_device_authorization_operations)`;
}

function stateGate(previous,activation,entries=[]){
  const activationChecks=activation?`  if not ${historyLineageCondition(entries)} then
    raise exception 'PRODUCTION_ACTIVATION_EXACT_FULL_LINEAGE_REQUIRED';
  end if;
  if not (${operationalEmptyCondition()}) then
    raise exception 'PRODUCTION_STREAM_UNEXPECTED_OPERATIONAL_STATE';
  end if;
`:'';
  return `do $production_gate$\ndeclare latest record;\nbegin\n  if current_setting('server_version_num')::integer<170000\n    or current_setting('server_version_num')::integer>=180000 then\n    raise exception 'PRODUCTION_STREAM_POSTGRES_17_REQUIRED';\n  end if;\n  select version,name into latest from supabase_migrations.schema_migrations\n    order by version desc limit 1;\n  if latest.version is distinct from '${previous.version}'\n    or latest.name is distinct from '${previous.name}' then\n    raise exception 'PRODUCTION_STREAM_EXACT_PREDECESSOR_REQUIRED';\n  end if;\n  if (select count(*)<>1 or coalesce(bool_or(enabled),true)\n      from public.webauthn_privileged_device_feature) then\n    raise exception 'PRODUCTION_STREAM_WEBAUTHN_MUST_BE_DISABLED';\n  end if;\n  if (select count(*)<>1 or coalesce(bool_or(enforcement_enabled),true)\n      from public.device_authorization_enforcement) then\n    raise exception 'PRODUCTION_STREAM_DEVICE_ENFORCEMENT_MUST_BE_DISABLED';\n  end if;\n${activationChecks}end;\n$production_gate$;\n`;
}

function inertPostcondition(){
  return `\ndo $production_post$\nbegin\n  if (select count(*)<>1 or coalesce(bool_or(enabled),true)\n      from public.webauthn_privileged_device_feature)\n    or (select count(*)<>1 or coalesce(bool_or(enforcement_enabled),true)\n      from public.device_authorization_enforcement) then\n    raise exception 'PRODUCTION_STREAM_INERT_POSTCONDITION_FAILED';\n  end if;\nend;\n$production_post$;\n`;
}

function correctedBridge(){
  let sql=stripTransaction(read('supabase/migrations/20260828120132_production_platform_foundation_lineage_bridge.sql'));
  sql=sql.replace(/begin\n  with expected/,`begin\n  if current_setting('server_version_num')::integer<170000\n    or current_setting('server_version_num')::integer>=180000 then\n    raise exception 'PRODUCTION_PLATFORM_BRIDGE_POSTGRES_17_REQUIRED';\n  end if;\n  with expected`);
  const start=sql.indexOf("  select md5(coalesce(string_agg(v.name||'|'||");
  const end=sql.indexOf("  if (select count(*)<>1",start);
  const qualified=`  if exists (\n    select 1 from (values\n      ('device_security_credentials_lifecycle_guard','device_security_credentials'),\n      ('user_device_authorizations_security_credential_guard','user_device_authorizations'),\n      ('device_possession_challenges_identity_guard','device_possession_challenges'),\n      ('device_possession_challenge_consumers_guard','device_possession_challenge_consumers'),\n      ('privileged_device_listing_sessions_lifecycle_guard','privileged_device_listing_sessions'),\n      ('system_owner_bootstrap_authorizations_lifecycle_guard','system_owner_credential_bootstrap_authorizations'),\n      ('system_owner_recovery_authorizations_lifecycle_guard','system_owner_credential_recovery_authorizations'),\n      ('privileged_device_authorization_audit_immutable','privileged_device_authorization_audit_log'),\n      ('system_owner_device_authorization_operations_immutable','system_owner_device_authorization_operations')\n    ) expected(trigger_name,relation_name)\n    left join pg_class c on c.oid=to_regclass('public.'||expected.relation_name)\n    left join pg_trigger t on t.tgrelid=c.oid and t.tgname=expected.trigger_name\n      and not t.tgisinternal\n    where t.oid is null\n  ) then raise exception 'PRODUCTION_PLATFORM_BRIDGE_QUALIFIED_TRIGGER_DRIFT'; end if;\n\n`;
  sql=sql.slice(0,start)+qualified+sql.slice(end);
  sql=sql.replace("    raise exception 'PRODUCTION_PLATFORM_BRIDGE_6_19_RESULTING_CONTRACT_REQUIRED';\n  end if;",
`    raise exception 'PRODUCTION_PLATFORM_BRIDGE_6_19_RESULTING_CONTRACT_REQUIRED';\n  end if;\n  if position('require_current_approved_device' in pg_get_functiondef(\n      to_regprocedure('public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)')))=0\n    or position('conference_snapshot_guard_intents' in pg_get_functiondef(\n      to_regprocedure('public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)')))=0\n    or position('sync_operations' in pg_get_functiondef(\n      to_regprocedure('public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)')))=0\n    or position('require_current_approved_device' in pg_get_functiondef(\n      to_regprocedure('public.device_guarded_resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)')))=0\n    or position('system_access_admin_operations' in pg_get_functiondef(\n      to_regprocedure('public.device_guarded_manage_system_user(uuid,uuid,uuid,text,boolean)')))=0\n    or position('is_system_owner' in pg_get_functiondef(\n      to_regprocedure('public.device_guarded_manage_system_user(uuid,uuid,uuid,text,boolean)')))=0 then\n    raise exception 'PRODUCTION_PLATFORM_BRIDGE_6_19_SEMANTIC_CONTRACT_REQUIRED';\n  end if;`);
  return sql;
}

function canonicalDerivative(source,deferActivation){
  let body=stripTransaction(read(source));
  if(deferActivation){
    const activation=/\nupdate public\.webauthn_privileged_device_feature set enabled=true,updated_at=statement_timestamp\(\)\nwhere singleton_id=1 and enabled=false;\n?$/i;
    if(!activation.test(body)) throw new Error('canonical 6.20.0 activation statement changed');
    body=body.replace(activation,'\n');
  }
  return body;
}

function productionGrantDerivative(source){
  const canonical=stripTransaction(read(source));
  const optional='revoke execute on function public.rls_auto_enable() from public, anon, authenticated;';
  if(!canonical.includes(optional)) throw new Error('canonical grant reconciliation target changed');
  return canonical.replace(optional,`-- Production evidence (PostgreSQL 17.6, project mpezfbvcdfxpgflehuot) proves this
-- repository-undefined historical helper is absent. If it unexpectedly exists later,
-- reconcile only its exact zero-argument signature without creating or replacing it.
do $production_optional_historical_grant$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$production_optional_historical_grant$;`);
}

function aclExecuteCondition(oidExpression,roleName,allowed){
  const grantee=roleName==='PUBLIC' ? 'acl.grantee=0' :
    `acl.grantee=(select oid from pg_roles where rolname='${roleName}')`;
  const exists=`exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where ${grantee} and acl.privilege_type='EXECUTE')`;
  return `${allowed?'':'not '}${exists}`;
}

const platformSignatures=[
  'require_platform_device_backend()','require_system_owner_webauthn_actor(uuid,uuid,uuid)',
  'begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)',
  'issue_system_owner_credential_bootstrap_authorization(uuid,uuid,uuid,uuid,text,bytea,text,text,text)',
  'get_system_owner_platform_device_administration_state(uuid,uuid)',
  'complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)',
  'begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)',
  'complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)',
  'get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)',
  'fail_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text)',
  'list_system_owner_pending_device_authorizations(uuid,uuid,uuid,text,bytea)',
  'complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)',
  'get_system_owner_device_operation_result(uuid,uuid,uuid,uuid,uuid,text,text)'
];

function functionSecurityCondition(signatures=platformSignatures){
  const values=signatures.map(signature=>`('${signature}')`).join(',');
  return `(select count(*)=${signatures.length} and bool_and(p.prosecdef)
    and bool_and(p.proconfig @> array['search_path=pg_catalog, public']::text[])
    and count(distinct p.proowner)=1
    and bool_and(p.proowner=(select relowner from pg_class
      where oid=to_regclass('public.user_device_authorizations')))
    and bool_and(${aclExecuteCondition('p.oid','PUBLIC',false)})
    and bool_and(${aclExecuteCondition('p.oid','anon',false)})
    and bool_and(${aclExecuteCondition('p.oid','authenticated',false)})
    and bool_and(${aclExecuteCondition('p.oid','service_role',true)})
    from (values ${values}) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature))`;
}

function functionMarkersCondition(signature,markers){
  return `to_regprocedure('public.${signature}') is not null and `+markers.map(marker=>
    `position('${marker.replaceAll("'","''")}' in pg_get_functiondef(to_regprocedure('public.${signature}')))>0`).join(' and ');
}

function exactTwoMinuteStatementTimestampCondition(signature){
  const oid=`to_regprocedure('public.${signature}')`;
  return `${oid} is not null and position('statement_timestamp()+interval''2minutes''' in
    regexp_replace(pg_get_functiondef(${oid}),'[[:space:]]+','','g'))>0`;
}

function exactStep3FunctionMetadataCondition(signature){
  return `(select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.${signature}'))`;
}

function exactStep4EnrollmentContractCondition(signature){
  return `(select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    and position('p_environment,now()+interval''2minutes'')' in
      regexp_replace(p.prosrc,'[[:space:]]+','','g'))>0
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.${signature}'))`;
}

function exactStep5EnrollmentContractCondition(signature){
  return `(select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    and position('jsonb_typeof(p_verification_context->''backupEligible'')isdistinctfrom''boolean''' in
      regexp_replace(p.prosrc,'[[:space:]]+','','g'))>0
    and position('jsonb_typeof(p_verification_context->''backupState'')isdistinctfrom''boolean''' in
      regexp_replace(p.prosrc,'[[:space:]]+','','g'))>0
    and position('(p_verification_context->>''backupEligible'')::boolean' in
      regexp_replace(p.prosrc,'[[:space:]]+','','g'))>0
    and position('(p_verification_context->>''backupState'')::boolean' in
      regexp_replace(p.prosrc,'[[:space:]]+','','g'))>0
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.${signature}'))`;
}

function exactStep7TimeBoundaryContractCondition(beginChallenge,listing){
  const metadata=signature=>`(select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.${signature}'))`;
  const normalizedSource=(signature,marker)=>`position('${marker.replaceAll("'","''")}' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.${signature}')),'[[:space:]]+','','g'))>0`;
  return `${metadata(beginChallenge)} and ${metadata(listing)}
    and ${normalizedSource(beginChallenge,"credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,p_credential_id)")}
    and ${normalizedSource(beginChallenge,"p_purposenotin('SYSTEM_OWNER_PENDING_DEVICE_LIST','SYSTEM_OWNER_PENDING_DEVICE_APPROVE','SYSTEM_OWNER_PENDING_DEVICE_REJECT')")}
    and ${normalizedSource(beginChallenge,"p_environment,now()+interval'2minutes')returningidintochallenge_id")}
    and ${normalizedSource(listing,"credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,p_credential_id)")}
    and ${normalizedSource(listing,"challenges.purpose='SYSTEM_OWNER_PENDING_DEVICE_LIST'")}
    and ${normalizedSource(listing,"challenges.environment=p_environment")}
    and ${normalizedSource(listing,"p_environment,'SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY',now()+interval'5minutes');")}`;
}

function exactStep8EncodingContractCondition(signature){
  const normalizedSource=marker=>`position('${marker.replaceAll("'","''")}' in
    lower(regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.${signature}')),'[[:space:]]+','','g')))>0`;
  const canonicalEncodingExpression=`(select p.prosrc ~* $step8_encoding$'publicKeyCose'[[:space:]]*,[[:space:]]*translate[[:space:]]*\\([[:space:]]*encode[[:space:]]*\\([[:space:]]*credential[[:space:]]*\\.[[:space:]]*public_key_cose[[:space:]]*,[[:space:]]*'base64'[[:space:]]*\\)[[:space:]]*,[[:space:]]*E'\\\\n\\\\r'[[:space:]]*,[[:space:]]*''[[:space:]]*\\)$step8_encoding$ from pg_proc p
    where p.oid=to_regprocedure('public.${signature}'))`;
  return `(select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.${signature}'))
    and ${normalizedSource('performpublic.require_platform_device_backend();')}
    and ${normalizedSource('wherechallenges.id=p_challenge_idandchallenges.user_id=p_actor_user_idandchallenges.actor_device_id=p_actor_device_idandchallenges.session_id=p_session_id;')}
    and ${normalizedSource("ifnotfoundorchallenge.credential_idisnullorchallenge.verified_atisnotnullorchallenge.consumed_atisnotnullorchallenge.failed_atisnotnullorchallenge.expires_at<=statement_timestamp()then")}
    and ${normalizedSource('credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,challenge.credential_id);')}
    and ${canonicalEncodingExpression}`;
}

function foundationContract(){
  return `(select count(*)=9 and bool_and(c.relrowsecurity) and count(distinct c.relowner)=1
      and bool_and(c.relowner=(select relowner from pg_class
        where oid=to_regclass('public.user_device_authorizations')))
      and bool_and(not exists(select 1 from pg_policy where polrelid=c.oid))
      and bool_and(not has_table_privilege('anon',c.oid,'select,insert,update,delete'))
      and bool_and(not has_table_privilege('authenticated',c.oid,'select,insert,update,delete'))
    from (values ('webauthn_privileged_device_feature'),('device_security_credentials'),
      ('device_possession_challenges'),('device_possession_challenge_consumers'),
      ('privileged_device_listing_sessions'),('system_owner_credential_bootstrap_authorizations'),
      ('system_owner_credential_recovery_authorizations'),('privileged_device_authorization_audit_log'),
      ('system_owner_device_authorization_operations')) required(name)
    join pg_class c on c.oid=to_regclass('public.'||required.name))
    and (select count(t.oid)=9 from (values
      ('device_security_credentials_lifecycle_guard','device_security_credentials'),
      ('user_device_authorizations_security_credential_guard','user_device_authorizations'),
      ('device_possession_challenges_identity_guard','device_possession_challenges'),
      ('device_possession_challenge_consumers_guard','device_possession_challenge_consumers'),
      ('privileged_device_listing_sessions_lifecycle_guard','privileged_device_listing_sessions'),
      ('system_owner_bootstrap_authorizations_lifecycle_guard','system_owner_credential_bootstrap_authorizations'),
      ('system_owner_recovery_authorizations_lifecycle_guard','system_owner_credential_recovery_authorizations'),
      ('privileged_device_authorization_audit_immutable','privileged_device_authorization_audit_log'),
      ('system_owner_device_authorization_operations_immutable','system_owner_device_authorization_operations'))
      required(trigger_name,relation_name)
      join pg_class c on c.oid=to_regclass('public.'||required.relation_name)
      join pg_trigger t on t.tgrelid=c.oid and t.tgname=required.trigger_name and not t.tgisinternal)
    and (select md5(coalesce(string_agg(i.tablename||'|'||i.indexname||'|'||i.indexdef,
      E'\\n' order by i.tablename,i.indexname),'')) from pg_indexes i
      where i.schemaname='public' and i.tablename=any(array[
      'webauthn_privileged_device_feature','device_security_credentials',
      'device_possession_challenges','device_possession_challenge_consumers',
      'privileged_device_listing_sessions','system_owner_credential_bootstrap_authorizations',
      'system_owner_credential_recovery_authorizations','privileged_device_authorization_audit_log',
      'system_owner_device_authorization_operations']))='5059f8c84bc709b10cdc258660de52b9'`;
}

function releaseContract(release){
  const beginEnrollment='begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)';
  const completeEnrollment='complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)';
  const beginChallenge='begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)';
  const listing='complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)';
  const material='get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)';
  const operation='complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)';
  if(release==='6.20.0') return `${foundationContract()} and ${functionSecurityCondition()}`;
  if(release==='6.20.1') return `${functionSecurityCondition([beginEnrollment])} and ${exactStep3FunctionMetadataCondition(beginEnrollment)} and ${exactTwoMinuteStatementTimestampCondition(beginEnrollment)}`;
  if(release==='6.20.2') return `${functionSecurityCondition([beginEnrollment])} and ${exactStep4EnrollmentContractCondition(beginEnrollment)}`;
  if(release==='6.20.3') return `${functionSecurityCondition([completeEnrollment])} and ${exactStep5EnrollmentContractCondition(completeEnrollment)}`;
  if(release==='6.20.4') return `exists(select 1 from pg_constraint where conrelid='public.device_security_credentials'::regclass and conname='device_security_credentials_non_backup_policy' and pg_get_constraintdef(oid,true) like '%NOT backup_state OR backup_eligible%') and ${functionSecurityCondition([listing,operation])} and ${functionMarkersCondition(listing,['backupState','backupEligible'])}`;
  if(release==='6.20.5') return `${functionSecurityCondition([beginChallenge,listing])} and ${exactStep7TimeBoundaryContractCondition(beginChallenge,listing)}`;
  if(release==='6.20.6') return `${functionSecurityCondition([material])} and ${exactStep8EncodingContractCondition(material)}`;
  if(release==='6.20.7') return `${functionSecurityCondition([listing])} and exists(select 1 from information_schema.columns where table_schema='public' and table_name='privileged_device_listing_sessions' and column_name='source_challenge_purpose') and ${functionMarkersCondition(listing,['source_challenge_purpose','SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY'])}`;
  if(release==='6.20.8') return `${functionSecurityCondition([operation])} and ${functionMarkersCondition(operation,['complete_system_owner_pending_device_operation.purpose'])}`;
  if(release==='6.20.9') return `${functionSecurityCondition([operation])} and ${functionMarkersCondition(operation,['expected_challenge_purpose'])} and position('complete_system_owner_pending_device_operation.purpose' in pg_get_functiondef(to_regprocedure('public.${operation}')))=0`;
  if(release==='grant-reconciliation') return `(
    (to_regprocedure('public.rls_auto_enable()') is null or not exists(
      select 1 from pg_proc p cross join lateral
        aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where p.oid=to_regprocedure('public.rls_auto_enable()')
        and acl.privilege_type='EXECUTE' and (acl.grantee=0 or acl.grantee in
          (select oid from pg_roles where rolname in ('anon','authenticated')))))
    and not exists(select 1 from (values
      ('enforce_launch_conference_member_contract()','PUBLIC'),
      ('enforce_launch_conference_member_contract()','anon'),
      ('enforce_launch_conference_member_contract()','authenticated'),
      ('prevent_null_conference_organization()','PUBLIC'),
      ('prevent_null_conference_organization()','anon'),
      ('prevent_null_conference_organization()','authenticated'),
      ('acquire_conference_lock(uuid,uuid,uuid,integer)','anon'),
      ('renew_conference_lock(uuid,uuid,uuid,integer)','anon'),
      ('release_conference_lock(uuid,uuid,uuid)','anon'),
      ('get_conference_lock(uuid,uuid)','anon'),('get_conference_section_lock(uuid,text,uuid)','anon'),
      ('is_conference_member(uuid)','anon'),('has_conference_role(uuid,text[])','anon'),
      ('is_conference_owner(uuid)','anon')) required(signature,role_name)
      join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)
      cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where acl.privilege_type='EXECUTE' and (required.role_name='PUBLIC' and acl.grantee=0
        or required.role_name<>'PUBLIC' and acl.grantee=(select oid from pg_roles where rolname=required.role_name))))`;
  return foundationContract();
}

function completeActivationContract(){
  return `${foundationContract()} and ${functionSecurityCondition()}
    and ${releaseContract('6.20.2')} and ${releaseContract('6.20.3')}
    and ${releaseContract('6.20.4')}
    and exists(select 1 from pg_constraint
      where conrelid='public.privileged_device_authorization_audit_log'::regclass
      and conname='privileged_device_audit_webauthn_policy'
      and pg_get_constraintdef(oid,true) like '%NOT backup_state OR backup_eligible%')
    and ${releaseContract('6.20.5')}
    and ${releaseContract('6.20.6')} and ${releaseContract('6.20.7')}
    and ${releaseContract('6.20.9')} and ${releaseContract('grant-reconciliation')}`;
}

function substantiveVerifier(version,name,release,webauthn){
  const contract=release==='6.20-final-activation'?completeActivationContract():releaseContract(release);
  return `-- Independent read-only resulting-contract verifier for ${version}.
select case when exists(select 1 from supabase_migrations.schema_migrations
    where version='${version}' and name='${name}') and (${contract}) then 'PASS' else 'BLOCKED' end,
  (select enabled from public.webauthn_privileged_device_feature where singleton_id=1),
  (select enforcement_enabled from public.device_authorization_enforcement where singleton_id=1);
`;
}

function activationSql(){
  return `do $activation_contract$
begin
  if not (${completeActivationContract()}) then
    raise exception 'PRODUCTION_ACTIVATION_COMPLETE_SECURITY_CONTRACT_REQUIRED';
  end if;
end;
$activation_contract$;
update public.webauthn_privileged_device_feature
set enabled=true,updated_at=statement_timestamp()
where singleton_id=1 and enabled=false;
do $activation_post$
begin
  if not (select count(*)=1 and bool_and(enabled)
      from public.webauthn_privileged_device_feature)
    or not (select count(*)=1 and bool_and(not enforcement_enabled)
      from public.device_authorization_enforcement)
    or not (${completeActivationContract()}) then
    raise exception 'PRODUCTION_ACTIVATION_POSTCONDITION_FAILED';
  end if;
end;
$activation_post$;
`;
}

function bridgeVerifier(version,name){
  return `-- Independent read-only bridge post-verifier.\nwith relations as (select c.oid,c.relowner,c.relrowsecurity from (values\n  ('webauthn_privileged_device_feature'),('device_security_credentials'),\n  ('device_possession_challenges'),('device_possession_challenge_consumers'),\n  ('privileged_device_listing_sessions'),('system_owner_credential_bootstrap_authorizations'),\n  ('system_owner_credential_recovery_authorizations'),('privileged_device_authorization_audit_log'),\n  ('system_owner_device_authorization_operations')) v(name)\n  left join pg_class c on c.oid=to_regclass('public.'||v.name)),\nfunctions as (select to_regprocedure('public.'||v.signature) oid from (values\n  ('guard_device_security_credential_lifecycle()'),\n  ('guard_device_authorization_security_credential_state()'),\n  ('guard_device_possession_challenge_identity()'),('guard_device_possession_challenge_consumer()'),\n  ('guard_privileged_device_listing_session_lifecycle()'),\n  ('guard_system_owner_bootstrap_authorization_lifecycle()'),\n  ('guard_system_owner_recovery_authorization_lifecycle()')) v(signature)),\nqualified_triggers as (select t.oid from (values\n  ('device_security_credentials_lifecycle_guard','device_security_credentials'),\n  ('user_device_authorizations_security_credential_guard','user_device_authorizations'),\n  ('device_possession_challenges_identity_guard','device_possession_challenges'),\n  ('device_possession_challenge_consumers_guard','device_possession_challenge_consumers'),\n  ('privileged_device_listing_sessions_lifecycle_guard','privileged_device_listing_sessions'),\n  ('system_owner_bootstrap_authorizations_lifecycle_guard','system_owner_credential_bootstrap_authorizations'),\n  ('system_owner_recovery_authorizations_lifecycle_guard','system_owner_credential_recovery_authorizations'),\n  ('privileged_device_authorization_audit_immutable','privileged_device_authorization_audit_log'),\n  ('system_owner_device_authorization_operations_immutable','system_owner_device_authorization_operations')) v(trigger_name,relation_name)\n  left join pg_class c on c.oid=to_regclass('public.'||v.relation_name)\n  left join pg_trigger t on t.tgrelid=c.oid and t.tgname=v.trigger_name and not t.tgisinternal)\nselect case when exists(select 1 from supabase_migrations.schema_migrations\n    where version='${version}' and name='${name}')\n  and (select count(*)=9 and bool_and(relrowsecurity) and count(distinct relowner)=1\n    and bool_and(not exists(select 1 from pg_policy where polrelid=relations.oid))\n    and bool_and(not has_table_privilege('anon',relations.oid,'select,insert,update,delete'))\n    and bool_and(not has_table_privilege('authenticated',relations.oid,'select,insert,update,delete')) from relations)\n  and (select count(*)=7 and bool_and(p.prosecdef)\n    and bool_and(p.proconfig @> array['search_path=pg_catalog, public']::text[])\n    and bool_and(not has_function_privilege('anon',p.oid,'execute'))\n    and bool_and(not has_function_privilege('authenticated',p.oid,'execute'))\n    from functions f join pg_proc p on p.oid=f.oid)\n  and (select count(oid)=9 from qualified_triggers)\n  and position('conference_snapshot_guard_intents' in pg_get_functiondef(to_regprocedure(\n    'public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)')))>0\n  and position('system_access_admin_operations' in pg_get_functiondef(to_regprocedure(\n    'public.device_guarded_manage_system_user(uuid,uuid,uuid,text,boolean)')))>0\n  then 'PASS' else 'BLOCKED' end,\n  (select enabled from public.webauthn_privileged_device_feature where singleton_id=1),\n  (select enforcement_enabled from public.device_authorization_enforcement where singleton_id=1);\n`;
}

fs.mkdirSync(verifyDir,{recursive:true});
fs.mkdirSync(preflightDir,{recursive:true});
const entries=[];
let previous=initial;
for(const [version,name,release,source,delta] of definitions){
  let body;
  if(delta==='PRODUCTION_LINEAGE_BRIDGE') body=correctedBridge();
  else if(delta==='PRODUCTION_FINAL_ACTIVATION') body=stateGate(previous,true,entries)+activationSql();
  else if(delta==='PRODUCTION_OPTIONAL_HISTORICAL_RLS_AUTO_ENABLE_ABSENCE')
    body=stateGate(previous,false)+productionGrantDerivative(source)+inertPostcondition();
  else body=stateGate(previous,false)+canonicalDerivative(source,delta==='PRODUCTION_ACTIVATION_DEFERRED')+inertPostcondition();
  const header=`-- Generated dedicated Production stream migration.\n-- Project: ${productionRef}; Development ref is forbidden: ${developmentRef}.\n-- Semantic release: ${release}; intentional delta: ${delta}.\n`;
  const content=header+body.trim()+'\n';
  const file=`${version}_${name}.sql`;
  fs.writeFileSync(path.join(outputDir,file),content);
  const exactBridgeHistory=delta==='PRODUCTION_LINEAGE_BRIDGE' ? `\n    and (select count(*)=5 from supabase_migrations.schema_migrations)\n    and exists(select 1 from supabase_migrations.schema_migrations where version='20260824121653' and name='20260824_6_15_0_organization_membership_reconciliation' and md5(coalesce(array_to_string(statements,E'\\n'),''))='cb5c461d6a8b0f20d814d2984ce5214f')\n    and exists(select 1 from supabase_migrations.schema_migrations where version='20260824180055' and name='20260824_6_16_0_webauthn_privileged_device_security_foundation' and md5(coalesce(array_to_string(statements,E'\\n'),''))='1776e168f18f0a587192ad0d60c621ae')\n    and exists(select 1 from supabase_migrations.schema_migrations where version='20260826191608' and md5(coalesce(array_to_string(statements,E'\\n'),''))='ca136f8ef4e70b7a74f43b47142bdc14')\n    and exists(select 1 from supabase_migrations.schema_migrations where version='20260826191920' and md5(coalesce(array_to_string(statements,E'\\n'),''))='699f1bf58271c8c75d6026ebc0436b28')\n    and exists(select 1 from supabase_migrations.schema_migrations where version='20260826193052' and md5(coalesce(array_to_string(statements,E'\\n'),''))='b62936c7a81c6a743b206d3ef37ff0e2')` : '';
  const predecessorEntry=entries.at(-1);
  const predecessorDigest=predecessorEntry?crypto.createHash('md5').update(
    fs.readFileSync(path.join(outputDir,predecessorEntry.file),'utf8')).digest('hex'):null;
  const predecessorState=predecessorEntry
    ?`\n    and exists(select 1 from supabase_migrations.schema_migrations where version='${previous.version}'
      and name='${previous.name}' and md5(coalesce(array_to_string(statements,E'\\n'),''))='${predecessorDigest}')
    and (${predecessorEntry.semanticRelease==='6.19-production-bridge'?foundationContract():releaseContract(predecessorEntry.semanticRelease)})`:'';
  const activationPreflight=delta==='PRODUCTION_FINAL_ACTIVATION'
    ?`\n    and ${historyLineageCondition(entries)}
    and (${completeActivationContract()})
    and (${operationalEmptyCondition()})`:'';
  const grantPreflight=delta==='PRODUCTION_OPTIONAL_HISTORICAL_RLS_AUTO_ENABLE_ABSENCE'
    ?`\n    -- Approved Production evidence expects absence; the reviewed safe-present branch is also valid.
    and (to_regprocedure('public.rls_auto_enable()') is null or exists(select 1 from pg_proc
      where oid=to_regprocedure('public.rls_auto_enable()') and pronargs=0))
    and (select count(*)=11 from (values
      ('enforce_launch_conference_member_contract()'),('prevent_null_conference_organization()'),
      ('acquire_conference_lock(uuid,uuid,uuid,integer)'),('renew_conference_lock(uuid,uuid,uuid,integer)'),
      ('release_conference_lock(uuid,uuid,uuid)'),('get_conference_lock(uuid,uuid)'),
      ('get_conference_section_lock(uuid,text,uuid)'),('is_conference_member(uuid)'),
      ('has_conference_role(uuid,text[])'),('is_conference_owner(uuid)'),
      ('complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')) required(signature)
      where to_regprocedure('public.'||required.signature) is not null)`:'';
  const preflight=`-- Independent read-only predecessor-contract preflight for ${version}.
with latest as (select version,name from supabase_migrations.schema_migrations order by version desc limit 1)
select case when (select version='${previous.version}' and name='${previous.name}' from latest)${exactBridgeHistory}${predecessorState}${activationPreflight}${grantPreflight}
    and (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
    and (select count(*)=1 and bool_and(not enforcement_enabled) from public.device_authorization_enforcement)
  then 'PASS' else 'BLOCKED' end;
`;
  const preflightFile=`preflight/${version}_${name}.sql`;
  fs.writeFileSync(path.join(outputDir,preflightFile),preflight);
  const verifier=delta==='PRODUCTION_LINEAGE_BRIDGE' ? bridgeVerifier(version,name) :
    substantiveVerifier(version,name,release,delta==='PRODUCTION_FINAL_ACTIVATION');
  const verifierFile=`verify/${version}_${name}.sql`;
  fs.writeFileSync(path.join(outputDir,verifierFile),verifier);
  entries.push({version,name,semanticRelease:release,
    predecessor:{version:previous.version,name:previous.name},file,
    sourceCanonicalPath:source,canonicalSourceSha256:source?sha(read(source)):null,
    productionSha256:sha(content),verifier:verifierFile,verifierSha256:sha(verifier),
    preflight:preflightFile,preflightSha256:sha(preflight),
    intentionalDelta:delta,featureActivationPermitted:delta==='PRODUCTION_FINAL_ACTIVATION',
    expectedWebAuthnBefore:false,expectedWebAuthnAfter:delta==='PRODUCTION_FINAL_ACTIVATION',
    expectedDeviceEnforcementBefore:false,expectedDeviceEnforcementAfter:false});
  previous={version,name};
}
const manifest={schemaVersion:1,stream:'conference-production-forward-reconciliation',
  productionProjectRef:productionRef,forbiddenProjectRefs:[developmentRef],
  productionDatabaseIdentity:null,
  migrationHistoryEvidence:{source:'PHASE_2AM_PRODUCTION_READ_ONLY',rowCount:5,
    statementsArrayElementsPerRow:1,columns:[
      {ordinal:1,name:'version',type:'text',udtSchema:'pg_catalog',udtName:'text',nullable:false,default:null,identity:'',generated:'NEVER'},
      {ordinal:2,name:'statements',type:'ARRAY',udtSchema:'pg_catalog',udtName:'_text',nullable:true,default:null,identity:'',generated:'NEVER'},
      {ordinal:3,name:'name',type:'text',udtSchema:'pg_catalog',udtName:'text',nullable:true,default:null,identity:'',generated:'NEVER'},
      {ordinal:4,name:'created_by',type:'text',udtSchema:'pg_catalog',udtName:'text',nullable:true,default:null,identity:'',generated:'NEVER'},
      {ordinal:5,name:'idempotency_key',type:'text',udtSchema:'pg_catalog',udtName:'text',nullable:true,default:null,identity:'',generated:'NEVER'},
      {ordinal:6,name:'rollback',type:'ARRAY',udtSchema:'pg_catalog',udtName:'_text',nullable:true,default:null,identity:'',generated:'NEVER'}],
    constraints:[{name:'schema_migrations_idempotency_key_key',type:'u',definition:'UNIQUE (idempotency_key)'},
      {name:'schema_migrations_pkey',type:'p',definition:'PRIMARY KEY (version)'}]},
  migrationHistoryContractSha256:null,
  normalSupabaseBulkCommandsPermitted:false,initialPredecessor:initial,migrations:entries};
manifest.migrationHistoryContractSha256=sha(JSON.stringify(manifest.migrationHistoryEvidence.columns)+
  JSON.stringify(manifest.migrationHistoryEvidence.constraints));
fs.writeFileSync(path.join(outputDir,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
fs.writeFileSync(path.join(outputDir,'catalog-contracts.json'),JSON.stringify({
  schema:'PHASE_2CG_CATALOG_CONTRACTS_V1',labels:catalogLabels,states:catalogContracts,
  productionSemanticIdentities},null,2)+'\n');
console.log(`generated ${entries.length} Production migrations`);
