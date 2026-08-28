-- LAB_ONLY_PRODUCTION_HISTORY_RECONSTRUCTION
-- EXACT_LIVE_PRODUCTION_FIVE_ROW_LINEAGE
-- NEVER EXECUTE AGAINST PRODUCTION OR DEVELOPMENT
begin;
do $guard$
begin
  if current_setting('server_version_num')::integer/10000<>17
    or inet_server_addr() is null
    or inet_server_addr() not in (inet '127.0.0.1',inet '::1')
    or current_database()!~'^phase2a[[:alnum:]_]*$'
    or (select system_identifier::text from pg_control_system())='7662742571317219726' then
    raise exception 'LAB_ONLY_PRODUCTION_HISTORY_TARGET_REFUSED';
  end if;
  if (select count(*) from supabase_migrations.schema_migrations)<>1
    or not exists(select 1 from supabase_migrations.schema_migrations
      where version='20260826191920' and name='conference_lifecycle_hardening_6_18_0'
        and cardinality(statements)=1
        and md5(coalesce(array_to_string(statements,E'\n'),''))='699f1bf58271c8c75d6026ebc0436b28'
        and created_by is null and idempotency_key is null and rollback is null) then
    raise exception 'LAB_ONLY_HISTORY_EXPECTED_ONLY_6_18';
  end if;
  if has_function_privilege('authenticated',
      'public.apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)','execute')
    or has_function_privilege('authenticated',
      'public.resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)','execute')
    or not has_function_privilege('authenticated',
      'public.device_guarded_apply_conference_snapshot(uuid,uuid,uuid,bigint,jsonb,text,text)','execute')
    or not has_function_privilege('authenticated',
      'public.device_guarded_resolve_sync_conflict(uuid,uuid,uuid,uuid,bigint,text,jsonb,text,text)','execute') then
    raise exception 'LAB_ONLY_HISTORY_6_19_RESULT_CONTRACT_MISSING';
  end if;
end;
$guard$;
insert into supabase_migrations.schema_migrations
  (version,statements,name,created_by,idempotency_key,rollback)
values
 ('20260824121653',array[:'history_6_15_body']::text[],
  '20260824_6_15_0_organization_membership_reconciliation',null,null,null),
 ('20260824180055',array[:'history_6_16_body']::text[],
  '20260824_6_16_0_webauthn_privileged_device_security_foundation',null,null,null),
 ('20260826191608',array[:'history_6_17_body']::text[],
  'conference_authorization_chain_hardening_6_17_0',null,null,null),
 ('20260826193052',array[:'history_6_19_body']::text[],
  'snapshot_sync_account_authorization_hardening_6_19_0',null,null,null);
do $post$
declare mismatch_count integer;
begin
  with expected(ordinal,version,name,digest) as (values
    (1,'20260824121653','20260824_6_15_0_organization_membership_reconciliation','cb5c461d6a8b0f20d814d2984ce5214f'),
    (2,'20260824180055','20260824_6_16_0_webauthn_privileged_device_security_foundation','1776e168f18f0a587192ad0d60c621ae'),
    (3,'20260826191608','conference_authorization_chain_hardening_6_17_0','ca136f8ef4e70b7a74f43b47142bdc14'),
    (4,'20260826191920','conference_lifecycle_hardening_6_18_0','699f1bf58271c8c75d6026ebc0436b28'),
    (5,'20260826193052','snapshot_sync_account_authorization_hardening_6_19_0','b62936c7a81c6a743b206d3ef37ff0e2')
  ), actual as (select row_number() over(order by version)::integer ordinal,*,
    md5(coalesce(array_to_string(statements,E'\n'),'')) digest
    from supabase_migrations.schema_migrations)
  select count(*) into mismatch_count from expected full join actual using(ordinal)
  where expected.version is distinct from actual.version or expected.name is distinct from actual.name
    or expected.digest is distinct from actual.digest or cardinality(actual.statements) is distinct from 1
    or actual.created_by is not null or actual.idempotency_key is not null or actual.rollback is not null;
  if mismatch_count<>0 or (select count(*) from supabase_migrations.schema_migrations)<>5 then
    raise exception 'LAB_ONLY_HISTORY_FIVE_ROW_LINEAGE_MISMATCH_%',mismatch_count;
  end if;
end;
$post$;
commit;
