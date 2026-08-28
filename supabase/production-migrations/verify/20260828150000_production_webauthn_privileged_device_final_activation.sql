-- Independent read-only resulting-contract verifier for 20260828150000.
select case when exists(select 1 from supabase_migrations.schema_migrations
    where version='20260828150000' and name='production_webauthn_privileged_device_final_activation') and ((select count(*)=9 and bool_and(c.relrowsecurity) and count(distinct c.relowner)=1
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
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature))
    and (select count(*)=1 and bool_and(p.prosecdef)
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
    and position('p_environment,now()+interval''2minutes'')' in
      regexp_replace(p.prosrc,'[[:space:]]+','','g'))>0
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)')) and (select count(*)=1 and bool_and(p.prosecdef)
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
    where p.oid=to_regprocedure('public.complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)'))
    and exists(select 1 from pg_constraint where conrelid='public.device_security_credentials'::regclass and conname='device_security_credentials_non_backup_policy' and pg_get_constraintdef(oid,true) like '%NOT backup_state OR backup_eligible%') and (select count(*)=2 and bool_and(p.prosecdef)
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
    from (values ('complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)'),('complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)') is not null and position('backupState' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')))>0 and position('backupEligible' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')))>0
    and exists(select 1 from pg_constraint
      where conrelid='public.privileged_device_authorization_audit_log'::regclass
      and conname='privileged_device_audit_webauthn_policy'
      and pg_get_constraintdef(oid,true) like '%NOT backup_state OR backup_eligible%')
    and (select count(*)=2 and bool_and(p.prosecdef)
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
    from (values ('begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)'),('complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and (select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)')) and (select pg_get_function_result(p.oid)='jsonb' and l.lanname='plpgsql'
    and p.prosecdef and p.provolatile='v' and p.proparallel='u' and not p.proisstrict
    from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)'))
    and position('credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,p_credential_id)' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)')),'[[:space:]]+','','g'))>0
    and position('p_purposenotin(''SYSTEM_OWNER_PENDING_DEVICE_LIST'',''SYSTEM_OWNER_PENDING_DEVICE_APPROVE'',''SYSTEM_OWNER_PENDING_DEVICE_REJECT'')' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)')),'[[:space:]]+','','g'))>0
    and position('p_environment,now()+interval''2minutes'')returningidintochallenge_id' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)')),'[[:space:]]+','','g'))>0
    and position('credential:=public.require_system_owner_webauthn_actor(p_actor_user_id,p_actor_device_id,p_credential_id)' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')),'[[:space:]]+','','g'))>0
    and position('challenges.purpose=''SYSTEM_OWNER_PENDING_DEVICE_LIST''' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')),'[[:space:]]+','','g'))>0
    and position('challenges.environment=p_environment' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')),'[[:space:]]+','','g'))>0
    and position('p_environment,''SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY'',now()+interval''5minutes'');' in
    regexp_replace((select p.prosrc from pg_proc p
      where p.oid=to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')),'[[:space:]]+','','g'))>0
    and (select count(*)=1 and bool_and(p.prosecdef)
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
    where p.oid=to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)')) and (select count(*)=1 and bool_and(p.prosecdef)
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
    from (values ('complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')) required(signature)
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and exists(select 1 from information_schema.columns where table_schema='public' and table_name='privileged_device_listing_sessions' and column_name='source_challenge_purpose') and to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)') is not null and position('source_challenge_purpose' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')))>0 and position('SYSTEM_OWNER_PENDING_DEVICE_LIST_READ_ONLY' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')))>0
    and (select count(*)=1 and bool_and(p.prosecdef)
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
    join pg_proc p on p.oid=to_regprocedure('public.'||required.signature)) and to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)') is not null and position('expected_challenge_purpose' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')))>0 and position('complete_system_owner_pending_device_operation.purpose' in pg_get_functiondef(to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)')))=0 and (
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
