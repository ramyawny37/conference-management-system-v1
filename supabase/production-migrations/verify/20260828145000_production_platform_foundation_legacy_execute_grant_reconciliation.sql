-- Independent read-only resulting-contract verifier for 20260828145000.
select case when exists(select 1 from supabase_migrations.schema_migrations
    where version='20260828145000' and name='production_platform_foundation_legacy_execute_grant_reconciliation') and ((
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
        or required.role_name<>'PUBLIC' and acl.grantee=(select oid from pg_roles where rolname=required.role_name))))) then 'PASS' else 'BLOCKED' end,
  (select enabled from public.webauthn_privileged_device_feature where singleton_id=1),
  (select enforcement_enabled from public.device_authorization_enforcement where singleton_id=1);
