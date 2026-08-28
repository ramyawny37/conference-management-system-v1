-- Independent read-only bridge post-verifier.
with relations as (select c.oid,c.relowner,c.relrowsecurity from (values
  ('webauthn_privileged_device_feature'),('device_security_credentials'),
  ('device_possession_challenges'),('device_possession_challenge_consumers'),
  ('privileged_device_listing_sessions'),('system_owner_credential_bootstrap_authorizations'),
  ('system_owner_credential_recovery_authorizations'),('privileged_device_authorization_audit_log'),
  ('system_owner_device_authorization_operations')) v(name)
  left join pg_class c on c.oid=to_regclass('public.'||v.name)),
functions as (select to_regprocedure('public.'||v.signature) oid from (values
  ('guard_device_security_credential_lifecycle()'),
  ('guard_device_authorization_security_credential_state()'),
  ('guard_device_possession_challenge_identity()'),('guard_device_possession_challenge_consumer()'),
  ('guard_privileged_device_listing_session_lifecycle()'),
  ('guard_system_owner_bootstrap_authorization_lifecycle()'),
  ('guard_system_owner_recovery_authorization_lifecycle()')) v(signature)),
qualified_triggers as (select t.oid from (values
  ('device_security_credentials_lifecycle_guard','device_security_credentials'),
  ('user_device_authorizations_security_credential_guard','user_device_authorizations'),
  ('device_possession_challenges_identity_guard','device_possession_challenges'),
  ('device_possession_challenge_consumers_guard','device_possession_challenge_consumers'),
  ('privileged_device_listing_sessions_lifecycle_guard','privileged_device_listing_sessions'),
  ('system_owner_bootstrap_authorizations_lifecycle_guard','system_owner_credential_bootstrap_authorizations'),
  ('system_owner_recovery_authorizations_lifecycle_guard','system_owner_credential_recovery_authorizations'),
  ('privileged_device_authorization_audit_immutable','privileged_device_authorization_audit_log'),
  ('system_owner_device_authorization_operations_immutable','system_owner_device_authorization_operations')) v(trigger_name,relation_name)
  left join pg_class c on c.oid=to_regclass('public.'||v.relation_name)
  left join pg_trigger t on t.tgrelid=c.oid and t.tgname=v.trigger_name and not t.tgisinternal)
select case when exists(select 1 from supabase_migrations.schema_migrations
    where version='20260828130000' and name='production_platform_foundation_lineage_bridge')
  and (select count(*)=9 and bool_and(relrowsecurity) and count(distinct relowner)=1
    and bool_and(not exists(select 1 from pg_policy where polrelid=relations.oid))
    and bool_and(not has_table_privilege('anon',relations.oid,'select,insert,update,delete'))
    and bool_and(not has_table_privilege('authenticated',relations.oid,'select,insert,update,delete')) from relations)
  and (select count(*)=7 and bool_and(p.prosecdef)
    and bool_and(p.proconfig @> array['search_path=pg_catalog, public']::text[])
    and bool_and(not has_function_privilege('anon',p.oid,'execute'))
    and bool_and(not has_function_privilege('authenticated',p.oid,'execute'))
    from functions f join pg_proc p on p.oid=f.oid)
  and (select count(oid)=9 from qualified_triggers)
  and position('conference_snapshot_guard_intents' in pg_get_functiondef(to_regprocedure(
    'public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)')))>0
  and position('system_access_admin_operations' in pg_get_functiondef(to_regprocedure(
    'public.device_guarded_manage_system_user(uuid,uuid,uuid,text,boolean)')))>0
  then 'PASS' else 'BLOCKED' end,
  (select enabled from public.webauthn_privileged_device_feature where singleton_id=1),
  (select enforcement_enabled from public.device_authorization_enforcement where singleton_id=1);
