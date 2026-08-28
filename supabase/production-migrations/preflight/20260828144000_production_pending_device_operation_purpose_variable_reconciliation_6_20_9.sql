-- Independent read-only predecessor-contract preflight for 20260828144000.
with latest as (select version,name from supabase_migrations.schema_migrations order by version desc limit 1)
select case when (select version='20260828143000' and name='production_pending_device_operation_purpose_qualification_reconciliation_6_20_8' from latest)
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260828143000'
      and name='production_pending_device_operation_purpose_qualification_reconciliation_6_20_8' and md5(coalesce(array_to_string(statements,E'\n'),''))='234d70bc3af1a1d1d069343cd9f31a7e')
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
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)') is not null and position('complete_system_owner_pending_device_operation.purpose' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')))>0)
    and (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
    and (select count(*)=1 and bool_and(not enforcement_enabled) from public.device_authorization_enforcement)
  then 'PASS' else 'BLOCKED' end;
