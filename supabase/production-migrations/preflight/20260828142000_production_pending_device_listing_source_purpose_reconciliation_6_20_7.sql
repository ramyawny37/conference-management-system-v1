-- Independent read-only predecessor-contract preflight for 20260828142000.
with latest as (select version,name from supabase_migrations.schema_migrations order by version desc limit 1)
select case when (select version='20260828141000' and name='production_webauthn_verification_material_base64_reconciliation_6_20_6' from latest)
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260828141000'
      and name='production_webauthn_verification_material_base64_reconciliation_6_20_6' and md5(coalesce(array_to_string(statements,E'\n'),''))='42ccd207946ad243233ad179f7b86408')
    and ((select count(*)=1 and bool_and(p.prosecdef)
    and bool_and(p.proconfig @> array['search_path=pg_catalog, public']::text[])
    and count(distinct p.proowner)=1
    and bool_and(p.proowner=(select relowner from pg_class
      where oid=to_regclass('public.user_device_authorizations')))
    and bool_and(not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where acl.grantee=0 and acl.privilege_type='EXECUTE'))
    and bool_and(not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where acl.grantee=(select oid from pg_roles where rolname='anon') and acl.privilege_type='EXECUTE'))
    and bool_and(not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where acl.grantee=(select oid from pg_roles where rolname='authenticated') and acl.privilege_type='EXECUTE'))
    and bool_and(exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where acl.grantee=(select oid from pg_roles where rolname='service_role') and acl.privilege_type='EXECUTE'))
    from (values ('get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and (select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)'))
    and position('performpublic.require_platform_device_backend();' in
    lower(regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)')),'[[:space:]]+','','g')))>0
    and position('wherechallenges.id=p_challenge_idandchallenges.user_id=p_actor_user_idandchallenges.actor_device_id=p_actor_device_idandchallenges.session_id=p_session_id;' in
    lower(regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)')),'[[:space:]]+','','g')))>0
    and position('ifnotfoundorchallenge.credential_idisnullorchallenge.verified_atisnotnullorchallenge.consumed_atisnotnullorchallenge.failed_atisnotnullorchallenge.expires_at<=statement_timestamp()then' in
    lower(regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)')),'[[:space:]]+','','g')))>0
    and position('credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,challenge.credential_id);' in
    lower(regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)')),'[[:space:]]+','','g')))>0
    and (select p.prosrc ~* $step8_encoding$'publicKeyCose'[[:space:]]*,[[:space:]]*translate[[:space:]]*\([[:space:]]*encode[[:space:]]*\([[:space:]]*credential[[:space:]]*\.[[:space:]]*public_key_cose[[:space:]]*,[[:space:]]*'base64'[[:space:]]*\)[[:space:]]*,[[:space:]]*E'\\n\\r'[[:space:]]*,[[:space:]]*''[[:space:]]*\)$step8_encoding$ from pg_proc p
    where p.oid=to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)')))
    and (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
    and (select count(*)=1 and bool_and(not enforcement_enabled) from public.device_authorization_enforcement)
  then 'PASS' else 'BLOCKED' end;
