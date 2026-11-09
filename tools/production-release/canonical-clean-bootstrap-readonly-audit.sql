-- Canonical production replacement: read-only baseline acceptance inventory
-- Run against DEVELOPMENT first, then against an isolated freshly bootstrapped database.
-- This is a SELECT-only audit; it never modifies business data, Auth, or migration history.
WITH expected_schemas(name) AS (
  VALUES ('public'),('platform'),('platform_private'),('reservations'),('reservations_private')
), relations AS (
  SELECT n.nspname AS schema_name,
         count(*) FILTER (WHERE c.relkind IN ('r','p')) AS table_count,
         count(*) FILTER (WHERE c.relkind IN ('r','p') AND c.relrowsecurity) AS rls_count,
         count(*) FILTER (WHERE c.relkind = 'v') AS view_count
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN (SELECT name FROM expected_schemas)
  GROUP BY n.nspname
), functions AS (
  SELECT n.nspname AS schema_name, count(*) AS function_count
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN (SELECT name FROM expected_schemas)
  GROUP BY n.nspname
)
SELECT e.name AS schema_name,
       (to_regnamespace(e.name) IS NOT NULL) AS schema_exists,
       coalesce(r.table_count,0) AS tables,
       coalesce(r.rls_count,0) AS rls_tables,
       coalesce(r.view_count,0) AS views,
       coalesce(f.function_count,0) AS functions
FROM expected_schemas e
LEFT JOIN relations r ON r.schema_name=e.name
LEFT JOIN functions f ON f.schema_name=e.name
ORDER BY e.name;

-- Security-sensitive first-owner contracts; checks signatures, NOT private tokens.
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       p.proconfig AS function_settings
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('complete_first_system_bootstrap','get_first_system_bootstrap_status')
ORDER BY p.proname;

-- The bootstrap secret must be provisioned for the new owner by an audited,
-- privileged, one-time process. Do NOT inspect or export its secret_hash.
-- The first-system bootstrap grants owner role but does NOT itself approve a device.

-- Exposed application tables without RLS are a release blocker.
SELECT n.nspname AS schema_name,c.relname AS table_name
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','platform','reservations')
  AND c.relkind IN ('r','p')
  AND NOT c.relrowsecurity
ORDER BY 1,2;

-- Check that platform owner reference role exists, without querying any user rows.
SELECT EXISTS (
  SELECT 1 FROM platform.roles
  WHERE domain='platform' AND code='platform_owner'
) AS platform_owner_role_seeded;
