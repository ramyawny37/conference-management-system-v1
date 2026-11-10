-- Execute after the canonical application bootstrap and before assertions,
-- inside the same outer cutover transaction.
CREATE TRIGGER auth_users_create_profile
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

CREATE TRIGGER platform_auth_user_provisioned
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION platform_private.provision_auth_user();

DO $assert_canonical_auth_integration$
DECLARE blockers text; unexpected text;
BEGIN
  WITH expected(trigger_name,function_name) AS (
    VALUES
      ('auth_users_create_profile','public.handle_new_user_profile()'),
      ('platform_auth_user_provisioned','platform_private.provision_auth_user()')
  ), invalid AS (
    SELECT expected.trigger_name
    FROM expected
    LEFT JOIN pg_trigger trigger_definition
      ON trigger_definition.tgrelid='auth.users'::regclass
     AND trigger_definition.tgname=expected.trigger_name
     AND NOT trigger_definition.tgisinternal
    WHERE trigger_definition.oid IS NULL
       OR trigger_definition.tgfoid<>to_regprocedure(expected.function_name)
       OR trigger_definition.tgtype<>5
       OR trigger_definition.tgenabled<>'O'
       OR trigger_definition.tgnargs<>0
  )
  SELECT string_agg(trigger_name,', ' ORDER BY trigger_name) INTO blockers FROM invalid;
  IF blockers IS NOT NULL THEN
    RAISE EXCEPTION 'CANONICAL_AUTH_INTEGRATION_ASSERTION_FAILED: %',blockers;
  END IF;

  SELECT string_agg(trigger_definition.tgname,', ' ORDER BY trigger_definition.tgname)
  INTO unexpected
  FROM pg_trigger trigger_definition
  JOIN pg_proc function_definition ON function_definition.oid=trigger_definition.tgfoid
  JOIN pg_namespace function_schema ON function_schema.oid=function_definition.pronamespace
  WHERE trigger_definition.tgrelid='auth.users'::regclass
    AND NOT trigger_definition.tgisinternal
    AND function_schema.nspname IN ('public','platform','platform_private','reservations','reservations_private')
    AND trigger_definition.tgname NOT IN ('auth_users_create_profile','platform_auth_user_provisioned');
  IF unexpected IS NOT NULL THEN
    RAISE EXCEPTION 'CANONICAL_AUTH_INTEGRATION_UNEXPECTED_TRIGGER: %',unexpected;
  END IF;
  RAISE NOTICE 'CANONICAL_AUTH_INTEGRATION_PASS';
END
$assert_canonical_auth_integration$;
