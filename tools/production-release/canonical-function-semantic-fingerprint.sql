-- Read-only metadata fingerprint. Reads no function results or application rows.
SET search_path = public, pg_catalog;
WITH items AS (
  SELECT n.nspname schema_name,
    (n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')') signature,
    md5(concat_ws('|',p.prosrc,l.lanname,p.provolatile,p.prosecdef::text,p.proleakproof::text,
      p.proisstrict::text,p.proretset::text,p.proparallel,p.prokind,p.procost::text,p.prorows::text,
      coalesce(array_to_string(p.proconfig,E'\\x1f'),''),pg_get_function_result(p.oid))) semantic_digest
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
  WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
)
SELECT schema_name,count(*) objects,
       md5(string_agg(signature||':'||semantic_digest,E'\n' ORDER BY signature||':'||semantic_digest)) digest
FROM items GROUP BY schema_name ORDER BY schema_name;
