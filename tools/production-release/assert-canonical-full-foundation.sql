-- FAIL-CLOSED, read-only verification. Run with psql -v ON_ERROR_STOP=1.
-- Only after a clean bootstrap in a disposable Supabase-compatible database.
-- Expected counts are Development 2026-11-09, not a replacement for structural fingerprints.
DO $foundation_acceptance$
DECLARE
  mismatch_count integer;
  missing_extensions text;
  unprotected_tables text;
BEGIN
  WITH expected(schema_name,tables,views) AS (
    VALUES ('public',46,0),('platform',13,0),('platform_private',11,0),
           ('reservations',15,2),('reservations_private',1,0)
  ), actual AS (
    SELECT n.nspname::text schema_name,
      count(*) FILTER (WHERE c.relkind IN ('r','p'))::integer tables,
      count(*) FILTER (WHERE c.relkind='v')::integer views
    FROM pg_namespace n LEFT JOIN pg_class c ON c.relnamespace=n.oid
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
    GROUP BY n.nspname
  )
  SELECT count(*) INTO mismatch_count FROM expected e LEFT JOIN actual a USING(schema_name)
  WHERE a.schema_name IS NULL OR a.tables <> e.tables OR a.views <> e.views;
  IF mismatch_count > 0 THEN
    RAISE EXCEPTION 'FOUNDATION_OBJECT_COUNT_MISMATCH: % schema(s)', mismatch_count;
  END IF;

  SELECT string_agg(required.name, ', ' ORDER BY required.name) INTO missing_extensions
  FROM (VALUES ('btree_gist'),('pgcrypto'),('uuid-ossp'),('supabase_vault'),
               ('pg_stat_statements'),('plpgsql')) AS required(name)
  LEFT JOIN pg_extension installed ON installed.extname=required.name
  WHERE installed.oid IS NULL;
  IF missing_extensions IS NOT NULL THEN
    RAISE EXCEPTION 'FOUNDATION_MISSING_EXTENSIONS: %',missing_extensions;
  END IF;

  SELECT string_agg(format('%I.%I',n.nspname,c.relname), ', ' ORDER BY n.nspname,c.relname)
  INTO unprotected_tables
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','platform','reservations')
    AND c.relkind IN ('r','p') AND NOT c.relrowsecurity;
  IF unprotected_tables IS NOT NULL THEN
    RAISE EXCEPTION 'FOUNDATION_RLS_DISABLED: %',unprotected_tables;
  END IF;
  RAISE NOTICE 'FOUNDATION_ACCEPTANCE_PASS: objects/extensions/RLS';
END
$foundation_acceptance$;
