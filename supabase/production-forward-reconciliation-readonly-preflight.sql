-- Phase 2AC: Production forward-reconciliation read-only preflight.
-- Target project: mpezfbvcdfxpgflehuot only.
--
-- This is one SELECT statement. It never changes schema, data, grants,
-- feature flags, enforcement state, or migration history. Consumers MUST stop
-- unless the lineage_gate row reports PASS.

with
expected_lineage(ordinal,version,name,content_md5) as (
  values
    (1,'20260824121653','20260824_6_15_0_organization_membership_reconciliation',
      'cb5c461d6a8b0f20d814d2984ce5214f'),
    (2,'20260824180055','20260824_6_16_0_webauthn_privileged_device_security_foundation',
      '1776e168f18f0a587192ad0d60c621ae'),
    (3,'20260826191608','conference_authorization_chain_hardening_6_17_0',
      'ca136f8ef4e70b7a74f43b47142bdc14'),
    (4,'20260826191920','conference_lifecycle_hardening_6_18_0',
      '699f1bf58271c8c75d6026ebc0436b28'),
    (5,'20260826193052','snapshot_sync_account_authorization_hardening_6_19_0',
      'b62936c7a81c6a743b206d3ef37ff0e2')
),
actual_lineage as (
  select row_number() over(order by version)::integer ordinal,version,name,
    md5(coalesce(array_to_string(statements,E'\n'),'')) content_md5
  from supabase_migrations.schema_migrations
),
lineage_gate as (
  select count(*) filter(where a.ordinal is null or e.ordinal is null
      or a.version<>e.version or a.name<>e.name
      or a.content_md5<>e.content_md5)=0
      and (select count(*) from actual_lineage)=5 as exact_match
  from expected_lineage e full join actual_lineage a using(ordinal)
),
foundation_relations(name) as (
  values ('webauthn_privileged_device_feature'),('device_security_credentials'),
    ('device_possession_challenges'),('device_possession_challenge_consumers'),
    ('privileged_device_listing_sessions'),
    ('system_owner_credential_bootstrap_authorizations'),
    ('system_owner_credential_recovery_authorizations'),
    ('privileged_device_authorization_audit_log'),
    ('system_owner_device_authorization_operations')
),
foundation_functions(signature) as (
  values ('guard_device_security_credential_lifecycle()'),
    ('guard_device_authorization_security_credential_state()'),
    ('guard_device_possession_challenge_identity()'),
    ('guard_device_possession_challenge_consumer()'),
    ('guard_privileged_device_listing_session_lifecycle()'),
    ('guard_system_owner_bootstrap_authorization_lifecycle()'),
    ('guard_system_owner_recovery_authorization_lifecycle()')
),
foundation_triggers(name) as (
  values ('device_security_credentials_lifecycle_guard'),
    ('user_device_authorizations_security_credential_guard'),
    ('device_possession_challenges_identity_guard'),
    ('device_possession_challenge_consumers_guard'),
    ('privileged_device_listing_sessions_lifecycle_guard'),
    ('system_owner_bootstrap_authorizations_lifecycle_guard'),
    ('system_owner_recovery_authorizations_lifecycle_guard'),
    ('privileged_device_authorization_audit_immutable'),
    ('system_owner_device_authorization_operations_immutable')
),
expected_fingerprints(kind,value) as (
  values ('columns','829e417fab214943e2b6d17376e45c59'),
    ('constraints','223e7c5b07516baf39328d71351be2bb'),
    ('functions','8f7e36012b64b5280a895e288fff2948'),
    ('indexes','5059f8c84bc709b10cdc258660de52b9'),
    ('triggers','7ecaddcfc4b496a13aa1c27b82e1953f')
),
actual_fingerprints as (
  select 'columns' kind,md5(coalesce(string_agg(
    c.table_name||'|'||c.ordinal_position||'|'||c.column_name||'|'||
    c.data_type||'|'||c.is_nullable||'|'||coalesce(c.column_default,''),
    E'\n' order by c.table_name,c.ordinal_position),'')) value
  from information_schema.columns c join foundation_relations f
    on f.name=c.table_name where c.table_schema='public'
  union all
  select 'constraints',md5(coalesce(string_agg(
    cl.relname||'|'||con.conname||'|'||con.contype::text||'|'||
    pg_get_constraintdef(con.oid,true),E'\n' order by cl.relname,con.conname),''))
  from pg_constraint con join pg_class cl on cl.oid=con.conrelid
  join pg_namespace n on n.oid=cl.relnamespace
  join foundation_relations f on f.name=cl.relname where n.nspname='public'
  union all
  select 'indexes',md5(coalesce(string_agg(
    i.tablename||'|'||i.indexname||'|'||i.indexdef,
    E'\n' order by i.tablename,i.indexname),''))
  from pg_indexes i join foundation_relations f on f.name=i.tablename
  where i.schemaname='public'
  union all
  select 'functions',md5(coalesce(string_agg(ff.signature||'|'||
    coalesce(pg_get_functiondef(to_regprocedure('public.'||ff.signature)),'MISSING'),
    E'\n' order by ff.signature),'')) from foundation_functions ff
  union all
  select 'triggers',md5(coalesce(string_agg(ft.name||'|'||
    coalesce(pg_get_triggerdef(t.oid,true),'MISSING'),E'\n' order by ft.name),''))
  from foundation_triggers ft left join pg_trigger t
    on t.tgname=ft.name and not t.tgisinternal
),
relation_inventory as (
  select f.name,c.oid is not null present,c.relrowsecurity rls_enabled,
    pg_get_userbyid(c.relowner) owner_name,
    (select pg_get_userbyid(relowner) from pg_class
      where oid='public.user_device_authorizations'::regclass) controlled_owner,
    exists(select 1 from pg_policy p where p.polrelid=c.oid) has_policy,
    coalesce(has_table_privilege('anon','public.'||f.name,
      'select,insert,update,delete'),false) anon_data_privilege,
    coalesce(has_table_privilege('authenticated','public.'||f.name,
      'select,insert,update,delete'),false) authenticated_data_privilege
  from foundation_relations f left join pg_class c
    on c.oid=to_regclass('public.'||f.name)
),
function_inventory as (
  select f.signature,p.oid is not null present,p.prosecdef security_definer,
    p.proconfig,pg_get_userbyid(p.proowner) owner_name,
    coalesce(has_function_privilege('anon',p.oid,'execute'),false) anon_execute,
    coalesce(has_function_privilege('authenticated',p.oid,'execute'),false)
      authenticated_execute,
    coalesce(has_function_privilege('service_role',p.oid,'execute'),false)
      service_role_execute
  from foundation_functions f left join pg_proc p
    on p.oid=to_regprocedure('public.'||f.signature)
),
data_checks(check_name,violation_count) as (
  values
    ('conference_null_organization',
      (select count(*) from public.conferences where organization_id is null)),
    ('conference_organization_membership_gap',
      (select count(*) from public.conference_members cm
       join public.conferences c on c.id=cm.conference_id
       left join public.organization_members om
         on om.organization_id=c.organization_id and om.user_id=cm.user_id
       where c.organization_id is null or om.user_id is null)),
    ('conference_member_orphan_user',
      (select count(*) from public.conference_members cm
       left join auth.users u on u.id=cm.user_id where u.id is null)),
    ('organization_member_orphan_user',
      (select count(*) from public.organization_members om
       left join auth.users u on u.id=om.user_id where u.id is null)),
    ('device_authorization_pair_gap',
      (select count(*) from public.user_device_authorizations uda
       left join public.devices d on d.id=uda.device_id and d.user_id=uda.user_id
       where d.id is null)),
    ('credential_authorization_gap',
      (select count(*) from public.device_security_credentials c
       left join public.user_device_authorizations uda
         on uda.user_id=c.user_id and uda.device_id=c.device_id
       where uda.device_id is null)),
    ('invalid_credential_backup_state',
      (select count(*) from public.device_security_credentials
       where backup_state and not backup_eligible)),
    ('invalid_privileged_audit_backup_state',
      (select count(*) from public.privileged_device_authorization_audit_log
       where backup_state and not backup_eligible)),
    ('challenge_orphan_actor_authorization',
      (select count(*) from public.device_possession_challenges c
       left join public.user_device_authorizations uda
         on uda.user_id=c.user_id and uda.device_id=c.actor_device_id
       where uda.device_id is null)),
    ('challenge_consumer_orphan_challenge',
      (select count(*) from public.device_possession_challenge_consumers c
       left join public.device_possession_challenges ch on ch.id=c.challenge_id
       where ch.id is null)),
    ('listing_session_orphan_challenge',
      (select count(*) from public.privileged_device_listing_sessions s
       left join public.device_possession_challenges ch
         on ch.id=s.source_challenge_id where ch.id is null)),
    ('platform_operation_orphan_challenge',
      (select count(*) from public.system_owner_device_authorization_operations o
       left join public.device_possession_challenges ch on ch.id=o.challenge_id
       where ch.id is null)),
    ('duplicate_device_authorization_pair',
      (select count(*) from (select user_id,device_id from
        public.user_device_authorizations group by user_id,device_id
        having count(*)>1) duplicates)),
    ('duplicate_webauthn_credential_id',
      (select count(*) from (select webauthn_credential_id from
        public.device_security_credentials group by webauthn_credential_id
        having count(*)>1) duplicates))
),
legacy_grants as (
  select p.proname,pg_get_function_identity_arguments(p.oid) arguments,
    has_function_privilege('public',p.oid,'execute') public_execute,
    has_function_privilege('anon',p.oid,'execute') anon_execute,
    has_function_privilege('authenticated',p.oid,'execute') authenticated_execute
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'rls_auto_enable','enforce_launch_conference_member_contract',
    'prevent_null_conference_organization','acquire_conference_lock',
    'renew_conference_lock','release_conference_lock','get_conference_lock',
    'get_conference_section_lock','is_conference_member',
    'has_conference_role','is_conference_owner')
),
report(section,item,status,details) as (
  select 'identity','database_session','OBSERVED',jsonb_build_object(
    'database',current_database(),'sessionUser',session_user,
    'serverVersion',current_setting('server_version'),'observedAt',now())
  union all
  select 'lineage','lineage_gate',case when exact_match then 'PASS'
    else 'LINEAGE_MISMATCH_FAIL_CLOSED' end,
    jsonb_build_object('expectedRows',5,'actualRows',(select count(*) from actual_lineage),
      'latestExpected','20260826193052') from lineage_gate
  union all
  select 'lineage',lpad(a.ordinal::text,2,'0')||':'||coalesce(a.version,e.version),
    case when a.version=e.version and a.name=e.name and a.content_md5=e.content_md5
      then 'MATCH' else 'MISMATCH' end,
    jsonb_build_object('expectedName',e.name,'actualName',a.name,
      'expectedMd5',e.content_md5,'actualMd5',a.content_md5)
  from expected_lineage e full join actual_lineage a using(ordinal)
  union all
  select 'foundation_fingerprint',e.kind,
    case when a.value=e.value then 'ALREADY_EQUIVALENT' else 'EXISTS_BUT_DIFFERS' end,
    jsonb_build_object('expected',e.value,'actual',a.value)
  from expected_fingerprints e left join actual_fingerprints a using(kind)
  union all
  select 'foundation_relation',name,
    case when not present then 'MISSING'
      when rls_enabled and owner_name=controlled_owner and not has_policy
        and not anon_data_privilege and not authenticated_data_privilege
      then 'ALREADY_EQUIVALENT' else 'EXISTS_BUT_DIFFERS' end,
    jsonb_build_object('present',present,'rls',rls_enabled,'owner',owner_name,
      'controlledOwner',controlled_owner,'hasPolicy',has_policy,
      'anonDataPrivilege',anon_data_privilege,
      'authenticatedDataPrivilege',authenticated_data_privilege)
  from relation_inventory
  union all
  select 'foundation_function',signature,
    case when not present then 'MISSING'
      when security_definer and proconfig @> array['search_path=pg_catalog, public']::text[]
        and not anon_execute and not authenticated_execute
      then 'ALREADY_EQUIVALENT' else 'EXISTS_BUT_DIFFERS' end,
    jsonb_build_object('present',present,'securityDefiner',security_definer,
      'config',proconfig,'owner',owner_name,'anonExecute',anon_execute,
      'authenticatedExecute',authenticated_execute,
      'serviceRoleExecute',service_role_execute)
  from function_inventory
  union all
  select 'foundation_trigger',ft.name,
    case when t.oid is null then 'MISSING' else 'ALREADY_EQUIVALENT' end,
    jsonb_build_object('definition',pg_get_triggerdef(t.oid,true))
  from foundation_triggers ft left join pg_trigger t
    on t.tgname=ft.name and not t.tgisinternal
  union all
  select 'data_compatibility',check_name,
    case when violation_count=0 then 'PASS' else 'BLOCKED' end,
    jsonb_build_object('violations',violation_count) from data_checks
  union all
  select 'security_grant',proname||'('||arguments||')',
    case when public_execute or anon_execute then 'UNSAFE_EXCESS_PRIVILEGE'
      else 'FINAL_STATE' end,
    jsonb_build_object('publicExecute',public_execute,'anonExecute',anon_execute,
      'authenticatedExecute',authenticated_execute) from legacy_grants
  union all
  select 'feature_state','webauthn_privileged_device_feature',
    case when count(*)=1 and bool_and(not enabled) then 'INERT_DISABLED'
      else 'BLOCKED' end,jsonb_build_object('rows',count(*),'enabled',bool_or(enabled))
  from public.webauthn_privileged_device_feature
  union all
  select 'feature_state','device_authorization_enforcement',
    case when count(*)=1 and bool_and(not enforcement_enabled) then 'DISABLED'
      else 'BLOCKED' end,
    jsonb_build_object('rows',count(*),'enabled',bool_or(enforcement_enabled))
  from public.device_authorization_enforcement
  union all
  select 'migration_delta','6.19.0','SATISFIED_BUT_DIFFERENT_PROVENANCE',
    jsonb_build_object('productionMd5','b62936c7a81c6a743b206d3ef37ff0e2',
      'canonicalMd5','3eaf058c2f2041587ed376aa93e3bc50',
      'semanticDelta','predecessor lineage guard only; schema actions are identical',
      'futureAction','recognize immutable Production history; never replay 6.19.0')
  union all
  select 'prerequisite','6.19.1','SATISFIED_BUT_DIFFERENT_PROVENANCE',
    jsonb_build_object('foundation','Production 6.16 body equals 6.19.1 foundation body',
      'application','existing 6.19.1 file must not be applied to Production')
  union all
  select 'prerequisite','6.20.0','REQUIRES_FORWARD_RECONCILIATION',
    jsonb_build_object('foundationReady',
      not exists(select 1 from expected_fingerprints e join actual_fingerprints a using(kind)
        where e.value<>a.value),
      'platformFunctionsPresent',to_regprocedure('public.require_platform_device_backend()') is not null,
      'featureCurrentlyDisabled',(select count(*)=1 and bool_and(not enabled)
        from public.webauthn_privileged_device_feature))
  union all
  select 'prerequisite',v.migration,'BLOCKED_ON_6.20.0_AND_PRIOR_RECONCILIATIONS',
    jsonb_build_object('targetFunctionPresent',
      case v.migration
        when '6.20.1' then to_regprocedure('public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)') is not null
        when '6.20.2' then to_regprocedure('public.begin_system_owner_credential_enrollment(uuid,uuid,uuid,text,text,text,bytea,uuid,bytea)') is not null
        when '6.20.3' then to_regprocedure('public.complete_system_owner_credential_enrollment(uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,bytea,bytea,integer,uuid,text[],bigint,text,text,jsonb)') is not null
        when '6.20.4' then to_regprocedure('public.require_system_owner_webauthn_actor(uuid,uuid,uuid)') is not null
        when '6.20.5' then to_regprocedure('public.begin_system_owner_device_possession_challenge(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,text,text,bytea)') is not null
        when '6.20.6' then to_regprocedure('public.get_system_owner_device_challenge_verification_material(uuid,uuid,uuid,uuid)') is not null
        when '6.20.7' then to_regprocedure('public.complete_system_owner_pending_device_listing(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,bytea,bigint,text,text,jsonb)') is not null
        else to_regprocedure('public.complete_system_owner_pending_device_operation(uuid,uuid,uuid,uuid,text,uuid,bytea,uuid,uuid,uuid,text,bigint,text,text,jsonb)') is not null end)
  from (values ('6.20.1'),('6.20.2'),('6.20.3'),('6.20.4'),('6.20.5'),
    ('6.20.6'),('6.20.7'),('6.20.8'),('6.20.9')) v(migration)
  union all
  select 'prerequisite','legacy_execute_grant_reconciliation',
    case when exists(select 1 from legacy_grants
      where public_execute or anon_execute) then 'REQUIRES_FORWARD_RECONCILIATION'
      else 'SATISFIED' end,
    jsonb_build_object('exposedFunctions',(select count(*) from legacy_grants
      where public_execute or anon_execute))
)
select section,item,status,details from report
order by section,item;
