-- Read-only acceptance gate for a complete clean Supabase application foundation.
-- Run AFTER bootstrap on an isolated disposable Supabase-compatible instance.
-- This is NOT an executable foundation and must never mutate Production.
WITH expected(schema_name,tables,views) AS (
 VALUES ('public',46,0),('platform',13,0),('platform_private',11,0),
        ('reservations',15,2),('reservations_private',1,0)
), actual AS (
 SELECT n.nspname::text schema_name,
 count(*) FILTER (WHERE c.relkind IN ('r','p'))::integer tables,
 count(*) FILTER (WHERE c.relkind='v')::integer views
 FROM pg_namespace n LEFT JOIN pg_class c ON c.relnamespace=n.oid
 WHERE n.nspname IN (SELECT schema_name FROM expected)
 GROUP BY n.nspname
), checks AS (
 SELECT e.schema_name,e.tables expected_tables,coalesce(a.tables,0) actual_tables,
 e.views expected_views,coalesce(a.views,0) actual_views,
 (e.tables=a.tables AND e.views=a.views) AS matches
 FROM expected e LEFT JOIN actual a USING(schema_name)
)
SELECT * FROM checks ORDER BY schema_name;

-- Required extension identities. Versions may vary by Supabase runtime.
SELECT e.name AS required_extension, x.extversion AS installed_version,
       (x.oid IS NOT NULL) AS installed
FROM (VALUES ('btree_gist'),('pgcrypto'),('uuid-ossp'),('supabase_vault'),
             ('pg_stat_statements'),('plpgsql')) AS e(name)
LEFT JOIN pg_extension x ON x.extname=e.name
ORDER BY e.name;

-- Security invariant: exposed application tables require RLS.
SELECT n.nspname,c.relname
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('public','platform','reservations')
  AND c.relkind IN ('r','p') AND NOT c.relrowsecurity
ORDER BY 1,2;
