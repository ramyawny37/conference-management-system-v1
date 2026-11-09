-- Read-only access parity gate, captured from Development 2026-11-09.
-- Checks effective explicit/default ACL entries for anon/authenticated/service_role.
-- Must be executed on a disposable clean bootstrap after grants are restored.
DO $access$
DECLARE actual_count bigint; actual_digest text;
BEGIN
  WITH grants AS (
    SELECT 'relation:'||n.nspname||'.'||c.relname||':'||r.rolname||':'||a.privilege_type item
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
    JOIN pg_roles r ON r.oid=a.grantee
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
      AND c.relkind IN ('r','p','v') AND r.rolname IN ('anon','authenticated','service_role')
    UNION ALL
    SELECT 'routine:'||n.nspname||'.'||pr.proname||'('||pg_get_function_identity_arguments(pr.oid)||'):'||r.rolname||':'||a.privilege_type
    FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
    CROSS JOIN LATERAL aclexplode(coalesce(pr.proacl,acldefault('f',pr.proowner))) a
    JOIN pg_roles r ON r.oid=a.grantee
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
      AND r.rolname IN ('anon','authenticated','service_role')
  )
  SELECT count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) INTO actual_count,actual_digest FROM grants;
  IF actual_count<>333 OR actual_digest<>'b1e472f24c24b730e934cd2d115a32af' THEN
    RAISE EXCEPTION 'FOUNDATION_ACCESS_PARITY_FAILED: entries=% digest=%',actual_count,actual_digest;
  END IF;
  RAISE NOTICE 'FOUNDATION_ACCESS_PARITY_PASS';
END
$access$;
