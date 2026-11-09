-- Read-only, fail-closed security gate for Development and a clean disposable bootstrap.
-- Never reads secret hashes, auth rows, device rows, or reservation data.
DO $security$
DECLARE
  private_table oid := to_regclass('reservations_private.manual_person_identity_challenges');
  required record;
  fn oid;
BEGIN
  IF private_table IS NULL THEN
    RAISE EXCEPTION 'OWNER_DEVICE_SECURITY_MISSING_PRIVATE_TABLE';
  END IF;
  IF has_table_privilege('anon',private_table,'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated',private_table,'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'OWNER_DEVICE_SECURITY_PRIVATE_TABLE_EXPOSED';
  END IF;
  FOR required IN SELECT * FROM (VALUES
    ('platform.complete_device_binding_recovery(uuid,uuid,uuid,uuid,uuid,text,jsonb,text,uuid,bytea,timestamptz,timestamptz)',false),
    ('platform.complete_device_ownership_handoff(uuid,uuid,uuid,uuid,text,jsonb,uuid,bytea,timestamptz,timestamptz)',false),
    ('platform.enroll_new_device_key(uuid,uuid,text,text,jsonb,text,text,text,text)',false),
    ('platform.get_my_device_key_binding_status()',true),
    ('public.complete_first_system_bootstrap(text,uuid,text,text,uuid)',true),
    ('public.get_first_system_bootstrap_status()',true)
  ) AS t(signature,authenticated_allowed)
  LOOP
    fn := to_regprocedure(required.signature);
    IF fn IS NULL THEN
      RAISE EXCEPTION 'OWNER_DEVICE_SECURITY_MISSING_ROUTINE: %',required.signature;
    END IF;
    IF NOT (SELECT p.prosecdef AND p.proconfig IS NOT NULL
            FROM pg_proc p WHERE p.oid=fn) THEN
      RAISE EXCEPTION 'OWNER_DEVICE_SECURITY_ROUTINE_NOT_HARDENED: %',required.signature;
    END IF;
    IF has_function_privilege('anon',fn,'EXECUTE') THEN
      RAISE EXCEPTION 'OWNER_DEVICE_SECURITY_ANON_EXECUTE: %',required.signature;
    END IF;
    IF has_function_privilege('authenticated',fn,'EXECUTE') <> required.authenticated_allowed THEN
      RAISE EXCEPTION 'OWNER_DEVICE_SECURITY_AUTH_EXECUTE_DRIFT: %',required.signature;
    END IF;
  END LOOP;
  RAISE NOTICE 'OWNER_DEVICE_SECURITY_PASS';
END
$security$;
