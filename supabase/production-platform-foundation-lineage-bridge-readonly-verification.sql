-- Read-only companion verification for the Production platform bridge.
-- Safe before or after the bridge: it reports readiness and never mutates state.
with expected_history(ordinal,version,name,content_md5) as (
  values
    (1,'20260824121653','20260824_6_15_0_organization_membership_reconciliation','cb5c461d6a8b0f20d814d2984ce5214f'),
    (2,'20260824180055','20260824_6_16_0_webauthn_privileged_device_security_foundation','1776e168f18f0a587192ad0d60c621ae'),
    (3,'20260826191608','conference_authorization_chain_hardening_6_17_0','ca136f8ef4e70b7a74f43b47142bdc14'),
    (4,'20260826191920','conference_lifecycle_hardening_6_18_0','699f1bf58271c8c75d6026ebc0436b28'),
    (5,'20260826193052','snapshot_sync_account_authorization_hardening_6_19_0','b62936c7a81c6a743b206d3ef37ff0e2')
), actual_history as (
  select row_number() over(order by version)::integer ordinal,version,name,
    md5(coalesce(array_to_string(statements,E'\n'),'')) content_md5
  from supabase_migrations.schema_migrations
  where version<>'20260828120132'
), foundation_relations(name) as (
  values ('webauthn_privileged_device_feature'),('device_security_credentials'),
    ('device_possession_challenges'),('device_possession_challenge_consumers'),
    ('privileged_device_listing_sessions'),
    ('system_owner_credential_bootstrap_authorizations'),
    ('system_owner_credential_recovery_authorizations'),
    ('privileged_device_authorization_audit_log'),
    ('system_owner_device_authorization_operations')
), expected_fingerprints(kind,value) as (
  values ('columns','829e417fab214943e2b6d17376e45c59'),
    ('constraints','223e7c5b07516baf39328d71351be2bb'),
    ('functions','8f7e36012b64b5280a895e288fff2948'),
    ('indexes','5059f8c84bc709b10cdc258660de52b9'),
    ('triggers','7ecaddcfc4b496a13aa1c27b82e1953f')
), actual_fingerprints(kind,value) as (
  select 'columns',md5(coalesce(string_agg(c.table_name||'|'||c.ordinal_position||'|'||
    c.column_name||'|'||c.data_type||'|'||c.is_nullable||'|'||coalesce(c.column_default,''),
    E'\n' order by c.table_name,c.ordinal_position),''))
  from information_schema.columns c join foundation_relations f on f.name=c.table_name
  where c.table_schema='public'
  union all select 'constraints',md5(coalesce(string_agg(cl.relname||'|'||con.conname||'|'||
    con.contype::text||'|'||pg_get_constraintdef(con.oid,true),
    E'\n' order by cl.relname,con.conname),''))
  from pg_constraint con join pg_class cl on cl.oid=con.conrelid
  join pg_namespace n on n.oid=cl.relnamespace join foundation_relations f on f.name=cl.relname
  where n.nspname='public'
  union all select 'indexes',md5(coalesce(string_agg(i.tablename||'|'||i.indexname||'|'||
    i.indexdef,E'\n' order by i.tablename,i.indexname),''))
  from pg_indexes i join foundation_relations f on f.name=i.tablename where i.schemaname='public'
  union all select 'functions',md5(coalesce(string_agg(v.signature||'|'||
    coalesce(pg_get_functiondef(to_regprocedure('public.'||v.signature)),'MISSING'),
    E'\n' order by v.signature),'')) from (values
      ('guard_device_security_credential_lifecycle()'),
      ('guard_device_authorization_security_credential_state()'),
      ('guard_device_possession_challenge_identity()'),
      ('guard_device_possession_challenge_consumer()'),
      ('guard_privileged_device_listing_session_lifecycle()'),
      ('guard_system_owner_bootstrap_authorization_lifecycle()'),
      ('guard_system_owner_recovery_authorization_lifecycle()')) v(signature)
  union all select 'triggers',md5(coalesce(string_agg(v.name||'|'||
    coalesce(pg_get_triggerdef(t.oid,true),'MISSING'),E'\n' order by v.name),''))
  from (values ('device_security_credentials_lifecycle_guard'),
      ('user_device_authorizations_security_credential_guard'),
      ('device_possession_challenges_identity_guard'),
      ('device_possession_challenge_consumers_guard'),
      ('privileged_device_listing_sessions_lifecycle_guard'),
      ('system_owner_bootstrap_authorizations_lifecycle_guard'),
      ('system_owner_recovery_authorizations_lifecycle_guard'),
      ('privileged_device_authorization_audit_immutable'),
      ('system_owner_device_authorization_operations_immutable')) v(name)
    left join pg_trigger t on t.tgname=v.name and not t.tgisinternal
), data_violations as (
  select count(*)::bigint violations from public.conferences where organization_id is null
  union all select count(*) from public.conference_members cm join public.conferences c
    on c.id=cm.conference_id left join public.organization_members om
    on om.organization_id=c.organization_id and om.user_id=cm.user_id where om.user_id is null
  union all select count(*) from public.conference_members cm left join auth.users u
    on u.id=cm.user_id where u.id is null
  union all select count(*) from public.organization_members om left join auth.users u
    on u.id=om.user_id where u.id is null
  union all select count(*) from public.user_device_authorizations uda left join public.devices d
    on d.id=uda.device_id and d.user_id=uda.user_id where d.id is null
  union all select count(*) from (select user_id,device_id from public.user_device_authorizations
    group by user_id,device_id having count(*)>1) duplicates
  union all select count(*) from public.device_security_credentials c
    left join public.user_device_authorizations uda
    on uda.user_id=c.user_id and uda.device_id=c.device_id where uda.device_id is null
  union all select count(*) from public.device_security_credentials
    where backup_state and not backup_eligible
  union all select count(*) from public.privileged_device_authorization_audit_log
    where backup_state and not backup_eligible
  union all select count(*) from public.device_possession_challenges c
    left join public.user_device_authorizations uda
    on uda.user_id=c.user_id and uda.device_id=c.actor_device_id where uda.device_id is null
  union all select count(*) from public.device_possession_challenge_consumers c
    left join public.device_possession_challenges ch on ch.id=c.challenge_id where ch.id is null
  union all select count(*) from public.privileged_device_listing_sessions s
    left join public.device_possession_challenges ch on ch.id=s.source_challenge_id where ch.id is null
  union all select count(*) from public.system_owner_device_authorization_operations o
    left join public.device_possession_challenges ch on ch.id=o.challenge_id where ch.id is null
  union all select count(*) from (select webauthn_credential_id
    from public.device_security_credentials group by webauthn_credential_id having count(*)>1) duplicates
), checks(item,status,details) as (
  select 'historical_lineage',case when not exists(
      (select * from actual_history except select * from expected_history)
      union all (select * from expected_history except select * from actual_history))
      then 'PASS' else 'BLOCKED' end,
    jsonb_build_object('historicalRows',(select count(*) from actual_history))
  union all select 'bridge_history',case when count(*)=0 then 'NOT_YET_APPLIED'
      when count(*)=1 and bool_and(name='production_platform_foundation_lineage_bridge')
        then 'PASS' else 'BLOCKED' end,
    jsonb_build_object('rows',count(*),'names',jsonb_agg(name))
    from supabase_migrations.schema_migrations where version='20260828120132'
  union all select 'foundation_fingerprints',case when not exists(select 1
      from expected_fingerprints e left join actual_fingerprints a using(kind)
      where a.value is distinct from e.value) then 'PASS' else 'BLOCKED' end,
    jsonb_build_object('matched',(select count(*) from expected_fingerprints e
      join actual_fingerprints a using(kind) where a.value=e.value),'required',5)
  union all select 'inert_state',case when
      (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
      and (select count(*)=1 and bool_and(not enforcement_enabled)
        from public.device_authorization_enforcement)
      then 'PASS' else 'BLOCKED' end,jsonb_build_object('featuresMustRemainDisabled',true)
  union all select 'runtime_state',case when
      (select count(*) from public.device_security_credentials)=0
      and (select count(*) from public.device_possession_challenges)=0
      and (select count(*) from public.device_possession_challenge_consumers)=0
      and (select count(*) from public.privileged_device_listing_sessions)=0
      and (select count(*) from public.system_owner_device_authorization_operations)=0
      then 'PASS' else 'BLOCKED' end,jsonb_build_object('expectedRuntimeRows',0)
  union all select 'data_compatibility',case when coalesce(sum(violations),0)=0
      then 'PASS' else 'BLOCKED' end,
    jsonb_build_object('violations',coalesce(sum(violations),0),'repairsPerformed',false)
    from data_violations
  union all select '6.20.0_readiness_boundary',case when
      to_regclass('public.device_security_credentials') is not null
      and to_regprocedure('public.require_platform_device_backend()') is null
      then 'READY_FOR_INDEPENDENT_PREFLIGHT' else 'BLOCKED' end,
    jsonb_build_object('bridgeDoesNotEnableWebAuthn',true,'bridgeDoesNotCreatePlatformFunctions',true)
)
select item,status,details from checks order by item;
