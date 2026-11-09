-- Read-only parity for ALTER DEFAULT PRIVILEGES in application schemas.
-- Development baseline captured 2026-11-09. No business or auth data accessed.
DO $defaults$
DECLARE actual_count bigint; actual_digest text;
BEGIN
  WITH entries AS (
    SELECT 'default:'||n.nspname||':'||owner.rolname||':'||
           coalesce(grantee.rolname,'PUBLIC')||':'||d.defaclobjtype::text||':'||
           x.privilege_type item
    FROM pg_default_acl d
    JOIN pg_namespace n ON n.oid=d.defaclnamespace
    JOIN pg_roles owner ON owner.oid=d.defaclrole
    CROSS JOIN LATERAL aclexplode(d.defaclacl) x
    LEFT JOIN pg_roles grantee ON grantee.oid=x.grantee
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
      AND (x.grantee=0 OR grantee.rolname IN ('anon','authenticated','service_role'))
  )
  SELECT count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),''))
  INTO actual_count,actual_digest FROM entries;
  IF actual_count<>72 OR actual_digest<>'39ee17cb37fffe5a58cebeb2b7ff3576' THEN
    RAISE EXCEPTION 'FOUNDATION_DEFAULT_GRANTS_FAILED: entries=% digest=%',
      actual_count,actual_digest;
  END IF;
  RAISE NOTICE 'FOUNDATION_DEFAULT_GRANTS_PASS';
END
$defaults$;
