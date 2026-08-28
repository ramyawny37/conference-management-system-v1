begin;

-- Production-only validation/provenance bridge. This migration deliberately
-- performs no application-schema or business-data mutation. Its successful
-- migration-history row is recorded only by the external migration mechanism.
do $$
declare
  lineage_matches boolean;
  relation_name text;
  function_signature text;
  relation_oid oid;
  function_oid oid;
  controlled_owner oid := (select relowner from pg_class
    where oid=to_regclass('public.user_device_authorizations'));
  actual_fingerprint text;
begin
  with expected(ordinal,version,name,content_md5) as (
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
  ), actual as (
    select row_number() over(order by version)::integer ordinal,version,name,
      md5(coalesce(array_to_string(statements,E'\n'),'')) content_md5
    from supabase_migrations.schema_migrations
  )
  select count(*) filter(where expected.ordinal is null or actual.ordinal is null
      or expected.version<>actual.version or expected.name<>actual.name
      or expected.content_md5<>actual.content_md5)=0
      and (select count(*) from actual)=5
      and (select version from actual order by ordinal desc limit 1)='20260826193052'
    into lineage_matches
  from expected full join actual using(ordinal);
  if not coalesce(lineage_matches,false) then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_EXACT_LINEAGE_REQUIRED';
  end if;

  if controlled_owner is null then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_CONTROLLED_OWNER_MISSING';
  end if;

  foreach relation_name in array array[
    'webauthn_privileged_device_feature','device_security_credentials',
    'device_possession_challenges','device_possession_challenge_consumers',
    'privileged_device_listing_sessions',
    'system_owner_credential_bootstrap_authorizations',
    'system_owner_credential_recovery_authorizations',
    'privileged_device_authorization_audit_log',
    'system_owner_device_authorization_operations'
  ] loop
    relation_oid:=to_regclass('public.'||relation_name);
    if relation_oid is null
      or not (select relrowsecurity from pg_class where oid=relation_oid)
      or (select relowner from pg_class where oid=relation_oid)<>controlled_owner
      or exists(select 1 from pg_policy where polrelid=relation_oid)
      or has_table_privilege('anon',relation_oid,'select,insert,update,delete')
      or has_table_privilege('authenticated',relation_oid,'select,insert,update,delete') then
      raise exception 'PRODUCTION_PLATFORM_BRIDGE_RELATION_SECURITY_DRIFT: %',relation_name;
    end if;
  end loop;

  select md5(coalesce(string_agg(c.table_name||'|'||c.ordinal_position||'|'||
      c.column_name||'|'||c.data_type||'|'||c.is_nullable||'|'||
      coalesce(c.column_default,''),E'\n' order by c.table_name,c.ordinal_position),''))
    into actual_fingerprint
  from information_schema.columns c
  where c.table_schema='public' and c.table_name=any(array[
    'webauthn_privileged_device_feature','device_security_credentials',
    'device_possession_challenges','device_possession_challenge_consumers',
    'privileged_device_listing_sessions','system_owner_credential_bootstrap_authorizations',
    'system_owner_credential_recovery_authorizations',
    'privileged_device_authorization_audit_log','system_owner_device_authorization_operations']);
  if actual_fingerprint<>'829e417fab214943e2b6d17376e45c59' then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_COLUMN_FINGERPRINT_DRIFT';
  end if;

  select md5(coalesce(string_agg(cl.relname||'|'||con.conname||'|'||
      con.contype::text||'|'||pg_get_constraintdef(con.oid,true),
      E'\n' order by cl.relname,con.conname),'')) into actual_fingerprint
  from pg_constraint con join pg_class cl on cl.oid=con.conrelid
  join pg_namespace n on n.oid=cl.relnamespace
  where n.nspname='public' and cl.relname=any(array[
    'webauthn_privileged_device_feature','device_security_credentials',
    'device_possession_challenges','device_possession_challenge_consumers',
    'privileged_device_listing_sessions','system_owner_credential_bootstrap_authorizations',
    'system_owner_credential_recovery_authorizations',
    'privileged_device_authorization_audit_log','system_owner_device_authorization_operations']);
  if actual_fingerprint<>'223e7c5b07516baf39328d71351be2bb' then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_CONSTRAINT_FINGERPRINT_DRIFT';
  end if;

  select md5(coalesce(string_agg(i.tablename||'|'||i.indexname||'|'||i.indexdef,
      E'\n' order by i.tablename,i.indexname),'')) into actual_fingerprint
  from pg_indexes i where i.schemaname='public' and i.tablename=any(array[
    'webauthn_privileged_device_feature','device_security_credentials',
    'device_possession_challenges','device_possession_challenge_consumers',
    'privileged_device_listing_sessions','system_owner_credential_bootstrap_authorizations',
    'system_owner_credential_recovery_authorizations',
    'privileged_device_authorization_audit_log','system_owner_device_authorization_operations']);
  if actual_fingerprint<>'5059f8c84bc709b10cdc258660de52b9' then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_INDEX_FINGERPRINT_DRIFT';
  end if;

  foreach function_signature in array array[
    'guard_device_security_credential_lifecycle()',
    'guard_device_authorization_security_credential_state()',
    'guard_device_possession_challenge_identity()',
    'guard_device_possession_challenge_consumer()',
    'guard_privileged_device_listing_session_lifecycle()',
    'guard_system_owner_bootstrap_authorization_lifecycle()',
    'guard_system_owner_recovery_authorization_lifecycle()'
  ] loop
    function_oid:=to_regprocedure('public.'||function_signature);
    if function_oid is null
      or not (select prosecdef from pg_proc where oid=function_oid)
      or not ((select proconfig from pg_proc where oid=function_oid)
        @> array['search_path=pg_catalog, public']::text[])
      or (select proowner from pg_proc where oid=function_oid)<>controlled_owner
      or has_function_privilege('anon',function_oid,'execute')
      or has_function_privilege('authenticated',function_oid,'execute') then
      raise exception 'PRODUCTION_PLATFORM_BRIDGE_FUNCTION_SECURITY_DRIFT: %',function_signature;
    end if;
  end loop;

  select md5(coalesce(string_agg(v.signature||'|'||
      coalesce(pg_get_functiondef(to_regprocedure('public.'||v.signature)),'MISSING'),
      E'\n' order by v.signature),'')) into actual_fingerprint
  from (values ('guard_device_security_credential_lifecycle()'),
    ('guard_device_authorization_security_credential_state()'),
    ('guard_device_possession_challenge_identity()'),
    ('guard_device_possession_challenge_consumer()'),
    ('guard_privileged_device_listing_session_lifecycle()'),
    ('guard_system_owner_bootstrap_authorization_lifecycle()'),
    ('guard_system_owner_recovery_authorization_lifecycle()')) v(signature);
  if actual_fingerprint<>'8f7e36012b64b5280a895e288fff2948' then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_FUNCTION_FINGERPRINT_DRIFT';
  end if;

  select md5(coalesce(string_agg(v.name||'|'||
      coalesce(pg_get_triggerdef(t.oid,true),'MISSING'),E'\n' order by v.name),''))
    into actual_fingerprint
  from (values ('device_security_credentials_lifecycle_guard'),
    ('user_device_authorizations_security_credential_guard'),
    ('device_possession_challenges_identity_guard'),
    ('device_possession_challenge_consumers_guard'),
    ('privileged_device_listing_sessions_lifecycle_guard'),
    ('system_owner_bootstrap_authorizations_lifecycle_guard'),
    ('system_owner_recovery_authorizations_lifecycle_guard'),
    ('privileged_device_authorization_audit_immutable'),
    ('system_owner_device_authorization_operations_immutable')) v(name)
  left join pg_trigger t on t.tgname=v.name and not t.tgisinternal;
  if actual_fingerprint<>'7ecaddcfc4b496a13aa1c27b82e1953f' then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_TRIGGER_FINGERPRINT_DRIFT';
  end if;

  if (select count(*)<>1 or coalesce(bool_or(enabled),true)
      from public.webauthn_privileged_device_feature)
    or (select count(*)<>1 or coalesce(bool_or(enforcement_enabled),true)
      from public.device_authorization_enforcement) then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_INERT_STATE_REQUIRED';
  end if;
  if exists(select 1 from public.device_security_credentials)
    or exists(select 1 from public.device_possession_challenges)
    or exists(select 1 from public.device_possession_challenge_consumers)
    or exists(select 1 from public.privileged_device_listing_sessions)
    or exists(select 1 from public.system_owner_credential_bootstrap_authorizations)
    or exists(select 1 from public.system_owner_credential_recovery_authorizations)
    or exists(select 1 from public.privileged_device_authorization_audit_log)
    or exists(select 1 from public.system_owner_device_authorization_operations) then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_UNEXPECTED_RUNTIME_STATE';
  end if;

  if to_regprocedure('public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)') is null
    or to_regprocedure('public.device_guarded_resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)') is null
    or to_regprocedure('public.device_guarded_manage_system_user(uuid,uuid,uuid,text,boolean)') is null
    or not has_function_privilege('authenticated',
      'public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)','execute')
    or not has_function_privilege('authenticated',
      'public.device_guarded_resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)','execute')
    or not has_function_privilege('authenticated',
      'public.device_guarded_manage_system_user(uuid,uuid,uuid,text,boolean)','execute')
    or has_function_privilege('authenticated',
      'public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)','execute')
    or has_function_privilege('authenticated',
      'public.resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)','execute') then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_6_19_RESULTING_CONTRACT_REQUIRED';
  end if;

  if exists(select 1 from public.conferences where organization_id is null)
    or exists(select 1 from public.conference_members cm
      join public.conferences c on c.id=cm.conference_id
      left join public.organization_members om
        on om.organization_id=c.organization_id and om.user_id=cm.user_id
      where c.organization_id is null or om.user_id is null)
    or exists(select 1 from public.conference_members cm
      left join auth.users u on u.id=cm.user_id where u.id is null)
    or exists(select 1 from public.organization_members om
      left join auth.users u on u.id=om.user_id where u.id is null)
    or exists(select 1 from public.user_device_authorizations uda
      left join public.devices d on d.id=uda.device_id and d.user_id=uda.user_id
      where d.id is null)
    or exists(select 1 from (select user_id,device_id
      from public.user_device_authorizations group by user_id,device_id
      having count(*)>1) duplicate_pairs)
    or exists(select 1 from public.device_security_credentials credentials
      left join public.user_device_authorizations uda
        on uda.user_id=credentials.user_id and uda.device_id=credentials.device_id
      where uda.device_id is null)
    or exists(select 1 from public.device_security_credentials
      where backup_state and not backup_eligible)
    or exists(select 1 from public.privileged_device_authorization_audit_log
      where backup_state and not backup_eligible)
    or exists(select 1 from public.device_possession_challenges challenges
      left join public.user_device_authorizations uda
        on uda.user_id=challenges.user_id and uda.device_id=challenges.actor_device_id
      where uda.device_id is null)
    or exists(select 1 from public.device_possession_challenge_consumers consumers
      left join public.device_possession_challenges challenges
        on challenges.id=consumers.challenge_id where challenges.id is null)
    or exists(select 1 from public.privileged_device_listing_sessions sessions
      left join public.device_possession_challenges challenges
        on challenges.id=sessions.source_challenge_id where challenges.id is null)
    or exists(select 1 from public.system_owner_device_authorization_operations operations
      left join public.device_possession_challenges challenges
        on challenges.id=operations.challenge_id where challenges.id is null)
    or exists(select 1 from (select webauthn_credential_id
      from public.device_security_credentials group by webauthn_credential_id
      having count(*)>1) duplicate_credentials) then
    raise exception 'PRODUCTION_PLATFORM_BRIDGE_DATA_COMPATIBILITY_REQUIRED';
  end if;
end;
$$;

commit;
