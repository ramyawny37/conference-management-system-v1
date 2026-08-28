-- Independent read-only predecessor-contract preflight for 20260828145000.
with latest as (select version,name from supabase_migrations.schema_migrations order by version desc limit 1)
select case when (select version='20260828144000' and name='production_pending_device_operation_purpose_variable_reconciliation_6_20_9' from latest)
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260828144000'
      and name='production_pending_device_operation_purpose_variable_reconciliation_6_20_9' and md5(coalesce(array_to_string(statements,E'\n'),''))='d44194db2a86d023a04fb67e57fe95f5')
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
    from (values ('complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)') is not null and position('expected_challenge_purpose' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')))>0 and position('complete_system_owner_pending_device_operation.purpose' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')))=0)
    -- Approved Production evidence expects absence; the reviewed safe-present branch is also valid.
    and (to_regprocedure('public.rls_auto_enable()') is null or exists(select 1 from pg_proc
      where oid=to_regprocedure('public.rls_auto_enable()') and pronargs=0))
    and (select count(*)=11 from (values
      ('enforce_launch_conference_member_contract()'),('prevent_null_conference_organization()'),
      ('acquire_conference_lock(uuid,uuid,uuid,integer)'),('renew_conference_lock(uuid,uuid,uuid,integer)'),
      ('release_conference_lock(uuid,uuid,uuid)'),('get_conference_lock(uuid,uuid)'),
      ('get_conference_section_lock(uuid,text,uuid)'),('is_conference_member(uuid)'),
      ('has_conference_role(uuid,text[])'),('is_conference_owner(uuid)'),
      ('complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')) required(signature)
      where to_regprocedure('public.'||required.signature) is not null)
    and (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
    and (select count(*)=1 and bool_and(not enforcement_enabled) from public.device_authorization_enforcement)
  then 'PASS' else 'BLOCKED' end;
