-- Read-only parity for schema USAGE and PUBLIC routine grants not covered by
-- assert-canonical-access-parity.sql. Captured from Development 2026-11-09.
DO $ambient$
DECLARE rec record;
BEGIN
  FOR rec IN
    WITH entries AS (
      SELECT 'schema:'||n.nspname||':'||r.rolname||':'||a.privilege_type item
      FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
      JOIN pg_roles r ON r.oid=a.grantee
      WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
        AND r.rolname IN ('anon','authenticated','service_role')
      UNION ALL
      SELECT 'relation:'||n.nspname||'.'||c.relname||':PUBLIC:'||a.privilege_type
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
        AND c.relkind IN ('r','p','v') AND a.grantee=0
      UNION ALL
      SELECT 'routine:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||'):PUBLIC:'||a.privilege_type
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
        AND a.grantee=0
    ), grouped AS (
      SELECT split_part(item,':',1) category,count(*) n,md5(string_agg(item,E'\n' ORDER BY item)) digest
      FROM entries GROUP BY 1
    ), expected(category,n,digest) AS (
      VALUES ('schema',6::bigint,'ec87bda22518ccbe562c36bc8cbd1911'),
             ('routine',12::bigint,'2d6a1083ca7bb8230a33b4ac0e824299'),
             ('relation',0::bigint,md5(''))
    )
    SELECT e.category,e.n expected_count,e.digest expected_digest,
           coalesce(g.n,0) actual_count,coalesce(g.digest,md5('')) actual_digest
    FROM expected e LEFT JOIN grouped g USING(category)
  LOOP
    IF rec.actual_count<>rec.expected_count OR rec.actual_digest<>rec.expected_digest THEN
      RAISE EXCEPTION 'FOUNDATION_AMBIENT_GRANTS_FAILED: % expected %/% got %/%',
        rec.category,rec.expected_count,rec.expected_digest,rec.actual_count,rec.actual_digest;
    END IF;
  END LOOP;
  RAISE NOTICE 'FOUNDATION_AMBIENT_GRANTS_PASS';
END
$ambient$;
