-- Canonical schema fingerprint. READ ONLY. No business rows, secrets or user IDs.
-- Run against authoritative Development and clean disposable bootstrap target.
-- Match all counts and MD5 digests after bootstrap; a match is necessary, not sufficient.
WITH rels AS (
 SELECT concat_ws(':',n.nspname||'.'||c.relname,c.relkind::text,c.relrowsecurity::text) AS item
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
 AND c.relkind IN ('r','p','v')
), cols AS (
 SELECT concat_ws(':',n.nspname||'.'||c.relname||'.'||a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull::text) AS item
 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
 AND c.relkind IN ('r','p','v') AND a.attnum>0 AND NOT a.attisdropped
), funcs AS (
 SELECT concat_ws(':',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',md5(pg_get_functiondef(p.oid))) AS item
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
), policies AS (
 SELECT concat_ws(':',schemaname||'.'||tablename||'.'||policyname,cmd) AS item
 FROM pg_policies WHERE schemaname IN ('public','platform','platform_private','reservations','reservations_private')
)
SELECT 'relations' AS kind,count(*) AS objects,md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) AS digest FROM rels
UNION ALL SELECT 'columns',count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) FROM cols
UNION ALL SELECT 'functions',count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) FROM funcs
UNION ALL SELECT 'policies',count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) FROM policies;
