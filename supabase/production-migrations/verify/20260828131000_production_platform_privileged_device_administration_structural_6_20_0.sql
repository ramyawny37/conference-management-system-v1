-- Independent read-only resulting-contract verifier for 20260828131000.
select case when exists(select 1 from supabase_migrations.schema_migrations
    where version='20260828131000' and name='production_platform_privileged_device_administration_structural_6_20_0') and ((select count(*)=9 and bool_and(c.relrowsecurity) and count(distinct c.relowner)=1
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
      E'\n' order by i.tablename,i.indexname),'')) from pg_indexes i
      where i.schemaname='public' and i.tablename=any(array[
      'webauthn_privileged_device_feature','device_security_credentials',
      'device_possession_challenges','device_possession_challenge_consumers',
      'privileged_device_listing_sessions','system_owner_credential_bootstrap_authorizations',
      'system_owner_credential_recovery_authorizations','privileged_device_authorization_audit_log',
      'system_owner_device_authorization_operations']))='5059f8c84bc709b10cdc258660de52b9' and (select count(*)=13 and bool_and(p.prosecdef)
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
    from (values ('require_platform_device_backend()'),('require_system_owner_webauthn_actor(uuid,uuid,uuid)'),('begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)'),('issue_system_owner_credential_bootstrap_authorization(uuid,uuid,uuid,uuid,text,bytea,text,text,text)'),('get_system_owner_platform_device_administration_state(uuid,uuid)'),('complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)'),('begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)'),('complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)'),('get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)'),('fail_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text)'),('list_system_owner_pending_device_authorizations(uuid,uuid,uuid,text,bytea)'),('complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)'),('get_system_owner_device_operation_result(uuid,uuid,uuid,uuid,uuid,text,text)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature))) then 'PASS' else 'BLOCKED' end,
  (select enabled from public.webauthn_privileged_device_feature where singleton_id=1),
  (select enforcement_enabled from public.device_authorization_enforcement where singleton_id=1);
