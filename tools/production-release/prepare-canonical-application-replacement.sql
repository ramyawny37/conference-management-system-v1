-- Execute inside the one cutover transaction, before the canonical bootstrap.
-- Locks and classifies existing application data, blocks managed-schema
-- dependencies, preserves the Supabase-owned foundation, and removes application
-- objects. This immutable contract deliberately authorizes destruction of every
-- application row; it is not a runtime switch and cannot be used as a guard bypass.
DO $replacement_data_contract$
DECLARE
  rec record;
  has_rows boolean;
  operational_tables text;
  replaceable_platform_tables text;
  destructive_replacement_scope constant text := 'ALL_APPLICATION_DATA';
BEGIN
  FOR rec IN
    SELECT n.nspname,c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','platform','platform_private','reservations','reservations_private')
      AND c.relkind IN ('r','p')
    ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('LOCK TABLE %I.%I IN ACCESS EXCLUSIVE MODE',rec.nspname,rec.relname);
  END LOOP;

  -- Old platform audit, catalog, account, authorization and settings state is
  -- control-plane state owned by the application replacement. It is never
  -- migrated or replayed; the canonical catalog is seeded after replacement.
  FOR rec IN
    SELECT n.nspname,c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('platform','platform_private')
      AND c.relkind IN ('r','p')
    ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I.%I LIMIT 1)',rec.nspname,rec.relname) INTO has_rows;
    IF has_rows THEN
      replaceable_platform_tables := concat_ws(', ',replaceable_platform_tables,format('%I.%I',rec.nspname,rec.relname));
    END IF;
  END LOOP;

  -- Public, reservations and reservations_private hold business/operational data
  -- (conference, reservations, people, payments, accommodation, transport, and
  -- any future application tables). Presence is fail-closed unless this reviewed
  -- contract explicitly authorizes destruction of all application data.
  FOR rec IN
    SELECT n.nspname,c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','reservations','reservations_private')
      AND c.relkind IN ('r','p')
    ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I.%I LIMIT 1)',rec.nspname,rec.relname) INTO has_rows;
    IF has_rows THEN
      operational_tables := concat_ws(', ',operational_tables,format('%I.%I',rec.nspname,rec.relname));
    END IF;
  END LOOP;

  IF operational_tables IS NOT NULL AND destructive_replacement_scope <> 'ALL_APPLICATION_DATA' THEN
    RAISE EXCEPTION 'CUTOVER_OPERATIONAL_DATA_PRESENT: %',operational_tables;
  END IF;
  IF destructive_replacement_scope <> 'ALL_APPLICATION_DATA' THEN
    RAISE EXCEPTION 'CUTOVER_DESTRUCTIVE_REPLACEMENT_SCOPE_INVALID: %',destructive_replacement_scope;
  END IF;
  IF replaceable_platform_tables IS NOT NULL THEN
    RAISE NOTICE 'CUTOVER_REPLACEABLE_PLATFORM_STATE_AUTHORIZED: %',replaceable_platform_tables;
  END IF;
  IF operational_tables IS NOT NULL THEN
    RAISE NOTICE 'CUTOVER_ALL_APPLICATION_DATA_DESTRUCTION_AUTHORIZED: %',operational_tables;
  END IF;
  RAISE NOTICE 'CUTOVER_APPLICATION_DATA_CONTRACT_PASS: scope=%',destructive_replacement_scope;
END
$replacement_data_contract$;

DO $dependencies$
DECLARE blockers text;
BEGIN
  WITH app_schemas(name) AS (
    VALUES ('public'),('platform'),('platform_private'),('reservations'),('reservations_private')
  ), blocked AS (
    SELECT format('trigger:%I.%I',rn.nspname,t.tgname) item
    FROM pg_trigger t
    JOIN pg_class r ON r.oid=t.tgrelid JOIN pg_namespace rn ON rn.oid=r.relnamespace
    JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace pn ON pn.oid=p.pronamespace
    WHERE rn.nspname NOT IN (SELECT name FROM app_schemas)
      AND pn.nspname IN (SELECT name FROM app_schemas) AND NOT t.tgisinternal
    UNION ALL
    SELECT format('foreign-key:%I.%I',rn.nspname,c.conname)
    FROM pg_constraint c
    JOIN pg_class r ON r.oid=c.conrelid JOIN pg_namespace rn ON rn.oid=r.relnamespace
    JOIN pg_class target ON target.oid=c.confrelid JOIN pg_namespace tn ON tn.oid=target.relnamespace
    WHERE c.contype='f' AND rn.nspname NOT IN (SELECT name FROM app_schemas)
      AND tn.nspname IN (SELECT name FROM app_schemas)
    UNION ALL
    SELECT DISTINCT format('%s:%I.%I',CASE v.relkind WHEN 'm' THEN 'materialized-view' ELSE 'view' END,vn.nspname,v.relname)
    FROM pg_rewrite rw JOIN pg_class v ON v.oid=rw.ev_class JOIN pg_namespace vn ON vn.oid=v.relnamespace
    JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=rw.oid
    JOIN pg_class source ON d.refclassid='pg_class'::regclass AND source.oid=d.refobjid
    JOIN pg_namespace sn ON sn.oid=source.relnamespace
    WHERE v.relkind IN ('v','m') AND vn.nspname NOT IN (SELECT name FROM app_schemas)
      AND sn.nspname IN (SELECT name FROM app_schemas)
  )
  SELECT string_agg(item,', ' ORDER BY item) INTO blockers FROM blocked;
  IF blockers IS NOT NULL THEN RAISE EXCEPTION 'CUTOVER_MANAGED_DEPENDENCY_BLOCKED: %',blockers; END IF;
  RAISE NOTICE 'CUTOVER_MANAGED_DEPENDENCY_PASS';
