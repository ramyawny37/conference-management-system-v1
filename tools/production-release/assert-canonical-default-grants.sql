-- Read-only parity for application-owned and Supabase-managed defaults.
-- The bootstrap creates postgres entries; the preserved public foundation owns
-- supabase_admin entries.  Both halves must match Development.
DO $defaults$
DECLARE rec record;
BEGIN
  FOR rec IN
    WITH entries AS (
      SELECT owner.rolname owner_name,'default:'||n.nspname||':'||owner.rolname||':'||
             coalesce(grantee.rolname,'PUBLIC')||':'||d.defaclobjtype::text||':'||x.privilege_type item
      FROM pg_default_acl d JOIN pg_namespace n ON n.oid=d.defaclnamespace
      JOIN pg_roles owner ON owner.oid=d.defaclrole
      CROSS JOIN LATERAL aclexplode(d.defaclacl) x LEFT JOIN pg_roles grantee ON grantee.oid=x.grantee
      WHERE n.nspname='public' AND owner.rolname IN ('postgres','supabase_admin')
        AND grantee.rolname IN ('anon','authenticated','service_role')
    ), actual AS (
      SELECT owner_name,count(*) n,md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) digest
      FROM entries GROUP BY owner_name
    ), expected(owner_name,n,digest) AS (
      VALUES ('postgres',36::bigint,'f4ec4740b3d992216d6d403d7f760453'),
             ('supabase_admin',36::bigint,'3c69f7d61b77f987031642826d96677b')
    )
    SELECT e.owner_name,e.n expected_count,e.digest expected_digest,
           coalesce(a.n,0) actual_count,coalesce(a.digest,md5('')) actual_digest
    FROM expected e LEFT JOIN actual a USING(owner_name)
  LOOP
    IF rec.actual_count<>rec.expected_count OR rec.actual_digest<>rec.expected_digest THEN
      RAISE EXCEPTION 'FOUNDATION_DEFAULT_GRANTS_FAILED: owner=% expected=%/% actual=%/%',
        rec.owner_name,rec.expected_count,rec.expected_digest,rec.actual_count,rec.actual_digest;
    END IF;
  END LOOP;
  RAISE NOTICE 'FOUNDATION_DEFAULT_GRANTS_PASS';
END
$defaults$;
