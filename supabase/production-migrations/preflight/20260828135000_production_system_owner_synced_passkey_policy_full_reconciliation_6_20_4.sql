-- Independent read-only predecessor-contract preflight for 20260828135000.
with latest as (select version,name from supabase_migrations.schema_migrations order by version desc limit 1)
select case when (select version='20260828134000' and name='production_system_owner_synced_passkey_policy_reconciliation_6_20_3' from latest)
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260828134000'
      and name='production_system_owner_synced_passkey_policy_reconciliation_6_20_3' and md5(coalesce(array_to_string(statements,E'\n'),''))='fd8777456bc9937692ec740ab0b7d83e')
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
    from (values ('complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and (select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
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
    where p.oid=to_regprocedure('public.complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)')))
    and (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
    and (select count(*)=1 and bool_and(not enforcement_enabled) from public.device_authorization_enforcement)
  then 'PASS' else 'BLOCKED' end;
