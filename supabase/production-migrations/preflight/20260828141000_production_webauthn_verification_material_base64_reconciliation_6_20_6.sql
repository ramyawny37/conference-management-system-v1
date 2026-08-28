-- Independent read-only predecessor-contract preflight for 20260828141000.
with latest as (select version,name from supabase_migrations.schema_migrations order by version desc limit 1)
select case when (select version='20260828140000' and name='production_webauthn_time_boundary_reconciliation_6_20_5' from latest)
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260828140000'
      and name='production_webauthn_time_boundary_reconciliation_6_20_5' and md5(coalesce(array_to_string(statements,E'\n'),''))='f387c81e6cd768a32d46e7b177f49478')
    and ((select count(*)=2 and bool_and(p.prosecdef)
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
      where p.oid=to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)')),'[[:space:]]+','','g'))>0)
    and (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
    and (select count(*)=1 and bool_and(not enforcement_enabled) from public.device_authorization_enforcement)
  then 'PASS' else 'BLOCKED' end;
