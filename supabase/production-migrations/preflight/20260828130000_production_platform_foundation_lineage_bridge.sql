-- Independent read-only predecessor-contract preflight for 20260828130000.
with latest as (select version,name from supabase_migrations.schema_migrations order by version desc limit 1)
select case when (select version='20260826193052' and name='snapshot_sync_account_authorization_hardening_6_19_0' from latest)
    and (select count(*)=5 from supabase_migrations.schema_migrations)
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260824121653' and name='20260824_6_15_0_organization_membership_reconciliation' and md5(coalesce(array_to_string(statements,E'\n'),''))='cb5c461d6a8b0f20d814d2984ce5214f')
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260824180055' and name='20260824_6_16_0_webauthn_privileged_device_security_foundation' and md5(coalesce(array_to_string(statements,E'\n'),''))='1776e168f18f0a587192ad0d60c621ae')
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260826191608' and md5(coalesce(array_to_string(statements,E'\n'),''))='ca136f8ef4e70b7a74f43b47142bdc14')
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260826191920' and md5(coalesce(array_to_string(statements,E'\n'),''))='699f1bf58271c8c75d6026ebc0436b28')
    and exists(select 1 from supabase_migrations.schema_migrations where version='20260826193052' and md5(coalesce(array_to_string(statements,E'\n'),''))='b62936c7a81c6a743b206d3ef37ff0e2')
    and (select count(*)=1 and bool_and(not enabled) from public.webauthn_privileged_device_feature)
    and (select count(*)=1 and bool_and(not enforcement_enabled) from public.device_authorization_enforcement)
  then 'PASS' else 'BLOCKED' end;
