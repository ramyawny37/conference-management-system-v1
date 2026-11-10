-- Read-only exact structural parity gate for a clean, disposable Supabase-compatible target.
-- Fingerprints captured from Development on 2026-11-09. No data is read or copied.
-- Run with psql -X -v ON_ERROR_STOP=1 after the full foundation has been applied.
DO $parity$
DECLARE mismatches text;
BEGIN
  WITH rels AS (
    SELECT concat_ws(':',n.nspname||'.'||c.relname,c.relkind::text,c.relrowsecurity::text) item
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
      AND c.relkind IN ('r','p','v')
  ), cols AS (
    SELECT concat_ws(':',n.nspname||'.'||c.relname||'.'||a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull::text) item
    FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
      AND c.relkind IN ('r','p','v') AND a.attnum>0 AND NOT a.attisdropped
  ), funcs AS (
    SELECT concat_ws(':',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',md5(pg_get_functiondef(p.oid))) item
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
  ), policies AS (
    SELECT concat_ws(':',schemaname||'.'||tablename||'.'||policyname,cmd) item
    FROM pg_policies WHERE schemaname IN ('public','platform','platform_private','reservations','reservations_private')
  ), actual AS (
    SELECT 'relations' kind,count(*) objects,md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) digest FROM rels
    UNION ALL SELECT 'columns',count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) FROM cols
    UNION ALL SELECT 'functions',count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) FROM funcs
    UNION ALL SELECT 'policies',count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) FROM policies
  ), expected(kind,objects,digest) AS (
    VALUES
    ('relations',88::bigint,'97a500834dce377bdf487f4d6b8428ce'),
    ('columns',1103::bigint,'dc306aebb9918d6e944499fce8a158c9'),
    ('functions',279::bigint,'85f1b50ea2fcf095d0301c4ad0bbee5b'),
    ('policies',15::bigint,'be7f4626d990e0ef83d30fd648cfd9b5')
  )
  SELECT string_agg(format('%s expected=%s/%s actual=%s/%s',e.kind,e.objects,e.digest,a.objects,a.digest), E'\n')
  INTO mismatches
  FROM expected e LEFT JOIN actual a USING(kind)
  WHERE a.kind IS NULL OR e.objects<>a.objects OR e.digest<>a.digest;
  IF mismatches IS NOT NULL THEN
    RAISE NOTICE 'FUNCTION_SCHEMA_DIGESTS: %', (
      SELECT string_agg(format('%s=%s/%s', schema_name, objects, digest), ', ' ORDER BY schema_name)
      FROM (
        SELECT n.nspname schema_name, count(*) objects,
               md5(string_agg(concat_ws(':',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',md5(pg_get_functiondef(p.oid))), E'\\n' ORDER BY concat_ws(':',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',md5(pg_get_functiondef(p.oid))))) digest
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
        GROUP BY n.nspname
      ) d
    );
    RAISE NOTICE 'FUNCTION_SOURCE_DIGESTS: %', (
      SELECT string_agg(format('%s=%s/%s', schema_name, objects, digest), ', ' ORDER BY schema_name)
      FROM (
        SELECT n.nspname schema_name, count(*) objects,
               md5(string_agg((n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')')||':'||md5(p.prosrc), E'\\n' ORDER BY (n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')')||':'||md5(p.prosrc))) digest
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
        GROUP BY n.nspname
      ) d
    );
    RAISE EXCEPTION 'FOUNDATION_STRUCTURAL_PARITY_FAILED: %',mismatches;
  END IF;
  RAISE NOTICE 'FOUNDATION_STRUCTURAL_PARITY_PASS';
END
$parity$;