END
$dependencies$;

-- Supabase-managed defaults are a precondition and remain attached to the
-- preserved public namespace throughout replacement.
DO $managed_defaults$
DECLARE n bigint; digest text;
BEGIN
  IF to_regclass('auth.users') IS NULL
     OR NOT has_table_privilege(current_user,'auth.users','REFERENCES') THEN
    RAISE EXCEPTION 'SUPABASE_MANAGED_AUTH_USERS_REFERENCES_MISSING';
  END IF;
  WITH entries AS (
    SELECT 'default:'||ns.nspname||':'||owner.rolname||':'||coalesce(grantee.rolname,'PUBLIC')||':'||
           d.defaclobjtype::text||':'||x.privilege_type item
    FROM pg_default_acl d JOIN pg_namespace ns ON ns.oid=d.defaclnamespace
    JOIN pg_roles owner ON owner.oid=d.defaclrole
    CROSS JOIN LATERAL aclexplode(d.defaclacl) x LEFT JOIN pg_roles grantee ON grantee.oid=x.grantee
    WHERE ns.nspname='public' AND owner.rolname='supabase_admin'
      AND grantee.rolname IN ('anon','authenticated','service_role')
  ) SELECT count(*),md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) INTO n,digest FROM entries;
  IF n<>36 OR digest<>'3c69f7d61b77f987031642826d96677b' THEN
    RAISE EXCEPTION 'SUPABASE_MANAGED_DEFAULT_GRANTS_MISSING: entries=% digest=%',n,digest;
  END IF;
  RAISE NOTICE 'SUPABASE_MANAGED_DEFAULT_GRANTS_PASS';
END
$managed_defaults$;

DROP SCHEMA IF EXISTS "reservations_private" CASCADE;
DROP SCHEMA IF EXISTS "reservations" CASCADE;
DROP SCHEMA IF EXISTS "platform_private" CASCADE;
DROP SCHEMA IF EXISTS "platform" CASCADE;

-- public is a managed namespace because managed default ACLs reference its OID.
-- Remove only application objects; never DROP SCHEMA public.
DO $clear_public_relations$
DECLARE rec record;
BEGIN
  FOR rec IN
    SELECT c.relkind,n.nspname,c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S','f')
    ORDER BY CASE WHEN c.relkind IN ('r','p','f') THEN 0 ELSE 1 END,c.relname
  LOOP
    EXECUTE format('DROP %s %I.%I CASCADE',CASE rec.relkind
      WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE'
      WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,rec.nspname,rec.relname);
  END LOOP;
END
$clear_public_relations$;

DO $clear_public_routines$
DECLARE rec record;
BEGIN
  FOR rec IN
    SELECT p.oid,p.prokind,n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
  LOOP
    IF rec.prokind='a' THEN
      EXECUTE format('DROP AGGREGATE %I.%I(%s) CASCADE',rec.nspname,rec.proname,rec.args);
    ELSE
      EXECUTE format('DROP ROUTINE %I.%I(%s) CASCADE',rec.nspname,rec.proname,rec.args);
    END IF;
  END LOOP;
END
$clear_public_routines$;

DO $clear_public_types$
DECLARE rec record;
BEGIN
  FOR rec IN
    SELECT n.nspname,t.typname
    FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='public' AND t.typrelid=0 AND t.typelem=0
  LOOP EXECUTE format('DROP TYPE %I.%I CASCADE',rec.nspname,rec.typname); END LOOP;
END
$clear_public_types$;
