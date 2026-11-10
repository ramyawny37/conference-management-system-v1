-- Bounded read-only diagnostic for schemas whose semantic fingerprint can be
-- affected by the disposable managed-foundation contract.
SELECT n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' signature,
       md5(concat_ws('|',p.prosrc,l.lanname,p.provolatile,p.prosecdef::text,p.proleakproof::text,
         p.proisstrict::text,p.proretset::text,p.proparallel,p.prokind,p.procost::text,p.prorows::text,
         coalesce(array_to_string(p.proconfig,E'\\x1f'),''),pg_get_function_result(p.oid))) semantic_digest
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
WHERE n.nspname IN ('public','platform_private')
ORDER BY 1;
