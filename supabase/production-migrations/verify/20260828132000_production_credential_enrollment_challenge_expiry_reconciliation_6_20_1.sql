-- Independent read-only resulting-contract verifier for 20260828132000.
select case when exists(select 1 from supabase_migrations.schema_migrations
    where version='20260828132000' and name='production_credential_enrollment_challenge_expiry_reconciliation_6_20_1') and ((select count(*)=1 and bool_and(p.prosecdef)
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
    from (values ('begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and (select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)')) and to_regprocedure('public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)') is not null and position('statement_timestamp()+interval''2minutes''' in
    regexp_replace(pg_get_functiondef(to_regprocedure('public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)')),'[[:space:]]+','','g'))>0) then 'PASS' else 'BLOCKED' end,
  (select enabled from public.webauthn_privileged_device_feature where singleton_id=1),
  (select enforcement_enabled from public.device_authorization_enforcement where singleton_id=1);
